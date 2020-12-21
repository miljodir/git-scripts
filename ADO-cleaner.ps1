if ($env:ado_pat)
{
    $token = $env:ado_pat
}
else {
    Write-Host "You must set the 'ado_pat' env variable!" -ForegroundColor Red
    Exit
}

# List all ADO orgs

$csv = Import-Csv -Path "C:\maps\orgs2.csv"
$orgs = ($csv | select "Organization Name")."Organization Name"

$emptyOrgs = @()
$populatedOrgs = @()
$globalProjects = @()

# Find all ADO orgs without projects (no meaningful data what so ever)

foreach ($org in $orgs)
{
    Set-VSTeamAccount -Account $org -PersonalAccessToken $token
    $localProjects = Get-VSTeamProject

    if (!$localProjects)
    {
        echo "Org $($org) does not contain a project and should be removed"
        $emptyOrgs += $org
    }
    else {
        echo "Org $($org) contains one or more projects and must be further reviewed before removal."
        $populatedOrgs += $org
        $globalProjects += $org + "/" + $localProjects 
    }
}

echo "Here are the following orgs with projects:" -
$globalProjects

echo ""

echo "The following orgs are empty:"
echo $emptyOrgs