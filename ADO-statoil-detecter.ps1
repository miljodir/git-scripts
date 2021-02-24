$ErrorActionPreference = "Continue"

# List all ADO orgs

$csv = Import-Csv -Path "C:\maps\orgs.csv" | sort-object Url

$collection = @()

echo $csv[0].Url

foreach ($org in $csv)
{
    echo "Checking org:" $org.'Organization Name'
    $users = az devops user list --org $org.Url | ConvertFrom-Json | select items

    foreach ($user in $users.items)
    {
        if ($user.user.principalName.Contains("statoil"))
        {
            $collection += [pscustomobject] @{
                OrgName = $org.'Organization Name'
                UserName = $user.user.principalName
            }
        }
    }
}
echo $collection
