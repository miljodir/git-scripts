#requires -Version 7.0
<#
.SYNOPSIS
Creates a tenant-wide Nais service account that New-NaisTeams.ps1 can use, and issues an API token for it.
.EXAMPLE
.\Az\New-NaisServiceAccount.ps1
.EXAMPLE
.\Az\New-NaisServiceAccount.ps1 -Name team-provisioner -TokenExpiresInDays 30 -WhatIf

Nais service accounts live in the Nais API (not in Google Cloud), so gcloud
cannot create them. This script uses your personal Nais CLI login through
'nais api proxy', and you must be a Nais admin: only admins can create
service accounts that are not bound to a team and assign global roles.

The script is idempotent. It creates the service account -Name if no global
service account with that name exists, assigns any missing roles from
'Team creator' (create teams) and 'Team owner' (manage members of every
team), and always issues a new API token that expires after
-TokenExpiresInDays days. Existing tokens are left untouched; revoke old
ones in Nais Console.

The token secret is only returned once by Nais. It is never printed; it is
stored in $env:NAIS_API_TOKEN for the current PowerShell session so you can
run New-NaisTeams.ps1 -ConsoleHost console.<tenant>.cloud.nais.io right away.
Store it in a secret store (for example Azure Key Vault or
Microsoft.PowerShell.SecretManagement) if you need it later. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateNotNullOrEmpty()]
    [string] $Name = 'team-provisioner',
    [ValidateNotNullOrEmpty()]
    [string] $Description = 'Creates Nais teams and adds members from Entra ID groups (git-scripts/Az/New-NaisTeams.ps1).',
    [ValidateRange(1, 365)]
    [int] $TokenExpiresInDays = 90
)

$ErrorActionPreference = 'Stop'

$requiredRoles = @('Team creator', 'Team owner')

$nais = Get-Command nais -CommandType Application -ErrorAction SilentlyContinue
if (-not $nais) {
    throw 'Nais CLI (nais) is required.'
}

function Get-FreePort {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    try {
        $listener.Start()
        return $listener.LocalEndpoint.Port
    }
    finally {
        $listener.Stop()
    }
}

function Invoke-NaisApi {
    param(
        [string] $Query,
        [hashtable] $Variables = @{}
    )

    $body = @{ query = $Query; variables = $Variables } | ConvertTo-Json -Depth 10 -Compress
    $response = Invoke-RestMethod -Uri $script:naisApiUrl -Method Post -ContentType 'application/json' -Body $body -SkipHttpErrorCheck -StatusCodeVariable statusCode
    if ($statusCode -ge 400 -and -not $response.errors) {
        throw "Nais API returned HTTP $statusCode`: $response"
    }
    if ($response.errors) {
        throw "Nais API error: $(($response.errors | ForEach-Object { $_.message }) -join '; ')"
    }

    return $response.data
}

function Start-NaisApiProxy {
    $port = Get-FreePort
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $nais.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    foreach ($argument in @('api', 'proxy', '--listen', "localhost:$port")) {
        [void] $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    [void] $process.Start()
    $script:proxyStderr = $process.StandardError.ReadToEndAsync()
    $script:proxyStdout = $process.StandardOutput.ReadToEndAsync()
    $script:naisApiUrl = "http://localhost:$port/graphql"

    $deadline = [DateTime]::UtcNow.AddSeconds(30)
    while ($true) {
        if ($process.HasExited) {
            $errorOutput = $script:proxyStderr.GetAwaiter().GetResult()
            throw "Nais API proxy exited (exit $($process.ExitCode)). Are you logged in with 'nais login'? $errorOutput"
        }
        try {
            [void] (Invoke-NaisApi -Query 'query { me { ... on User { email } } }')
            return $process
        }
        catch [System.Net.Http.HttpRequestException] {
            if ([DateTime]::UtcNow -gt $deadline) {
                throw "Nais API proxy did not respond on $($script:naisApiUrl) within 30 seconds."
            }
            Start-Sleep -Milliseconds 250
        }
    }
}

function Get-GlobalServiceAccount {
    param([string] $Name)

    $after = $null
    do {
        $data = Invoke-NaisApi -Query 'query($after: Cursor) { serviceAccounts(first: 100, after: $after) { nodes { id name team { slug } roles(first: 100) { nodes { name } } } pageInfo { hasNextPage endCursor } } }' -Variables @{ after = $after }
        foreach ($node in $data.serviceAccounts.nodes) {
            if ($node.name -eq $Name -and $null -eq $node.team) {
                return $node
            }
        }
        $after = $data.serviceAccounts.pageInfo.endCursor
    } while ($data.serviceAccounts.pageInfo.hasNextPage)

    return $null
}

$proxy = Start-NaisApiProxy
try {
    $me = (Invoke-NaisApi -Query 'query { me { ... on User { email isAdmin } } }').me
    if (-not $me.isAdmin) {
        throw "'$($me.email)' is not a Nais admin. Only Nais admins can create global service accounts and assign the $($requiredRoles -join ' and ') roles."
    }

    $serviceAccount = Get-GlobalServiceAccount -Name $Name
    if ($serviceAccount) {
        Write-Host "Using existing global service account '$Name'."
        $existingRoles = @($serviceAccount.roles.nodes | ForEach-Object { $_.name })
    }
    elseif ($PSCmdlet.ShouldProcess($Name, 'Create global Nais service account')) {
        $data = Invoke-NaisApi -Query 'mutation($input: CreateServiceAccountInput!) { createServiceAccount(input: $input) { serviceAccount { id name } } }' -Variables @{
            input = @{ name = $Name; description = $Description }
        }
        $serviceAccount = $data.createServiceAccount.serviceAccount
        if ($serviceAccount.name -ne $Name -or -not $serviceAccount.id) {
            throw "Unexpected response when creating service account '$Name'."
        }
        $existingRoles = @()
        Write-Host "Created global service account '$Name'."
    }
    else {
        foreach ($role in $requiredRoles) {
            [void] $PSCmdlet.ShouldProcess($Name, "Assign role '$role'")
        }
        [void] $PSCmdlet.ShouldProcess($Name, "Create API token expiring in $TokenExpiresInDays day(s)")
        return
    }

    foreach ($role in $requiredRoles) {
        if ($role -in $existingRoles) {
            continue
        }
        if ($PSCmdlet.ShouldProcess($Name, "Assign role '$role'")) {
            [void] (Invoke-NaisApi -Query 'mutation($input: AssignRoleToServiceAccountInput!) { assignRoleToServiceAccount(input: $input) { serviceAccount { id } } }' -Variables @{
                input = @{ serviceAccountID = $serviceAccount.id; roleName = $role }
            })
            Write-Host "Assigned role '$role' to '$Name'."
        }
    }

    $expiresAt = [DateTime]::UtcNow.Date.AddDays($TokenExpiresInDays).ToString('yyyy-MM-dd')
    if ($PSCmdlet.ShouldProcess($Name, "Create API token expiring $expiresAt")) {
        $tokenName = "$Name-$([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
        $data = Invoke-NaisApi -Query 'mutation($input: CreateServiceAccountTokenInput!) { createServiceAccountToken(input: $input) { secret serviceAccountToken { name expiresAt } } }' -Variables @{
            input = @{
                serviceAccountID = $serviceAccount.id
                name = $tokenName
                description = "Created by $($me.email) with New-NaisServiceAccount.ps1"
                expiresAt = $expiresAt
            }
        }
        if ([string]::IsNullOrEmpty($data.createServiceAccountToken.secret)) {
            throw "Nais did not return a secret for token '$tokenName'."
        }
        $env:NAIS_API_TOKEN = $data.createServiceAccountToken.secret
        Write-Host "Created API token '$tokenName' (expires $expiresAt) and stored it in `$env:NAIS_API_TOKEN for this session."
        Write-Host 'The secret cannot be retrieved again; store it in a secret store now if you need it later.'
    }
}
finally {
    if (-not $proxy.HasExited) {
        $proxy.Kill($true)
    }
    $proxy.WaitForExit()
    $proxy.Dispose()
}
