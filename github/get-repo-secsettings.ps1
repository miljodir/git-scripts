# Find repos in an organization that have security alerts enabled but not automated security fixes enabled
$org = "miljodir"

$allRepos = gh api --paginate /orgs/$org/repos | jq -r .[].name
$filteredRepos = $allRepos | Where-Object { $_ -NotMatch "cp-*" } | Where-Object { $_ -NotMatch "wl-*" } | Where-Object { $_ -NotMatch "terraform-*" }

$secAutomation = @()
function Get-SecurityAutomation {
    $security2 = gh api -i /repos/$org/$folder/vulnerability-alerts
    $security2 = $security2.Split([Environment]::NewLine) | Select -First 1

    if ($security2 -eq "HTTP/2.0 404 Not Found") {
        $security2 = "false"
    }
    else {
        $security2 = "true"
    }

    $security = "false"
    if ($security2 -eq "true") {
        $security = gh api repos/$org/$folder/automated-security-fixes | jq -r .enabled
    }
    
    $script:secAutomation += [PSCustomObject]@{
        Repo              = $folder
        VulnAlertsEnabled = $security2
        AutoFixPrsEnabled = $security || "Enabled"
    }
}

foreach ($folder in $filteredRepos) {
    Get-SecurityAutomation
}

$secAutomation = $secAutomation | Where-Object VulnAlertsEnabled -eq true | Where-Object AutoFixPrsEnabled -eq false

foreach ($sec in $secAutomation) {
    Write-Host "Enabling Automated Security Fixes for $($sec.Repo)"
    gh api -X PUT repos/$org/$($sec.repo)/automated-security-fixes
}