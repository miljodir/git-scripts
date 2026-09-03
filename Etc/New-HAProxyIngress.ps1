<#
.SYNOPSIS
Duplicates NGINX Ingress resources for HAProxy and translates known annotations.

.DESCRIPTION
The default mode is read-only. The script appends HAProxy copies to the same
manifest, preserves DNS ownership annotations, clones name-specific Kustomize
patches, and translates supported NGINX annotations. Unsupported annotations
are retained as comments with migration warnings for manual review.
Specify either RepoPath for one repository or WorkspacePath to process every
folder in a VS Code workspace. Relative workspace paths are resolved from the
directory containing the workspace file.

.EXAMPLE
.\New-HAProxyIngress.ps1 -RepoPath C:\appl\repos\wl-skogve

.EXAMPLE
.\New-HAProxyIngress.ps1 -RepoPath C:\appl\repos\wl-skogve -Apply

.EXAMPLE
.\New-HAProxyIngress.ps1 -WorkspacePath C:\appl\repos\wl-repos.code-workspace

.EXAMPLE
.\New-HAProxyIngress.ps1 -WorkspacePath C:\appl\repos\wl-repos.code-workspace -Apply
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Repository')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Repository')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $RepoPath,

    [Parameter(Mandatory, ParameterSetName = 'Workspace')]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Leaf })]
    [string] $WorkspacePath,

    [switch] $Apply,

    [switch] $IncludeImplicitNginx
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$nameSuffix = '-haproxy'
$haproxyClass = 'haproxy-internal'
$directAnnotationMappings = @{
    'nginx.ingress.kubernetes.io/auth-realm'              = 'haproxy.org/auth-realm'
    'nginx.ingress.kubernetes.io/auth-secret'             = 'haproxy.org/auth-secret'
    'nginx.ingress.kubernetes.io/auth-type'               = 'haproxy.org/auth-type'
    'nginx.ingress.kubernetes.io/cors-allow-credentials'  = 'haproxy.org/cors-allow-credentials'
    'nginx.ingress.kubernetes.io/cors-allow-headers'      = 'haproxy.org/cors-allow-headers'
    'nginx.ingress.kubernetes.io/cors-allow-methods'      = 'haproxy.org/cors-allow-methods'
    'nginx.ingress.kubernetes.io/cors-allow-origin'       = 'haproxy.org/cors-allow-origin'
    'nginx.ingress.kubernetes.io/cors-max-age'            = 'haproxy.org/cors-max-age'
    'nginx.ingress.kubernetes.io/denylist-source-range'   = 'haproxy.org/deny-list'
    'nginx.ingress.kubernetes.io/enable-cors'             = 'haproxy.org/cors-enable'
    'nginx.ingress.kubernetes.io/force-ssl-redirect'      = 'haproxy.org/ssl-redirect'
    'nginx.ingress.kubernetes.io/permanent-redirect-code' = 'haproxy.org/request-redirect-code'
    'nginx.ingress.kubernetes.io/ssl-passthrough'         = 'haproxy.org/ssl-passthrough'
    'nginx.ingress.kubernetes.io/ssl-redirect'            = 'haproxy.org/ssl-redirect'
    'nginx.ingress.kubernetes.io/temporal-redirect'       = 'haproxy.org/request-redirect'
    'nginx.ingress.kubernetes.io/temporal-redirect-code'  = 'haproxy.org/request-redirect-code'
    'nginx.ingress.kubernetes.io/upstream-vhost'          = 'haproxy.org/set-host'
    'nginx.ingress.kubernetes.io/whitelist-source-range'  = 'haproxy.org/allow-list'
}

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

function Get-AnnotationValue {
    param(
        [Parameter(Mandatory)][string] $Suffix
    )

    $match = [regex]::Match($Suffix, '^\s*(?<value>"[^"]*"|''[^'']*''|[^#]*?)\s*(?:#.*)?$')
    return $match.Groups['value'].Value.Trim()
}

function Convert-TimeoutValue {
    param([Parameter(Mandatory)][string] $Value)

    $unquoted = $Value.Trim().Trim('"', "'")
    if ($unquoted -match '^\d+(?:\.\d+)?$') {
        $unquoted += 's'
    }

    return '"' + $unquoted + '"'
}

function Get-HaproxyPathRewrite {
    param(
        [Parameter(Mandatory)][string] $Document,
        [Parameter(Mandatory)][string] $Target,
        [Parameter(Mandatory)][string] $Indent,
        [Parameter(Mandatory)][string] $NewLine
    )

    $replacement = $Target.Trim().Trim('"', "'")
    $replacement = [regex]::Replace($replacement, '\$(\d+)', '\${1}')
    $paths = @(
        [regex]::Matches($Document, '(?m)^\s+(?:-\s+)?path:\s*(?<path>[^\r\n]*?\S)(?:[ ]+#.*)?(?=\r?$)') |
            ForEach-Object { $_.Groups['path'].Value.Trim().Trim('"', "'") } |
            Select-Object -Unique
    )
    if ($paths.Count -eq 0) {
        return $null
    }

    if ($paths.Count -eq 1) {
        $rule = ($paths[0] + ' ' + $replacement).Replace("'", "''")
        return "$Indent" + "haproxy.org/path-rewrite: '$rule'"
    }

    $rules = $paths | ForEach-Object { "$Indent  $_ $replacement" }
    return "$Indent" + 'haproxy.org/path-rewrite: |' + $NewLine + ($rules -join $NewLine)
}

function Convert-NginxAnnotations {
    param(
        [Parameter(Mandatory)][string] $Document,
        [Parameter(Mandatory)][string] $NewLine,
        [System.Collections.Generic.List[string]] $Warnings,
        [Parameter(Mandatory)][string] $Source
    )

    $emittedAnnotations = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $annotationPattern = '(?m)^(?<indent>[ ]{4})(?<name>nginx(?:\.ingress\.kubernetes\.io|\.org)/[^:]+):(?<suffix>[^\r\n]*)(?=\r?$)'
    $blockAnnotationPattern = '(?ms)^(?<indent>[ ]{4})(?<name>nginx(?:\.ingress\.kubernetes\.io|\.org)/[^:]+):(?<suffix>[ ]*[|>][+-]?\d*[^\r\n]*)(?<body>(?:\r?\n(?:[ ]{6,}[^\r\n]*|[ ]*(?=\r?$)))*)'

    $convertedDocument = [regex]::Replace(
        $Document,
        $blockAnnotationPattern,
        {
            param($match)

            $indent = $match.Groups['indent'].Value
            $name = $match.Groups['name'].Value
            $Warnings.Add("${Source}: '$name' uses a block value and was commented out because no automatic HAProxy conversion is supported.")
            $lines = [regex]::Split($match.Value, '\r?\n')
            $commentedLines = [System.Collections.Generic.List[string]]::new()
            $commentedLines.Add(
                "$indent# $($lines[0].TrimStart()) # WARNING: HAProxy migration was not possible; review manually."
            )
            foreach ($line in $lines | Select-Object -Skip 1) {
                $commentedLines.Add("$indent# $($line.TrimStart())")
            }
            return $commentedLines -join $NewLine
        }
    )

    return [regex]::Replace(
        $convertedDocument,
        $annotationPattern,
        {
            param($match)

            $indent = $match.Groups['indent'].Value
            $name = $match.Groups['name'].Value
            $suffix = $match.Groups['suffix'].Value
            $value = Get-AnnotationValue -Suffix $suffix
            $targetName = $null
            $targetLine = $null
            $failureReason = $null

            if ($name -eq 'nginx.ingress.kubernetes.io/permanent-redirect') {
                $targetName = 'haproxy.org/request-redirect'
                $targetLine = "$indent$targetName`:$suffix"
                if ($Document -notmatch '(?m)^\s{4}nginx\.ingress\.kubernetes\.io/permanent-redirect-code:') {
                    $targetLine += "$NewLine$indent" + 'haproxy.org/request-redirect-code: "301"'
                    [void]$emittedAnnotations.Add('haproxy.org/request-redirect-code')
                }
            }
            elseif ($directAnnotationMappings.ContainsKey($name)) {
                $targetName = $directAnnotationMappings[$name]
                $targetLine = "$indent$targetName`:$suffix"
            }
            elseif ($name -eq 'nginx.ingress.kubernetes.io/rewrite-target') {
                $targetName = 'haproxy.org/path-rewrite'
                $targetLine = Get-HaproxyPathRewrite `
                    -Document $Document `
                    -Target $value `
                    -Indent $indent `
                    -NewLine $NewLine
                if ($null -eq $targetLine) {
                    $failureReason = 'no Ingress paths were found to build a path-rewrite rule'
                }
            }
            elseif ($name -in @(
                    'nginx.ingress.kubernetes.io/proxy-connect-timeout',
                    'nginx.ingress.kubernetes.io/proxy-read-timeout',
                    'nginx.ingress.kubernetes.io/proxy-send-timeout'
                )) {
                $targetName = if ($name -eq 'nginx.ingress.kubernetes.io/proxy-connect-timeout') {
                    'haproxy.org/timeout-check'
                }
                else {
                    'haproxy.org/timeout-server'
                }
                $targetLine = "$indent$targetName`: $(Convert-TimeoutValue -Value $value)"
            }
            elseif ($name -eq 'nginx.ingress.kubernetes.io/backend-protocol') {
                $protocol = $value.Trim().Trim('"', "'").ToUpperInvariant()
                $protocolAnnotations = switch ($protocol) {
                    'HTTPS' { @("$indent" + 'haproxy.org/server-ssl: "true"') }
                    'GRPC' { @("$indent" + 'haproxy.org/server-proto: "h2"') }
                    'GRPCS' {
                        @(
                            "$indent" + 'haproxy.org/server-proto: "h2"'
                            "$indent" + 'haproxy.org/server-ssl: "true"'
                        )
                    }
                    default { @() }
                }
                if ($protocolAnnotations.Count -gt 0) {
                    return $protocolAnnotations -join $NewLine
                }
            }

            if ($null -ne $targetLine -and $emittedAnnotations.Add($targetName)) {
                return $targetLine
            }

            $reason = if ($null -ne $failureReason) {
                $failureReason
            }
            elseif ($null -ne $targetName) {
                "mapping to '$targetName' conflicts with another translated annotation"
            }
            else {
                'no supported HAProxy Community annotation equivalent was found'
            }
            $Warnings.Add("${Source}: '$name' was commented out because $reason.")
            return "$indent# $name`:$suffix # WARNING: HAProxy migration was not possible; review manually."
        }
    )
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

    return $clone
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
        $itemStart = [regex]::Match($lines[$index], '^(?<indent> *)-\s')
        if (-not $itemStart.Success) {
            continue
        }

        $itemIndent = $itemStart.Groups['indent'].Value.Length
        $end = $index + 1
        while ($end -lt $lines.Count) {
            if ([string]::IsNullOrWhiteSpace($lines[$end])) {
                $end++
                continue
            }

            $lineIndent = [regex]::Match($lines[$end], '^ *').Value.Length
            if ($lineIndent -lt $itemIndent -or
                ($lineIndent -eq $itemIndent -and $lines[$end] -notmatch '^\s*#')) {
                break
            }
            $end++
        }

        $itemLines = $lines[$index..($end - 1)]
        $item = $itemLines -join $newLine
        $target = [regex]::Match($item, '(?ms)^\s*(?:-\s*)?target:\s*(?:#.*)?\r?\n(?<body>.*)$')
        if (-not $target.Success -or $target.Groups['body'].Value -notmatch '(?m)^\s+kind:\s*Ingress\s*$') {
            $index = $end - 1
            continue
        }

        if ($target.Groups['body'].Value -match '(?m)^\s+name:\s*(?<name>[^#\r\n]+?)\s*(?:#.*)?$') {
            $originalName = $Matches['name'].Trim().Trim('"', "'")
            if (-not $IngressNames.ContainsKey($originalName)) {
                $index = $end - 1
                continue
            }

            $translatedItem = $item
            foreach ($mapping in $directAnnotationMappings.GetEnumerator()) {
                $encodedSource = $mapping.Key.Replace('/', '~1')
                $encodedTarget = $mapping.Value.Replace('/', '~1')
                $translatedItem = $translatedItem.Replace($encodedSource, $encodedTarget)
            }

            if ($translatedItem -match 'nginx(?:\.ingress)?\.' -or $translatedItem -match '/spec/ingressClassName') {
                $blockers.Add("$Path targets '$originalName' with NGINX-specific or ingress-class changes.")
                $index = $end - 1
                continue
            }

            $haproxyName = "$originalName$nameSuffix"
            if ($raw -match "(?m)^\s+name:\s*$([regex]::Escape($haproxyName))\s*(?:#.*)?$") {
                $index = $end - 1
                continue
            }

            $translatedTarget = [regex]::Match(
                $translatedItem,
                '(?ms)^\s*(?:-\s*)?target:\s*(?:#.*)?\r?\n(?<body>.*)$'
            )
            $updatedTargetBody = [regex]::Replace(
                $translatedTarget.Groups['body'].Value,
                '(?m)^(\s+name:\s*)[^#\r\n]+?(\s*(?:#.*)?)$',
                "`${1}$haproxyName`${2}",
                1
            )
            $clone = $translatedItem.Substring(0, $translatedTarget.Groups['body'].Index) + $updatedTargetBody
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

function Invoke-Repository {
    param([Parameter(Mandatory)][string] $Path)

    $repo = (Resolve-Path -LiteralPath $Path).Path
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
            $clone = Convert-NginxAnnotations `
                -Document $clone `
                -NewLine $newLine `
                -Warnings $warnings `
                -Source "$($file.FullName): ingress '$($metadata.Name)'"
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

    Write-Host ''
    Write-Host "Repository: $repo"
    Write-Host "Mode: $(if ($Apply) { 'apply' } else { 'dry-run' })"
    foreach ($plan in $sourcePlans) {
        Write-Host "DUPLICATE $($plan.Count) ingress(es): $($plan.Path)"
    }
    foreach ($plan in $kustomizationPlans) {
        foreach ($change in $plan.Changes) {
            Write-Host "CLONE PATCH for '$($change.Name)': $($plan.Path)"
        }
    }
    foreach ($warning in $warnings) {
        Write-Warning $warning
    }
    foreach ($blocker in $blockers) {
        Write-Warning "BLOCKED: $blocker"
    }

    $applied = $false
    if ($Apply -and $blockers.Count -eq 0) {
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
        $applied = $true
    }
    elseif ($Apply -and $blockers.Count -gt 0) {
        Write-Warning "SKIPPED repository: no files changed because $($blockers.Count) unsafe transformation(s) require manual review."
    }

    Write-Host "Summary: $($sourcePlans.Count) manifest file(s), $($kustomizationPlans.Count) kustomization file(s), $($blockers.Count) blocker(s)."
    return [pscustomobject]@{
        Repository         = $repo
        ManifestFiles      = $sourcePlans.Count
        KustomizationFiles = $kustomizationPlans.Count
        Blockers           = $blockers.Count
        Applied            = $applied
    }
}

function Get-WorkspaceRepositories {
    param([Parameter(Mandatory)][string] $Path)

    $resolvedWorkspace = (Resolve-Path -LiteralPath $Path).Path
    $workspaceDirectory = Split-Path -Parent $resolvedWorkspace
    try {
        $workspace = [System.IO.File]::ReadAllText($resolvedWorkspace) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "Unable to parse VS Code workspace '$resolvedWorkspace': $($_.Exception.Message)"
    }

    if ($null -eq $workspace.folders -or @($workspace.folders).Count -eq 0) {
        throw "VS Code workspace '$resolvedWorkspace' contains no folders."
    }

    $repositories = [System.Collections.Generic.List[string]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($folder in $workspace.folders) {
        if ([string]::IsNullOrWhiteSpace($folder.path)) {
            throw "VS Code workspace '$resolvedWorkspace' contains a folder without a path."
        }

        $candidate = $folder.path
        if (-not [System.IO.Path]::IsPathRooted($candidate)) {
            $candidate = Join-Path -Path $workspaceDirectory -ChildPath $candidate
        }
        if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
            throw "Workspace folder does not exist: $candidate"
        }

        $resolvedRepository = (Resolve-Path -LiteralPath $candidate).Path
        if ($seen.Add($resolvedRepository)) {
            $repositories.Add($resolvedRepository)
        }
    }

    return $repositories
}

$repositories = @(
    if ($PSCmdlet.ParameterSetName -eq 'Workspace') {
        Get-WorkspaceRepositories -Path $WorkspacePath
    }
    else {
        (Resolve-Path -LiteralPath $RepoPath).Path
    }
)

Write-Output "Processing $($repositories.Count) repository folder(s)."
$results = @(
    foreach ($repository in $repositories) {
        Invoke-Repository -Path $repository
    }
)

$blockedRepositories = @($results | Where-Object Blockers -gt 0)
Write-Output ''
Write-Output "Overall summary: $($results.Count) repository folder(s), $($blockedRepositories.Count) blocked."
if ($Apply -and $blockedRepositories.Count -gt 0) {
    throw "$($blockedRepositories.Count) repository folder(s) were skipped because they require manual review."
}
