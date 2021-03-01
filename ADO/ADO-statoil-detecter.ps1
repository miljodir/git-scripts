$ErrorActionPreference = "Continue"

# List all ADO orgs

$csv = Import-Csv -Path "C:\maps\orgsv2.csv" | sort-object Url

$collection = @()
$365DaysAgo = [DateTime]::UtcNow.AddDays(-365)

foreach ($org in $csv)
{
    echo "Checking org:" $org.Url
    $users = az devops user list --top 1365 --org $org.Url | ConvertFrom-Json | select items

    foreach ($user in $users.items)
    {
        if ($user.user.principalName.EndsWith("@statoil.com") -And $user.lastAccessedDate -lt $365DaysAgo) # Year 2018 is less than 2019 (365 days ago), therefore the logic is correct
        {
            echo "Removing user $($user.user.principalName) from org: $($org.Url).."
            az devops user remove --user $($user.user.principalName) --org $($org.Url) -y
            if ($?)
            {
                echo "Successfully removed $($user.user.principalName) from org: $($org.Url).."
                $collection += [pscustomobject] @{
                    OrgName = $org.Url
                    UserName = $user.user.principalName
                }
            }
        }
    }
}
$collection | export-excel
