<#
.SYNOPSIS
    Finds the most recent push date for each user using Github Advanced Security in a CSV file.
#>


param (
    [string] [Parameter(Mandatory=$false)] $csvPath = "C:\Users\audun\Downloads\ghas_active_committers_miljodir_2024-11-28T0312.csv",
    [string] [Parameter(Mandatory=$false)] $csvPath2 = "C:\Users\audun\Downloads\export-miljodir-1732787819.csv",
    [string] [Parameter(Mandatory=$false)] $copilotCsvPath = "C:\Users\audun\Downloads\miljodir-seat-usage-1733728035.csv"
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

# Output the missing entries
Write-Host "Found $($nonPushingMembers.Count) members which have not pushed code in the last 3 months."
$nonPushingMembers | select "GitHub com login", "GitHub com saml name", "Github com name"
# Output the result
#Write-Host "$($latestPerUser.Count) users found commiting code in the last 3 months."
#$latestPerUser | Select-Object 'User login', 'Organization / repository', 'Last pushed date',  'Last pushed email' | Sort-Object 'Last pushed date' |  Format-Table -AutoSize