# Script for cleaning up bogus B2C users in the specified tenant and domains

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Users

$tenantId = 'mytenantid' # mytenantid
$sinceUtc = [datetime]'2026-07-24T13:10:00Z'
$domains  = @(
    'mydomain.hehe'
)

Connect-MgGraph `
    -TenantId $tenantId `
    -Scopes 'User.ReadWrite.All' `
    -NoWelcome

# Safety check: ensure Graph connected to B2C prod.
$context = Get-MgContext
if ($context.TenantId -ne $tenantId) {
    throw "Connected to the wrong tenant: $($context.TenantId)"
}

$filter = "createdDateTime ge $($sinceUtc.ToString('yyyy-MM-ddTHH:mm:ssZ'))"

$candidates = Get-MgUser `
    -All `
    -Filter $filter `
    -Property 'id,displayName,accountEnabled,createdDateTime,userPrincipalName,identities' |
    ForEach-Object {
        $user = $_

        $matchingIdentity = $user.Identities |
            Where-Object {
                $_.SignInType -eq 'emailAddress' -and
                $_.IssuerAssignedId -match '@([^@]+)$' -and
                $Matches[1].ToLowerInvariant() -in $domains
            } |
            Select-Object -First 1

        if ($matchingIdentity) {
            [pscustomobject]@{
                Id                = $user.Id
                Email             = $matchingIdentity.IssuerAssignedId
                DisplayName       = $user.DisplayName
                CreatedDateTime   = $user.CreatedDateTime
                AccountEnabled    = $user.AccountEnabled
                UserPrincipalName = $user.UserPrincipalName
            }
        }
    } |
    Sort-Object CreatedDateTime

$candidates |
    Format-Table CreatedDateTime, Email, AccountEnabled, Id -AutoSize

"`nFound $($candidates.Count) candidate accounts."

$candidates = @($candidates)

if ($candidates.Count -eq 0) {
    Write-Host 'No candidate accounts found.'
    return
}

$results = foreach ($candidate in $candidates) {
    try {
        Update-MgUser `
            -UserId $candidate.Id `
            -AccountEnabled:$false `
            -ErrorAction Stop

        [pscustomobject]@{
            Id       = $candidate.Id
            Email    = $candidate.Email
            Disabled = $true
            Error    = $null
        }
    }
    catch {
        [pscustomobject]@{
            Id       = $candidate.Id
            Email    = $candidate.Email
            Disabled = $false
            Error    = $_.Exception.Message
        }
    }
}

$results | Format-Table Email, Disabled, Error -AutoSize
$results | Export-Csv '.\b2c-disable-results.csv' `
    -NoTypeInformation `
    -Encoding utf8