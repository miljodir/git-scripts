<#
.SYNOPSIS
    Analyze GitHub license usage data for an organization.
    Uses the GitHub API via the authenticated gh CLI for GHAS, Copilot, and org identity data.
    The Azure Log Analytics query is still used for sign-in activity.
#>

param (
    [string] [Parameter(Mandatory=$false)] $org = "miljodir",
    [string] [Parameter(Mandatory=$false)] $advancedSecurityProduct,
    [string] [Parameter(Mandatory=$false)] $workspaceId = "xxx",
    [int] [Parameter(Mandatory=$false)] $inactiveDays = 90
)

function Get-GitHubApiPages {
    param (
        [Parameter(Mandatory=$true)]
        [string] $Endpoint
    )

    gh api --method GET "$Endpoint" --paginate --slurp | ConvertFrom-Json
}

function Get-GitHubApiItems {
    param (
        [Parameter(Mandatory=$true)]
        [string] $Endpoint,
        [string[]] $CollectionProperties = @()
    )

    $pages = @(Get-GitHubApiPages -Endpoint $Endpoint)

    $items = foreach ($page in $pages) {
        if ($null -eq $page) {
            continue
        }

        $matchedCollection = $false
        $propertyNames = @($page.PSObject.Properties.Name)

        foreach ($collectionProperty in $CollectionProperties) {
            if ($propertyNames -contains $collectionProperty) {
                $matchedCollection = $true
                foreach ($item in $page.$collectionProperty) {
                    $item
                }
                break
            }
        }

        if (-not $matchedCollection) {
            foreach ($item in $page) {
                $item
            }
        }
    }

    @($items)
}

function Get-OrganizationExternalIdentities {
    param (
        [Parameter(Mandatory=$true)]
        [string] $Org
    )

    $externalIdentities = @()
    $cursor = $null

    do {
        $afterClause = if ([string]::IsNullOrWhiteSpace($cursor)) { "null" } else { '"' + $cursor + '"' }
        $query = @"
query {
  organization(login: "$Org") {
    samlIdentityProvider {
      externalIdentities(first: 100, after: $afterClause) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          samlIdentity {
            nameId
            username
          }
          scimIdentity {
            username
          }
          user {
            login
          }
        }
      }
    }
  }
}
"@

        $response = gh api graphql -f query=$query | ConvertFrom-Json
        $samlIdentityProvider = $response.data.organization.samlIdentityProvider

        if ($null -eq $samlIdentityProvider) {
            Write-Warning "No SAML identity provider data available for organization '$Org'."
            return @()
        }

        $connection = $samlIdentityProvider.externalIdentities
        $externalIdentities += @($connection.nodes)
        $cursor = $connection.pageInfo.endCursor
    } while ($connection.pageInfo.hasNextPage)

    @($externalIdentities)
}

function Get-CopilotSeatLogin {
    param (
        [Parameter(Mandatory=$true)]
        $Seat
    )

    if ($Seat.PSObject.Properties.Name -contains 'github_user' -and $null -ne $Seat.github_user) {
        return $Seat.github_user.login
    }

    if ($Seat.PSObject.Properties.Name -contains 'assignee' -and $null -ne $Seat.assignee) {
        return $Seat.assignee.login
    }

    if ($Seat.PSObject.Properties.Name -contains 'login') {
        return $Seat.login
    }

    return $null
}

function Get-CopilotLastSurface {
    param (
        [Parameter(Mandatory=$true)]
        $Seat
    )

    if ($Seat.PSObject.Properties.Name -contains 'last_activity_editor') {
        return $Seat.last_activity_editor
    }

    if ($Seat.PSObject.Properties.Name -contains 'last_surface_used') {
        return $Seat.last_surface_used
    }

    return $null
}

$advancedSecurityQueryParameters = @("per_page=100")
if (-not [string]::IsNullOrWhiteSpace($advancedSecurityProduct)) {
    $advancedSecurityQueryParameters += "advanced_security_product=$advancedSecurityProduct"
}

$advancedSecurityRepositories = Get-GitHubApiItems `
    -Endpoint "/orgs/$org/settings/billing/advanced-security?$($advancedSecurityQueryParameters -join '&')" `
    -CollectionProperties @("repositories")

$recentActivityCutoff = (Get-Date).AddDays(-$inactiveDays)
$recentGithubPushers = $advancedSecurityRepositories `
    | ForEach-Object { $_.advanced_security_committers_breakdown } `
    | Group-Object user_login `
    | ForEach-Object {
        $_.Group | Sort-Object -Property @{Expression = {[datetime]::Parse($_.last_pushed_date)}} -Descending | Select-Object -First 1
    } `
    | Where-Object { [datetime]::Parse($_.last_pushed_date) -ge $recentActivityCutoff }

$recentGithubPusherLoginNames = $recentGithubPushers.user_login

$copilotSeats = Get-GitHubApiItems `
    -Endpoint "/orgs/$org/copilot/billing/seats?per_page=100" `
    -CollectionProperties @("seats", "assigned_seats")

$copilotUsedByOtherOrgsOnly = $copilotSeats `
    | ForEach-Object {
        [PSCustomObject]@{
            Login              = Get-CopilotSeatLogin -Seat $_
            'Last Activity At' = $_.last_activity_at
            'Last Surface Used' = Get-CopilotLastSurface -Seat $_
        }
    } `
    | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_.Login) -and -not ($recentGithubPusherLoginNames -contains $_.Login)
    } `
    | Sort-Object 'Last Activity At'

Write-Host "We are paying for the following users Copilot licenses, but they have seemingly not pushed code to the Github org in the last 3 months" -ForegroundColor Red
Write-Host "Please review and consider removing their license unless they are pushing code to other places which benefits the organization." -ForegroundColor Yellow
$copilotUsedByOtherOrgsOnlyTable = $copilotUsedByOtherOrgsOnly | Select-Object 'Login', 'Last Activity At', 'Last Surface Used' | Format-Table -AutoSize | Out-String
Write-Host $copilotUsedByOtherOrgsOnlyTable.TrimEnd()
Write-Host ""

$orgMembers = Get-GitHubApiItems -Endpoint "/orgs/$org/members?per_page=100"
$externalIdentities = Get-OrganizationExternalIdentities -Org $org

$externalIdentityByLogin = @{}
foreach ($externalIdentity in $externalIdentities) {
    if ($null -eq $externalIdentity.user -or [string]::IsNullOrWhiteSpace($externalIdentity.user.login)) {
        continue
    }

    $externalIdentityByLogin[$externalIdentity.user.login] = $externalIdentity
}

$allGithubUsers = $orgMembers | Select-Object -ExpandProperty login | Sort-Object -Unique | ForEach-Object {
    $login = $_
    $externalIdentity = $externalIdentityByLogin[$login]

    $samlName = $null
    if ($null -ne $externalIdentity) {
        if ($null -ne $externalIdentity.samlIdentity) {
            $samlName = $externalIdentity.samlIdentity.nameId
            if ([string]::IsNullOrWhiteSpace($samlName)) {
                $samlName = $externalIdentity.samlIdentity.username
            }
        }

        if ([string]::IsNullOrWhiteSpace($samlName) -and $null -ne $externalIdentity.scimIdentity) {
            $samlName = $externalIdentity.scimIdentity.username
        }
    }

    [PSCustomObject]@{
        'GitHub com saml name' = $samlName
        'GitHub com login'     = $login
    }
}

# Successful Github Logins
$githubLoginQuery = @"
SigninLogs
| where AppDisplayName startswith("GitHub Enterprise Cloud")
| where TimeGenerated >= ago($($inactiveDays)d)
| where ResultType !in ("50074","500121","70044","50105","50126")
| summarize arg_max(TimeGenerated, *) by UserPrincipalName
| sort by TimeGenerated asc
| project UserPrincipalName
"@

$githubLoginsList = (Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $githubLoginQuery).Results | Select-Object -ExpandProperty UserPrincipalName

$missingNames = $allGithubUsers `
    | Where-Object {
        -not ($githubLoginsList -contains $_.'GitHub com saml name')
    } `
    | Select-Object 'GitHub com saml name', 'GitHub com login' `
    | ForEach-Object { $_.'GitHub com saml name' + " (" + $_.'GitHub com login' + ")" }

Write-Host "`nThe following names have not signed in to the Github org for at least the past $inactiveDays days" -ForegroundColor Red
Write-Host "Note that some users may have signed in to other orgs under the enterprise, and are still requiring a license." -ForegroundColor Yellow
$missingNames | ForEach-Object { Write-Host $_ }
