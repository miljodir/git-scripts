<#
.SYNOPSIS
    Finds the most recent push date for each user using Github Advanced Security in a CSV file.
#>


param (
    [string] [Parameter(Mandatory=$false)] $csvPath = "./.csv",
    [string] [Parameter(Mandatory=$false)] $csvPath2 = "./export-miljodir.csv"
)

$csv = import-csv -Path $csvPath

$usersCsv = import-csv -Path $csvPath2

# Group by 'User login' and select the entry with the most recent 'Last pushed date'
$latestPerUser = $csv | Group-Object 'User login' | ForEach-Object {
    $_.Group | Sort-Object -Property @{Expression = {[datetime]::Parse($_.'Last pushed date')}} -Descending | Select -First 1
}

# Get the list of 'User Login' values from $latestPerUser
$userLogins = $latestPerUser.'User Login'

# Filter $csv2 where 'GitHub com login' is not in $userLogins
$missingEntries = $usersCsv | Where-Object { -not ($userLogins -contains $_.'GitHub com login') }

# Output the missing entries
$missingEntries | select "GitHub com login", "GitHub com saml name", "Github com name"

# Output the result
#$latestPerUser | Select-Object 'User login', 'Organization / repository', 'Last pushed date',  'Last pushed email' | Sort-Object 'Last pushed date' |  Format-Table -AutoSize

Write-Host "$($latestPerUser.Count) users found in CSV file"