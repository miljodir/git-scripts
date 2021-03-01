$ErrorActionPreference = "Continue"

if ($env:ado_pat)
{
    $token = $env:ado_pat
    $encodedPat  = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes(":"+$token))
}
else {
    Write-Host "You must set the 'ado_pat' env variable!" -ForegroundColor Red
    Exit
}

# List all ADO orgs

$csv = Import-Csv -Path "C:\maps\orgs.csv" | sort-object Url

$emptyOrgs = @()
$populatedOrgs = @()
$globalProjects = @()
$collection = @()

# Find all ADO orgs without projects (no meaningful data what so ever)

foreach ($org in $csv)
{
    $hasGitHistory = $false
    $hasPipelines = $false
    $hasTestPlans = $false
    $hasWorkItems = $false
    $hasAzArtifacts = $false
    $hasProject = $false

    try {

    Set-VSTeamAccount -Account $org."Organization Name" -PersonalAccessToken $token
    $localProjects = Get-VSTeamProject

    if (!$localProjects)
    {
        Write-Host "Org $($org.'Organization Name') does not contain a project and can be safely removed" -ForegroundColor Green
        $emptyOrgs += $org.Url + "_settings/organizationOverview"
    }
    else {
        $hasProject = $true
        Write-Host "Org $($org.'Organization Name') contains one or more projects and will be reviewed more closely:" -ForegroundColor Yellow
        $populatedOrgs += $org.'Organization Name'
        $globalProjects += ($org.Url + $localProjects.Name)
        $pipelines = @()
        $testplans = @()

        $none = '{"value":[],"count":0}'

        # Check if there are pipelines
        foreach ($proj in $localProjects)
        {
            $pipelines += Get-VSTeamBuildDefinition -ProjectName $proj.Name
            $testPlanResp = Invoke-RestMethod -Uri ($org.Url + $proj.Name + "/_apis/test/plans?api-version=5.0") -Headers @{Authorization="Basic $encodedPat"}

            if ($testPlanResp.value)
            {
                $hasTestPlans = $true
                Write-Host "The Project $($proj) in Org $($org.'Organization Name') contains one or more test plans!" -ForegroundColor Red
            }
            else {
                Write-Host "The Project $($proj) in Org $($org.'Organization Name') does not contain a test plan" -ForegroundColor Green
            }
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

        try {$packages = Get-VSTeamFeed | Get-VSTeamPackage
        }
        catch {
            echo "Error fetching packages from feed"
        }
        if (!$packages)
        {
            Write-Host "Org $($org.'Organization Name') does not contain Az Artifacts (Packages)" -ForegroundColor Green
        }
        else {
            $hasAzArtifacts = $true
            Write-Host "Org $($org.'Organization Name') has one or more Az Artifacts (Packages)" -ForegroundColor Red
        }
    }
        # Format to excel sheet
        $collection += [pscustomobject] @{
            OrgName = $org.'Organization Name'
            SettingsUrl = $org.Url + "_settings/organizationOverview"
            HasProject    = $hasProject
            HasPipelines  = $hasPipelines
            HasTestPlans = $hasTestPlans
            HasWorkItems  = $hasWorkItems
            HasGitHistory = $hasGitHistory
            HasAzArtifacts = $hasAzArtifacts
    }
    }
    catch {
        echo "Catching a forced disconnection.."
    }
}

$excel = $collection| export-excel -WorksheetName "ADO" -AutoSize -TableName Table1 -PassThru

$ws = $excel.Workbook.Worksheets["ADO"]
$lastRow = $ws.Dimension.End.Row

Add-ConditionalFormatting -WorkSheet $ws -address "C2:C$Lastrow" -RuleType Equal -ConditionValue "=FALSE" -BackgroundColor Green

Add-ConditionalFormatting -WorkSheet $ws -address "D2:D$Lastrow" -RuleType Equal -ConditionValue "=TRUE" -BackgroundColor Red
Add-ConditionalFormatting -WorkSheet $ws -address "E2:E$Lastrow" -RuleType Equal -ConditionValue "=TRUE" -BackgroundColor Red
Add-ConditionalFormatting -WorkSheet $ws -address "F2:F$Lastrow" -RuleType Equal -ConditionValue "=TRUE" -BackgroundColor Red
Add-ConditionalFormatting -WorkSheet $ws -address "G2:G$Lastrow" -RuleType Equal -ConditionValue "=TRUE" -BackgroundColor Red
Add-ConditionalFormatting -WorkSheet $ws -address "H2:H$Lastrow" -RuleType Equal -ConditionValue "=TRUE" -BackgroundColor Red

Close-ExcelPackage -Show $excel