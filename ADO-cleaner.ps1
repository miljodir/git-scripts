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
$collection = @()

# Find all ADO orgs without projects (no meaningful data what so ever)

foreach ($org in $csv)
{
    $hasGitHistory = $false
    $hasPipelines = $false
    $hasWorkItems = $false
    $hasAzArtifacts = $false

    Set-VSTeamAccount -Account $org."Organization Name" -PersonalAccessToken $token
    $localProjects = Get-VSTeamProject

    if (!$localProjects)
    {
        Write-Host "Org $($org.'Organization Name') does not contain a project and can be safely removed" -ForegroundColor Green
        $emptyOrgs += $org.Url + "_settings/organizationOverview"
    }
    else {
        Write-Host "Org $($org.'Organization Name') contains one or more projects and will be reviewed more closely:" -ForegroundColor Yellow
        $populatedOrgs += $org.'Organization Name'
        $globalProjects += ($org.Url + $localProjects.Name)
        $pipelines = @()

        # Check if there are pipelines
        foreach ($proj in $localProjects)
        {
            $pipelines += Get-VSTeamBuildDefinition -ProjectName $proj.Name
        }

        if (!$pipelines)
        {
            Write-Host "Org $($org.'Organization Name') does not contain a pipeline" -ForegroundColor Green
        }
        else {
            $hasPipelines = $true
            Write-Host "Org $($org.'Organization Name') contains one or more pipelines" -ForegroundColor Red
        }

        #Check if there are work items
        $item = Get-VSTeamWiql -Query "Select [System.Id], [System.Title] From WorkItems" -Expand
        if (!$item.WorkItems)
        {
            Write-Host "Org $($org.'Organization Name') does not contain work items (populated boards)" -ForegroundColor Green
        }
        else {
            $hasWorkItems = $true
            Write-Host "Org $($org.'Organization Name') has one or more work items (boards)" -ForegroundColor Red
        }

        # Check if there are repos with git commits (content)
        $repos = Get-VSTeamGitRepository
        foreach ($repo in $repos)
        {
            $commits = Get-VSTeamGitCommit -RepositoryID $repo.Id
            if ($commits){
                $hasGitHistory = $true
                Write-Host "Repo $($Repo.Name) in org $($org.'Organization Name') contains git history!" -ForegroundColor Red
                break
            }
            else {
                Write-Host "Repo $($Repo.Name) in org $($org.'Organization Name') does not contain git history" -ForegroundColor Green
            }
        }
        # Check if there are Azure Artifacts

        $packages = Get-VSTeamFeed | Get-VSTeamPackage
        if (!$packages)
        {
            Write-Host "Org $($org.'Organization Name') does not contain Az Artifacts (Packages)" -ForegroundColor Green
        }
        else {
            $hasAzArtifacts = $true
            Write-Host "Org $($org.'Organization Name') has one or more Az Artifacts (Packages)" -ForegroundColor Red
        }


        # Format to excel sheet
        $collection += [pscustomobject] @{
            OrgName = $org.'Organization Name'
            SettingsUrl = $org.Url + "_settings/organizationOverview"
            HasPipelines  = $hasPipelines
            HasWorkItems  = $hasWorkItems
            HasGitHistory = $hasGitHistory
            HasAzArtifacts = $hasAzArtifacts
    }

    }
}

$collection | export-excel