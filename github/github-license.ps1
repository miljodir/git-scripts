<#
.SYNOPSIS
    This script analyzes GitHub license usage data for an organization.
    First step is to download the CSVs from the Enterprise level (GHAS and Github users). Copilot CSV is download at the org level
#>


param (
    [string] [Parameter(Mandatory=$false)] $csvPathActiveCommiters = "C:\Users\audun\Downloads\ghas_active_committers_miljodir_2025-09-30T0453.csv",
    [string] [Parameter(Mandatory=$false)] $csvPathOrgUsers = "C:\Users\audun\Downloads\export-miljodir-1759233183.csv",
    [string] [Parameter(Mandatory=$false)] $copilotCsvPath = "C:\Users\audun\Downloads\miljodir-seat-activity-1759240330.csv",
    [string] [Parameter(Mandatory=$false)] $workspaceId = "xxxx"

)

$csvActiveCommiters = import-csv -Path $csvPathActiveCommiters

$usersCsv = import-csv -Path $csvPathOrgUsers

$copilotCsv = import-csv -Path $copilotCsvPath

# Group by 'User login' and select the entry with the most recent 'Last pushed date'
$recentGithubPushers = $csvActiveCommiters | Group-Object 'User login' | ForEach-Object {
    $_.Group | Sort-Object -Property @{Expression = {[datetime]::Parse($_.'Last pushed date')}} -Descending | Select -First 1
}

# Get the list of 'User Login' values from $recentGithubPushers
$recentGithubPusherLoginNames = $recentGithubPushers.'User Login'

# Filter $csv2 where 'GitHub com login' is not in $recentGithubPusherLoginNames
$nonPushingMembers = $usersCsv | Where-Object { -not ($recentGithubPusherLoginNames -contains $_.'GitHub com login') }


Write-Host "We are paying for the following users Copilot licenses, but they have seemingly not pushed code to the Github org in the last 3 months" -ForegroundColor Red
Write-Host "Please review and consider removing their license unless they are pushing code to other places which benefits the organization." -ForegroundColor Yellow
$copilotUsedByOtherOrgsOnly = $copilotCsv | Where-Object { -not ($recentGithubPusherLoginNames -contains $_.'Login') } | Sort-Object 'Last Activity At' | Select-Object 'Login', 'Last Activity At', 'Last Surface Used' | Format-Table -AutoSize
# Output users which are using copilot but seemingly not pushing code to the org
$copilotUsedByOtherOrgsOnly

# Successful Github Logins
$githubLoginQuery = @"
SigninLogs
| where AppDisplayName == "GitHub Enterprise Cloud"
| where TimeGenerated >= ago(180d)
| where ResultType !in ("50074","500121","70044","50105","50126")
| summarize arg_max(TimeGenerated, *) by UserPrincipalName
| sort by TimeGenerated asc
| project UserPrincipalName
"@

# Execute the query
$allGithubUsers = $usersCsv | select "GitHub com saml name", "GitHub com login" 
$githubLoginsList = (Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $githubLoginQuery).Results | Select-Object -ExpandProperty UserPrincipalName

$missingNames = $allGithubUsers `
    | Where-Object { 
        -not ($githubLoginsList -contains $_.'GitHub com saml name') `
    } `
    | Select 'GitHub com saml name', 'GitHub com login' `
    | ForEach-Object { $_.'GitHub com saml name' + " (" + $_.'GitHub com login' + ")" }

# Output the missing names
Write-Host "The following names have not signed in to the Github org for at least the past 5 months" -ForegroundColor Red
Write-Host "Note that some users may have signed in to other orgs under the enterprise, and are still requiring a license." -ForegroundColor Yellow
$missingNames | ForEach-Object { Write-Host $_ }

# Output the missing entries
Write-Host ""
Write-Host "Found $($nonPushingMembers.Count) members which have not pushed code in the last 3 months:" -ForegroundColor Yellow
$nonPushingMembers | select "GitHub com login", "GitHub com saml name", "Github com name"
# Output the result
#Write-Host "$($recentGithubPushers.Count) users found commiting code in the last 3 months."
#$recentGithubPushers | Select-Object 'User login', 'Organization / repository', 'Last pushed date',  'Last pushed email' | Sort-Object 'Last pushed date' |  Format-Table -AutoSize