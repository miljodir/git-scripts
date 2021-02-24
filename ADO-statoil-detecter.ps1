$ErrorActionPreference = "Continue"

# List all ADO orgs

$csv = Import-Csv -Path "C:\maps\orgs3.csv" | sort-object Url

$collection = @()
$400DaysAgo = [DateTime]::UtcNow.AddDays(-400)

foreach ($org in $csv)
{
    echo "Checking org:" $org.Url
    $users = az devops user list --org $org.Url | ConvertFrom-Json | select items

    foreach ($user in $users.items)
    {
        if ($user.user.principalName.EndsWith("@statoil.com") -And $user.lastAccessedDate -lt $400DaysAgo) # Year 2018 is less than 2019 (400 days ago), therefore the logic is correct
        {
            $collection += [pscustomobject] @{
                OrgName = $org.Url
                UserName = $user.user.principalName
            }
            echo "Removing user $($user.user.principalName) from org: $($org.Url).."
            #az devops user remove --user $($user.user.principalName) --org $($org.Url) -y
        }
    }
}
$collection | export-excel
