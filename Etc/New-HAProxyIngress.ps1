<#
.SYNOPSIS
Safely duplicates simple NGINX Ingress resources for HAProxy.

.DESCRIPTION
The default mode is read-only. The script appends HAProxy copies to the same
manifest, clones name-specific Kustomize patches, and removes DNS ownership
annotations from the HAProxy copy. It refuses to apply a repository-wide plan
when NGINX-specific annotations or patches require semantic translation.

.EXAMPLE
.\Copy-NginxIngressToHAProxy.ps1 -RepoPath C:\appl\repos\wl-skogve

.EXAMPLE
.\Copy-NginxIngressToHAProxy.ps1 -RepoPath C:\appl\repos\wl-skogve -Apply

.EXAMPLE
.\Copy-NginxIngressToHAProxy.ps1 -RepoPath C:\appl\repos\wl-example -IncludeImplicitNginx
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $RepoPath,

    [switch] $Apply,

    [switch] $IncludeImplicitNginx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path -LiteralPath $RepoPath).Path
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$nameSuffix = '-haproxy'
$haproxyClass = 'haproxy-internal'

function Get-NewLine {
    param([string] $Text)

    if ($Text.Contains("`r`n")) {
        return "`r`n"
    }

    return "`n"
}

function Get-YamlDocuments {
    param([string] $Text)

    return [regex]::Split($Text, '(?m)^\s*---\s*(?:#.*)?\r?\n') |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
}

function Get-IngressMetadata {
    param([string] $Document)

    if ($Document -notmatch '(?m)^kind:\s*Ingress\s*$') {
        return $null
    }

    $metadata = [regex]::Match(
        $Document,
        '(?ms)^metadata:\s*\r?\n(?<body>.*?)(?=^[A-Za-z][A-Za-z0-9-]*:\s*)'
    )
    if (-not $metadata.Success) {
        throw 'Ingress has no parseable metadata block.'
    }

    $nameMatch = [regex]::Match($metadata.Groups['body'].Value, '(?m)^\s{2}name:\s*(?<name>[^#\r\n]+?)\s*(?:#.*)?$')
    if (-not $nameMatch.Success) {
        throw 'Ingress has no parseable metadata.name.'
    }

    $classMatch = [regex]::Match($Document, '(?m)^\s{2}ingressClassName:\s*(?<class>[^#\r\n]+?)\s*(?:#.*)?$')
    $nginxAnnotations = [regex]::Matches(
        $metadata.Groups['body'].Value,
        '(?m)^\s{4}(?<name>nginx(?:\.ingress)?\.[^:]+):'
    ) | ForEach-Object { $_.Groups['name'].Value }

    [pscustomobject]@{
        Name             = $nameMatch.Groups['name'].Value.Trim().Trim('"', "'")
        Class            = if ($classMatch.Success) { $classMatch.Groups['class'].Value.Trim().Trim('"', "'") } else { $null }
        NginxAnnotations = @($nginxAnnotations)
    }
}

function Remove-DnsAnnotations {
    param(
        [string] $Document,
        [string] $NewLine
    )

    $result = [regex]::Replace(
        $Document,
        '(?m)^\s{4}miljodir/(?:public|private)-dns:\s*[^\r\n]*(?:\r?\n|$)',
        ''
    )

    # Avoid leaving metadata.annotations as null when DNS was its only entry.
    $result = [regex]::Replace(
        $result,
        '(?m)^\s{2}annotations:\s*\r?\n(?=(?:\s*\r?\n)*^\S)',
        ''
    )

    return $result
}

function New-HaproxyIngressDocument {
    param(
        [string] $Document,
        [string] $OriginalName,
        [string] $NewLine
    )

    $metadata = [regex]::Match(
        $Document,
        '(?ms)^metadata:\s*\r?\n(?<body>.*?)(?=^[A-Za-z][A-Za-z0-9-]*:\s*)'
    )
    $updatedMetadata = [regex]::Replace(
        $metadata.Value,
        '(?m)^(\s{2}name:\s*)([^#\r\n]+?)(\s*(?:#.*)?)$',
        "`${1}$OriginalName$nameSuffix`${3}",
        1
    )
    $clone = $Document.Substring(0, $metadata.Index) +
        $updatedMetadata +
        $Document.Substring($metadata.Index + $metadata.Length)

    if ($clone -match '(?m)^\s{2}ingressClassName:') {
        $clone = [regex]::Replace(
            $clone,
            '(?m)^(\s{2}ingressClassName:\s*)[^#\r\n]+?(\s*(?:#.*)?)$',
            "`${1}$haproxyClass`${2}",
            1
        )
    }
    else {
        $clone = [regex]::Replace(
            $clone,
            '(?m)^spec:\s*$',
            "spec:$NewLine  ingressClassName: $haproxyClass",
            1
        )
    }

    return Remove-DnsAnnotations -Document $clone -NewLine $NewLine
}

function Remove-DnsPatchOperations {
    param([string] $PatchItem)

    $operationPattern = '(?ms)^\s{6}- op:\s*.*?(?=^\s{6}- op:|^\s{4}target:|\z)'
    return [regex]::Replace(
        $PatchItem,
        $operationPattern,
        {
            param($match)
            if ($match.Value -match '/metadata/annotations/miljodir~1(?:public|private)-dns') {
                return ''
            }
            return $match.Value
        }
    )
}

function Get-KustomizationChanges {
    param(
        [string] $Path,
        [hashtable] $IngressNames
    )

    $raw = [System.IO.File]::ReadAllText($Path)
    $newLine = Get-NewLine -Text $raw
    $lines = [regex]::Split($raw, '\r?\n')
    $insertions = [System.Collections.Generic.List[object]]::new()
    $blockers = [System.Collections.Generic.List[string]]::new()

    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -notmatch '^\s{2}-\s') {
            continue
        }

        $end = $index + 1
        while ($end -lt $lines.Count -and $lines[$end] -notmatch '^\s{2}-\s' -and $lines[$end] -notmatch '^\S') {
            $end++
        }

        $itemLines = $lines[$index..($end - 1)]
        $item = $itemLines -join $newLine
        if ($item -notmatch '(?m)^\s{6}kind:\s*Ingress\s*$') {
            $index = $end - 1
            continue
        }

        if ($item -match '(?m)^\s{6}name:\s*(?<name>[^#\r\n]+?)\s*(?:#.*)?$') {
            $originalName = $Matches['name'].Trim().Trim('"', "'")
            if (-not $IngressNames.ContainsKey($originalName)) {
                $index = $end - 1
                continue
            }

            if ($item -match 'nginx(?:\.ingress)?\.' -or $item -match '/spec/ingressClassName') {
                $blockers.Add("$Path targets '$originalName' with NGINX-specific or ingress-class changes.")
                $index = $end - 1
                continue
            }

            $haproxyName = "$originalName$nameSuffix"
            if ($raw -match "(?m)^\s{6}name:\s*$([regex]::Escape($haproxyName))\s*(?:#.*)?$") {
                $index = $end - 1
                continue
            }

            $clone = [regex]::Replace(
                $item,
                '(?m)^(\s{6}name:\s*)[^#\r\n]+?(\s*(?:#.*)?)$',
                "`${1}$haproxyName`${2}",
                1
            )
            $clone = Remove-DnsPatchOperations -PatchItem $clone
            $insertions.Add([pscustomobject]@{
                AfterLine = $end - 1
                Text      = $clone
                Name      = $originalName
            })
        }
        elseif ($item -match 'nginx(?:\.ingress)?\.' -or $item -match '/spec/ingressClassName') {
            $blockers.Add("$Path has a generic Ingress patch with NGINX-specific or ingress-class changes.")
        }

        $index = $end - 1
    }

    if ($insertions.Count -eq 0) {
        return [pscustomobject]@{
            Path     = $Path
            Content  = $raw
            Changes  = @()
            Blockers = @($blockers)
        }
    }

    $output = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $output.Add($lines[$index])
        foreach ($insertion in $insertions | Where-Object AfterLine -eq $index) {
            foreach ($line in [regex]::Split($insertion.Text, '\r?\n')) {
                $output.Add($line)
            }
        }
    }

    [pscustomobject]@{
        Path     = $Path
        Content  = $output -join $newLine
        Changes  = @($insertions)
        Blockers = @($blockers)
    }
}

$sourcePlans = [System.Collections.Generic.List[object]]::new()
$blockers = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()
$ingressNames = @{}

$yamlFiles = Get-ChildItem -LiteralPath $repo -Recurse -File -Include '*.yaml', '*.yml' |
    Where-Object {
        $_.FullName -notmatch '[\\/]\.git[\\/]' -and
        $_.Name -notmatch '^(?:kustomization|fluxkustomization)\.ya?ml$'
    }

foreach ($file in $yamlFiles) {
    $raw = [System.IO.File]::ReadAllText($file.FullName)
    $newLine = Get-NewLine -Text $raw
    $clones = [System.Collections.Generic.List[string]]::new()

    foreach ($document in Get-YamlDocuments -Text $raw) {
        $metadata = Get-IngressMetadata -Document $document
        if ($null -eq $metadata) {
            continue
        }

        $isExplicitNginx = $metadata.Class -eq 'nginx'
        $hasNginxAnnotations = $metadata.NginxAnnotations.Count -gt 0
        $isImplicitNginx = [string]::IsNullOrWhiteSpace($metadata.Class)
        if (-not $isExplicitNginx -and -not $hasNginxAnnotations -and -not ($IncludeImplicitNginx -and $isImplicitNginx)) {
            continue
        }

        if ($metadata.Name.EndsWith($nameSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
            continue
        }

        if ($hasNginxAnnotations) {
            $blockers.Add(
                "$($file.FullName): ingress '$($metadata.Name)' uses unsupported NGINX annotations: " +
                ($metadata.NginxAnnotations -join ', ')
            )
            continue
        }

        if ($isImplicitNginx) {
            $warnings.Add("$($file.FullName): treating implicit ingress '$($metadata.Name)' as NGINX.")
        }

        $haproxyName = "$($metadata.Name)$nameSuffix"
        if ($raw -match "(?m)^\s{2}name:\s*$([regex]::Escape($haproxyName))\s*(?:#.*)?$") {
            continue
        }

        $clone = New-HaproxyIngressDocument `
            -Document $document `
            -OriginalName $metadata.Name `
            -NewLine $newLine
        $clones.Add($clone.TrimEnd("`r", "`n"))
        $ingressNames[$metadata.Name] = $true
    }

    if ($clones.Count -gt 0) {
        $content = $raw.TrimEnd("`r", "`n")
        foreach ($clone in $clones) {
            $content += "$newLine---$newLine$clone"
        }
        $content += $newLine

        $sourcePlans.Add([pscustomobject]@{
            Path    = $file.FullName
            Content = $content
            Count   = $clones.Count
        })
    }
}

$kustomizationPlans = [System.Collections.Generic.List[object]]::new()
if ($ingressNames.Count -gt 0) {
    $kustomizationFiles = Get-ChildItem -LiteralPath $repo -Recurse -File -Include 'kustomization.yaml', 'kustomization.yml' |
        Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' }

    foreach ($file in $kustomizationFiles) {
        $plan = Get-KustomizationChanges -Path $file.FullName -IngressNames $ingressNames
        foreach ($blocker in $plan.Blockers) {
            $blockers.Add($blocker)
        }
        if ($plan.Changes.Count -gt 0) {
            $kustomizationPlans.Add($plan)
        }
    }
}

Write-Output "Repository: $repo"
Write-Output "Mode: $(if ($Apply) { 'apply' } else { 'dry-run' })"
foreach ($plan in $sourcePlans) {
    Write-Output "DUPLICATE $($plan.Count) ingress(es): $($plan.Path)"
}
foreach ($plan in $kustomizationPlans) {
    foreach ($change in $plan.Changes) {
        Write-Output "CLONE PATCH for '$($change.Name)': $($plan.Path)"
    }
}
foreach ($warning in $warnings) {
    Write-Warning $warning
}
foreach ($blocker in $blockers) {
    Write-Warning "BLOCKED: $blocker"
}

if ($Apply -and $blockers.Count -gt 0) {
    throw "No files changed because $($blockers.Count) unsafe transformation(s) require manual review."
}

if ($Apply) {
    foreach ($plan in $sourcePlans) {
        if ($PSCmdlet.ShouldProcess($plan.Path, 'append HAProxy ingress duplicate')) {
            [System.IO.File]::WriteAllText($plan.Path, $plan.Content, $utf8NoBom)
        }
    }
    foreach ($plan in $kustomizationPlans) {
        if ($PSCmdlet.ShouldProcess($plan.Path, 'clone Ingress patch target for HAProxy')) {
            [System.IO.File]::WriteAllText($plan.Path, $plan.Content, $utf8NoBom)
        }
    }
}

Write-Output "Summary: $($sourcePlans.Count) manifest file(s), $($kustomizationPlans.Count) kustomization file(s), $($blockers.Count) blocker(s)."
