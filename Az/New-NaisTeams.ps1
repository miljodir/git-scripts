#requires -Version 7.0
<#
.SYNOPSIS
Creates Nais teams from Azure subscription names and adds members from Entra ID groups.
.EXAMPLE
.\Az\New-NaisTeams.ps1 -Subscriptions d-tstsp1
.EXAMPLE
.\Az\New-NaisTeams.ps1 -Subscriptions d-tstsp1,d-tstsp2 -WhatIf
.EXAMPLE
.\Az\New-NaisTeams.ps1 -Subscriptions (Get-AzSubscription | Where-Object Name -Match '^d-' | Select-Object -ExpandProperty Name)
.EXAMPLE
$env:NAIS_API_TOKEN = '<token from New-NaisServiceAccount.ps1>'
.\Az\New-NaisTeams.ps1 -Subscriptions d-tstsp1 -ConsoleHost console.<tenant>.cloud.nais.io

Subscription names must be d-<team>, t-<team>, or p-<team>. Each subscription
maps to the Nais team <team>; a Nais team spans every environment, so d-xxx
and p-xxx both target team xxx. Team names must be 3-30 characters and cannot
start with the reserved prefixes 'team', 'nais' or 'pg-'. Missing teams are
created with Slack channel #mon-<team> and purpose 'Team for the <team>
project'.

Members are read from the Entra ID group 'az rbac sub <subscription>
contributors' (direct members only) and added to the Nais team with the
Member role, using each user's userPrincipalName (the mail attribute is
ignored). Nested groups and service principals are skipped with a warning.
Existing Nais members are never removed or changed. Users that Nais cannot
add (for example users unknown to Nais) are reported, and the script fails
after processing every team. The Nais-managed Google group nais-team-<team>
follows the team membership automatically.

Authentication:
- Default: your personal Nais CLI login. The script starts 'nais api proxy'
  on a free localhost port. You become owner of teams you create, and you must
  be an owner of existing teams (or a Nais admin) to add members.
- -ConsoleHost: a Nais service account. The API token is read from the
  NAIS_API_TOKEN environment variable and sent directly to
  https://<ConsoleHost>/graphql. The service account needs the 'Team creator'
  and 'Team owner' roles (see New-NaisServiceAccount.ps1). Teams created this
  way have no human owner.
Requires authenticated Azure CLI, plus the Nais CLI when -ConsoleHost is not
used. Supports -WhatIf.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]] $Subscriptions,
    [ValidateNotNullOrEmpty()]
    [string] $ConsoleHost
)

$ErrorActionPreference = 'Stop'

if ($Subscriptions | Where-Object { [string]::IsNullOrWhiteSpace($_) }) {
    throw 'Subscription names cannot be empty or whitespace.'
}

$useServiceAccount = $PSBoundParameters.ContainsKey('ConsoleHost')
if ($useServiceAccount -and [string]::IsNullOrWhiteSpace($env:NAIS_API_TOKEN)) {
    throw 'Set the NAIS_API_TOKEN environment variable to a Nais service account token when using -ConsoleHost.'
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI (az) is required.'
}

if (-not $useServiceAccount) {
    $nais = Get-Command nais -CommandType Application -ErrorAction SilentlyContinue
    if (-not $nais) {
        throw 'Nais CLI (nais) is required unless -ConsoleHost is used.'
    }
}

function Invoke-AzureCli {
    param([string[]] $Arguments)

    $result = & az @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed (exit $LASTEXITCODE): $($result -join "`n")"
    }

    return ($result -join "`n")
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
    $request = @{
        Uri = $script:naisApiUrl
        Method = 'Post'
        ContentType = 'application/json'
        Body = $body
        SkipHttpErrorCheck = $true
        StatusCodeVariable = 'statusCode'
    }
    if ($script:naisApiToken) {
        $request.Authentication = 'Bearer'
        $request.Token = $script:naisApiToken
        $request.AllowUnencryptedAuthentication = $script:naisApiUrl.StartsWith('http://')
    }
    $response = Invoke-RestMethod @request
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

function Get-NaisTeamSlugs {
    $slugs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $after = $null
    do {
        $data = Invoke-NaisApi -Query 'query($after: Cursor) { teams(first: 100, after: $after) { nodes { slug } pageInfo { hasNextPage endCursor } } }' -Variables @{ after = $after }
        foreach ($node in $data.teams.nodes) {
            [void] $slugs.Add($node.slug)
        }
        $after = $data.teams.pageInfo.endCursor
    } while ($data.teams.pageInfo.hasNextPage)

    return , $slugs
}

function Get-NaisTeamMemberEmails {
    param([string] $Team)

    $emails = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $after = $null
    do {
        $data = Invoke-NaisApi -Query 'query($slug: Slug!, $after: Cursor) { team(slug: $slug) { members(first: 100, after: $after) { nodes { user { email } } pageInfo { hasNextPage endCursor } } } }' -Variables @{ slug = $Team; after = $after }
        foreach ($node in $data.team.members.nodes) {
            [void] $emails.Add($node.user.email)
        }
        $after = $data.team.members.pageInfo.endCursor
    } while ($data.team.members.pageInfo.hasNextPage)

    return , $emails
}

$teams = [ordered]@{}
foreach ($subscription in $Subscriptions) {
    if ($subscription -cnotmatch '^[dtp]-([a-z][a-z0-9]*(?:-[a-z0-9]+)*)$') {
        throw "Subscription '$subscription' must be named d-<team>, t-<team>, or p-<team>."
    }
    $team = $Matches[1]
    if ($team.Length -lt 3 -or $team.Length -gt 30) {
        throw "Team name '$team' from subscription '$subscription' must be 3-30 characters long."
    }
    if ($team -match '^(team|nais|pg-)') {
        throw "Team name '$team' from subscription '$subscription' starts with a prefix reserved by Nais ('team', 'nais' or 'pg-')."
    }
    if (-not $teams.Contains($team)) {
        $teams[$team] = [pscustomobject]@{
            Team = $team
            Groups = [System.Collections.Generic.List[string]]::new()
            Members = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        }
    }

    $group = "az rbac sub $subscription contributors"
    if ($teams[$team].Groups.Contains($group)) {
        continue
    }
    $teams[$team].Groups.Add($group)

    Write-Host "Reading members of Entra ID group '$group'."
    $membersJson = Invoke-AzureCli -Arguments @('ad', 'group', 'member', 'list', '--group', $group, '--output', 'json')
    foreach ($member in @(ConvertFrom-Json -InputObject $membersJson)) {
        if ($member.'@odata.type' -ne '#microsoft.graph.user') {
            Write-Warning "Skipping non-user member '$($member.displayName)' ($($member.'@odata.type')) of '$group'."
            continue
        }
        $email = $member.userPrincipalName
        if ([string]::IsNullOrWhiteSpace($email)) {
            Write-Warning "Skipping user '$($member.displayName)' in '$group' without userPrincipalName."
            continue
        }
        [void] $teams[$team].Members.Add($email.ToLowerInvariant())
    }
}

$failures = [System.Collections.Generic.List[string]]::new()
$proxy = $null
if ($useServiceAccount) {
    $baseUrl = if ($ConsoleHost -match '^https?://') { $ConsoleHost.TrimEnd('/') } else { "https://$($ConsoleHost.TrimEnd('/'))" }
    $script:naisApiUrl = "$baseUrl/graphql"
    $script:naisApiToken = ConvertTo-SecureString -String $env:NAIS_API_TOKEN -AsPlainText -Force
}
else {
    $proxy = Start-NaisApiProxy
}
try {
    $existingTeams = Get-NaisTeamSlugs

    foreach ($plan in $teams.Values) {
        $team = $plan.Team
        $created = $false
        if (-not $existingTeams.Contains($team)) {
            $slackChannel = "#mon-$team"
            $purpose = "Team for the $team project"
            if (-not $PSCmdlet.ShouldProcess($team, "Create Nais team (Slack channel '$slackChannel', purpose '$purpose')")) {
                foreach ($email in $plan.Members) {
                    [void] $PSCmdlet.ShouldProcess($team, "Add '$email' as member")
                }
                continue
            }
            $data = Invoke-NaisApi -Query 'mutation($input: CreateTeamInput!) { createTeam(input: $input) { team { slug } } }' -Variables @{
                input = @{ slug = $team; purpose = $purpose; slackChannel = $slackChannel }
            }
            if ($data.createTeam.team.slug -ne $team) {
                throw "Unexpected response when creating Nais team '$team'."
            }
            $created = $true
            Write-Host "Created Nais team '$team'."
        }

        $existingMembers = Get-NaisTeamMemberEmails -Team $team

        $added = 0
        foreach ($email in $plan.Members) {
            if ($existingMembers.Contains($email)) {
                continue
            }
            if (-not $PSCmdlet.ShouldProcess($team, "Add '$email' as member")) {
                continue
            }
            try {
                [void] (Invoke-NaisApi -Query 'mutation($input: AddTeamMemberInput!) { addTeamMember(input: $input) { member { role } } }' -Variables @{
                    input = @{ teamSlug = $team; userEmail = $email; role = 'MEMBER' }
                })
                $added++
            }
            catch {
                Write-Warning "Could not add '$email' to team '$team': $($_.Exception.Message)"
                $failures.Add("$team/$email")
            }
        }

        $state = if ($created) { 'created' } else { 'existing' }
        Write-Host "Team '$team' ($state): added $added of $($plan.Members.Count) group member(s) from $($plan.Groups -join ', ')."
    }
}
finally {
    if ($proxy) {
        if (-not $proxy.HasExited) {
            $proxy.Kill($true)
        }
        $proxy.WaitForExit()
        $proxy.Dispose()
    }
}

if ($failures.Count -gt 0) {
    throw "Failed to add $($failures.Count) member(s): $($failures -join ', ')"
}
