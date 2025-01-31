<#
.SYNOPSIS
    Finds the most recent push date for each user using Github Advanced Security in a CSV file.
#>


param (
    [string] [Parameter(Mandatory=$false)] $csvPath = "C:\Users\audun\Downloads\ghas_active_committers_miljodir_2025-01-31T0015.csv",
    [string] [Parameter(Mandatory=$false)] $csvPath2 = "C:\Users\audun\Downloads\export-miljodir-1738311321.csv",
    [string] [Parameter(Mandatory=$false)] $copilotCsvPath = "C:\Users\audun\Downloads\miljodir-seat-usage-1738311386.csv",
    [string] [Parameter(Mandatory=$false)] $workspaceId = "xxxx"

)

$csv = import-csv -Path $csvPath

$usersCsv = import-csv -Path $csvPath2

$copilotCsv = import-csv -Path $copilotCsvPath

# Group by 'User login' and select the entry with the most recent 'Last pushed date'
$latestPerUser = $csv | Group-Object 'User login' | ForEach-Object {
    $_.Group | Sort-Object -Property @{Expression = {[datetime]::Parse($_.'Last pushed date')}} -Descending | Select -First 1
}

# Get the list of 'User Login' values from $latestPerUser
$userLogins = $latestPerUser.'User Login'

# Filter $csv2 where 'GitHub com login' is not in $userLogins
$nonPushingMembers = $usersCsv | Where-Object { -not ($userLogins -contains $_.'GitHub com login') }


Write-Host "We are paying for the following users Copilot licenses, but they have seemingly not pushed code to the Github org in the last 3 months" -ForegroundColor Red
Write-Host "Please review and consider removing their license unless they are pushing code to other places which benefits the organization." -ForegroundColor Yellow
$copilotUsedByOtherOrgsOnly = $copilotCsv | Where-Object { -not ($userLogins -contains $_.Login) } | Sort-Object 'Last Usage Date' | Select-Object 'Login', 'Last Usage Date', 'Last Editor Used' | Format-Table -AutoSize
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
$allGithubUsers = $usersCsv | select -ExpandProperty "GitHub com saml name"
$githubLoginsList = (Invoke-AzOperationalInsightsQuery -WorkspaceId $workspaceId -Query $githubLoginQuery).Results | Select-Object -ExpandProperty UserPrincipalName

$missingNames = $allGithubUsers | Where-Object { -not ($githubLoginsList -contains $_) }

# Output the missing names
Write-Host "The following names have not signed in to the Github org for at least the past 5 months" -ForegroundColor Red
Write-Host "Note that some users may have signed in to other orgs under the enterprise, and are still requiring a license." -ForegroundColor Yellow
$missingNames | ForEach-Object { Write-Host $_ }

# Output the missing entries
Write-Host "Found $($nonPushingMembers.Count) members which have not pushed code in the last 3 months."
$nonPushingMembers | select "GitHub com login", "GitHub com saml name", "Github com name"
# Output the result
Write-Host "$($latestPerUser.Count) users found commiting code in the last 3 months."
$latestPerUser | Select-Object 'User login', 'Organization / repository', 'Last pushed date',  'Last pushed email' | Sort-Object 'Last pushed date' |  Format-Table -AutoSize