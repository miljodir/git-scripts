#requires -Version 7.0
<#
.SYNOPSIS
Copies Azure Key Vault secrets from subscriptions to Nais secrets.
.EXAMPLE
.\Az\Import-KeyVaultSecrets.ps1 -Subscriptions d-tstsp1,d-tstsp2
.EXAMPLE
.\Az\Import-KeyVaultSecrets.ps1 -Subscriptions (Get-AzSubscription | Where-Object Name -Match '^d-' | Select-Object -ExpandProperty Name) -Names SampleApiKey
.EXAMPLE
.\Az\Import-KeyVaultSecrets.ps1 -Subscriptions d-tstsp2 -MergeVaults
.EXAMPLE
.\Az\Import-KeyVaultSecrets.ps1 -Subscriptions d-tstsp1 -IncludeVaultName

Subscription names must be d-<team>, t-<team>, or p-<team>. d and t map to
the Nais dev environment; p maps to prod. Every Key Vault in each subscription
is discovered with Azure CLI; the CLI calls specify the subscription explicitly
and do not change the active Azure context. By default each vault gets its own
Nais secret. d-tstsp1abc123-kv becomes tstsp1-secrets; d-tstsp2-service1
and d-ts-service2 become tstsp2-service1-secrets and
tstsp2-service2-secrets. A trailing -kv is ignored, and a vault with a single
name segment that does not match the subscription (d-othername-kv) maps to
<team>-secrets. For uncommon prefixes like d-ts-, the part
after the second hyphen is treated as the service name, with a warning.
-IncludeVaultName uses the full vault name instead,
and -MergeVaults puts all vaults in a subscription into <team>-secrets.
Duplicate keys in a merged target, or vaults mapping to the same target,
cause an error before any values are copied.

By default, copies the latest value of every Azure Key Vault secret. -Names
limits the copy to specific names. Empty vaults are skipped. Existing Nais
keys are updated after a warning. Azure names containing '--' are written
to Nais with '__' in place of each separator (for example,
Service--Connection--String becomes Service__Connection__String); names
without '--' are unchanged. -Names uses the original Azure names. Existing
keys are not removed. Requires authenticated Azure CLI and
Nais CLI; Get-AzSubscription is optional for selecting subscription names.
Secret values are never passed as command-line arguments or written to files.
#>
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Subscriptions,
    [ValidateNotNullOrEmpty()]
    [string[]] $Names,
    [switch] $All,
    [switch] $IncludeVaultName,
    [switch] $MergeVaults
)

$ErrorActionPreference = 'Stop'

if ($All -and $PSBoundParameters.ContainsKey('Names')) {
    throw 'Use either -Names or -All, not both.'
}
if ($Names | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw 'Secret names cannot be empty or whitespace.'
}
if ($Subscriptions | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw 'Subscription names cannot be empty or whitespace.'
}
if ($IncludeVaultName -and $MergeVaults) {
    throw 'Use either -IncludeVaultName or -MergeVaults, not both.'
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required.'
}

$nais = Get-Command nais -CommandType Application -ErrorAction SilentlyContinue
if (-not $nais) {
    throw 'Nais CLI (nais) is required.'
}

function Invoke-AzureCli {
    param([string[]] $Arguments)

    $result = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE): $($result -join "`n")"
    }

    return ($result -join "`n")
}

function Invoke-NaisCli {
    param([string[]] $Arguments)

    $result = & $nais.Source @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Nais CLI failed (exit $LASTEXITCODE): $($result -join "`n")"
    }

    return ($result -join "`n")
}

function Set-NaisValue {
    param(
        [string] $Target,
        [string] $Team,
        [string] $Environment,
        [string] $Key,
        [AllowEmptyString()][string] $Value
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $nais.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('secret', 'set', $Target, '--team', $Team, '--environment', $Environment, '--key', $Key, '--value-from-stdin')) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        [void] $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Value)
        $process.StandardInput.Close()
        $process.WaitForExit()
        $output = $stdout.GetAwaiter().GetResult()
        $errorOutput = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) {
            throw "Nais CLI failed setting key '$Key' (exit $($process.ExitCode)): $errorOutput"
        }

        Write-Host $output.TrimEnd()
    }
    finally {
        $process.Dispose()
    }
}

function Get-TargetName {
    param(
        [string] $Subscription,
        [string] $Vault,
        [string] $Team,
        [switch] $IncludeVaultName,
        [switch] $MergeVaults
    )

    if ($MergeVaults) {
        return "$Team-secrets"
    }
    if ($IncludeVaultName) {
        return "$Vault-secrets"
    }

    $prefix = $Subscription.Substring(0, 1)
    $base = $Vault -replace '-kv$', ''
    if ($base -match "^$prefix-$Team[a-z0-9]*$") {
        return "$Team-secrets"
    }

    if ($base -match "^$prefix-$Team-(.+)$") {
        $service = $Matches[1]
    }
    elseif ($base -match "^$prefix-[a-z0-9]+$") {
        Write-Warning "Vault '$Vault' does not start with '$prefix-$Team'; using '$Team-secrets'."
        return "$Team-secrets"
    }
    elseif ($base -match "^$prefix-[a-z0-9]+-(.+)$") {
        $service = $Matches[1]
        Write-Warning "Vault '$Vault' does not start with '$prefix-$Team-'; using '$service' as the service name for team '$Team'."
    }
    else {
        throw "Cannot derive a Nais secret name for vault '$Vault' in '$Subscription'. Use -IncludeVaultName or -MergeVaults."
    }
    return "$Team-$service-secrets"
}

$plans = [System.Collections.Generic.List[object]]::new()
$targets = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$foundNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($subscription in $Subscriptions) {
    if ($subscription -cnotmatch '^([dtp])-([a-z0-9]+(?:-[a-z0-9]+)*)$') {
        throw "Subscription '$subscription' must be named d-<team>, t-<team>, or p-<team>."
    }
    $prefix = $Matches[1]
    $team = $Matches[2]
    $environment = if ($prefix -eq 'p') { 'prod' } else { 'dev' }
    Write-Host "Discovering Key Vaults in subscription '$subscription'."
    $vaultsJson = Invoke-AzureCli -Arguments @('keyvault', 'list', '--subscription', $subscription, '--query', '[].name', '--output', 'json')
    $vaults = @(ConvertFrom-Json -InputObject $vaultsJson)
    if ($vaults.Count -eq 0) {
        Write-Warning "No Key Vaults found in subscription '$subscription'."
        continue
    }

    $keyOwners = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($vault in $vaults) {
        $target = Get-TargetName -Subscription $subscription -Vault $vault -Team $team -IncludeVaultName:$IncludeVaultName -MergeVaults:$MergeVaults
        $namesJson = Invoke-AzureCli -Arguments @('keyvault', 'secret', 'list', '--vault-name', $vault, '--subscription', $subscription, '--query', '[].name', '--output', 'json')
        $vaultNames = @(ConvertFrom-Json -InputObject $namesJson)
        if ($PSBoundParameters.ContainsKey('Names')) {
            $vaultNames = @($vaultNames | Where-Object { $_ -in $Names })
            foreach ($name in $vaultNames) {
                [void] $foundNames.Add($name)
            }
        }
        if ($vaultNames.Count -eq 0) {
            Write-Warning "No matching secrets found in Azure Key Vault '$vault' (subscription '$subscription'); skipping."
            continue
        }
        $targetId = "$environment/$team/$target"
        if (-not $MergeVaults -and -not $targets.Add($targetId)) {
            throw "More than one vault maps to Nais secret '$targetId'. Use -IncludeVaultName or -MergeVaults."
        }
        foreach ($name in $vaultNames) {
            $naisKey = $name.Replace('--', '__')
            $destination = "$targetId/$naisKey"
            if ($keyOwners.ContainsKey($destination)) {
                throw "Azure key '$name' in '$vault' maps to Nais key '$naisKey' in '$target', already mapped from '$($keyOwners[$destination])'."
            }
            $keyOwners.Add($destination, "$vault/$name")
        }

        $plans.Add([pscustomobject]@{
            Subscription = $subscription
            Vault = $vault
            Team = $team
            Environment = $environment
            Target = $target
            Names = $vaultNames
        })
    }
    if ($MergeVaults -and $keyOwners.Count -gt 0 -and -not $targets.Add("$environment/$team/$team-secrets")) {
        throw "More than one subscription maps to Nais secret '$environment/$team/$team-secrets'."
    }
}
if ($PSBoundParameters.ContainsKey('Names')) {
    foreach ($name in $Names) {
        if (-not $foundNames.Contains($name)) {
            throw "Requested secret '$name' was not found in any discovered Key Vault."
        }
    }
}

foreach ($group in ($plans | Group-Object Environment, Team, Target)) {
    $first = $group.Group[0]
    $team = $first.Team
    $environment = $first.Environment
    $target = $first.Target
    $secretsJson = Invoke-NaisCli -Arguments @('secret', 'list', '--team', $team, '--environment', $environment, '--output', 'json', '--no-colors')
    if ($secretsJson.TrimStart().StartsWith('[')) {
        $existingSecrets = @(ConvertFrom-Json -InputObject $secretsJson)
    }
    elseif ($secretsJson -match '\bNo secrets found\b') {
        $existingSecrets = @()
    }
    else {
        throw "Unexpected response from Nais secret list: $secretsJson"
    }

    if ($target -notin @($existingSecrets | ForEach-Object { $_.Name })) {
        [void] (Invoke-NaisCli -Arguments @('secret', 'create', $target, '--team', $team, '--environment', $environment))
        Write-Host "Created Nais secret '$target' in '$environment' for team '$team'."
    }

    $detailsJson = Invoke-NaisCli -Arguments @('secret', 'get', $target, '--team', $team, '--environment', $environment, '--output', 'json', '--no-colors')
    $details = ConvertFrom-Json -InputObject $detailsJson
    if ($details.name -ne $target -or $null -eq $details.data) {
        throw "Unexpected details from Nais secret '$target'."
    }
    $existingKeys = @($details.data | ForEach-Object { $_.key })

    $copied = 0
    foreach ($plan in $group.Group) {
        foreach ($name in $plan.Names) {
            $secretJson = Invoke-AzureCli -Arguments @('keyvault', 'secret', 'show', '--vault-name', $plan.Vault, '--subscription', $plan.Subscription, '--name', $name, '--output', 'json')
            $secret = ConvertFrom-Json -InputObject $secretJson
            if ($null -eq $secret.value) {
                throw "Azure Key Vault returned no value for '$name' in '$($plan.Vault)'."
            }

            $naisKey = $name.Replace('--', '__')
            if ($naisKey -in $existingKeys) {
                Write-Warning "Key '$naisKey' already exists in '$target'; updating its value."
            }

            Set-NaisValue -Target $target -Team $team -Environment $environment -Key $naisKey -Value $secret.value
            $copied++
        }
    }
    Write-Host "Copied $copied key(s) from $($group.Count) vault(s) to '$target' (team '$team', environment '$environment')."
}
