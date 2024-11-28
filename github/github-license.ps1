<#
.SYNOPSIS
    Finds the most recent push date for each user using Github Advanced Security in a CSV file.
#>


param (
    [string] [Parameter(Mandatory=$false)] $csvPath = "./ghas_active_committers_miljodir_2024-11-28T0121.csv"
)

$csv = import-csv -Path $csvPath


# Group by 'User login' and select the entry with the most recent 'Last pushed date'
$latestPerUser = $csv | Group-Object 'User login' | ForEach-Object {
    $_.Group | Sort-Object -Property @{Expression = {[datetime]::Parse($_.'Last pushed date')}} -Descending | Select -First 1
}

# Output the result
$latestPerUser | Select-Object 'User login', 'Organization / repository', 'Last pushed date',  'Last pushed email' | Sort-Object 'Last pushed date' |  Format-Table -AutoSize

Write-Host "$($latestPerUser.Count) users found in CSV file"