if ($env:ado_pat)
{
    $token = $env:ado_pat
}
else {
    Write-Host "You must set the 'ado_pat' env variable!" -ForegroundColor Red
    Exit
}

# List all ADO orgs

$csv = Import-Csv -Path "C:\maps\orgs2.csv" | sort-object Url

$emptyOrgs = @()
$populatedOrgs = @()
$globalProjects = @()

# Find all ADO orgs without projects (no meaningful data what so ever)

foreach ($org in $csv)
{
    Set-VSTeamAccount -Account $org."Organization Name" -PersonalAccessToken $token
    $localProjects = Get-VSTeamProject

    if (!$localProjects)
    {
        echo "Org $($org.'Organization Name') does not contain a project and should be removed"
        $emptyOrgs += $org.Url + "_settings/organizationOverview"
    }
    else {
        echo "Org $($org.'Organization Name') contains one or more projects and must be further reviewed before removal."
        $populatedOrgs += $org.'Organization Name'
        $globalProjects += ($org.Url + $localProjects)
    }
}

echo "Here are the following orgs with projects:"
$globalProjects

echo ""

echo "The following orgs are empty:"
echo $emptyOrgs