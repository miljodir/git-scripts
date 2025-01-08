<#
.SYNOPSIS
Fetch code scanning alerts in an org and attempt creating autofixes
#>

param (
  [string] [Parameter(Mandatory=$false)] $org = "miljodir",
  [string] [Parameter(Mandatory=$false)] $tool = "CodeQL",
  [string] [Parameter(Mandatory=$false)] $ruleFilter = "cs/*"
)

if ($org -eq "miljodir") {
  $env:jwt = (node ../../local-repo-sync/authapp/app.js $org | ConvertFrom-Json | Select-Object token -ExpandProperty token)
}

#$criticalAlerts =  gh api --method GET "/orgs/$org/code-scanning/alerts?state=open&tool_name=$tool&severity=critical" --paginate | ConvertFrom-Json 
$alerts = gh api --method GET "/orgs/$org/code-scanning/alerts?state=open&tool_name=$tool" --paginate | ConvertFrom-Json
$filteredAlerts = $alerts | Where-Object { $_.rule.id -like $ruleFilter -and ($_.most_recent_instance.classifications -ne "generated" -or "" -eq $_.most_recent_instance.classifications) }
$repofilter = "myrepo"
#$filteredAlerts = $filteredAlerts | Where-Object { $_.repository.name -like $repofilter }

# Group alerts by repository
$alertsByRepo = $filteredAlerts | Group-Object -Property { $_.repository.name }


foreach ($alert in $filteredAlerts) {
  $alertNumber = $alert.number
  $repo = $alert.repository.name
  Write-Host "Attempting to create autofix for alert $alertNumber in repo $repo"
  gh api `
    --method POST `
    /repos/$org/$repo/code-scanning/alerts/$alertNumber/autofix
}


function CreateBranchFromDefault {
  param (
      [Parameter(Mandatory = $true)]
      [string]$org,
      [Parameter(Mandatory = $true)]
      [string]$repo,
      [Parameter(Mandatory = $true)]
      [string]$newBranch
  )

  # Get the default branch
  $defaultBranch = gh api /repos/$org/$repo | ConvertFrom-Json | Select-Object -ExpandProperty default_branch

  # Get the latest commit SHA from the default branch
  $latestCommitSha = gh api /repos/$org/$repo/git/ref/heads/$defaultBranch | ConvertFrom-Json | Select-Object -ExpandProperty object | Select-Object -ExpandProperty sha

  # Create a new branch from the default branch
  gh api /repos/$org/$repo/git/refs -f ref="refs/heads/$newBranch" -f sha=$latestCommitSha
}



# foreach ($folder in $filteredAlerts.repository.name | Sort-Object | get-unique) {
#   CreateBranchFromDefault -org $org -repo $folder -newBranch "codeql-autofixes"
# }

# after fix is created, commit the fix to the branch
#Start-Sleep 30
$alerts = @()

# foreach ($alert in $filteredAlerts) {
#   $alertNumber = $alert.number
#   $repo = $alert.repository.name
#   $alerts += $alert.html_url
#   Write-Host "Attempting to create autofix for alert $alertNumber in repo $repo"
#   gh api `
#     --method POST `
#     /repos/$org/$repo/code-scanning/alerts/$alertNumber/autofix/commits `
#     -f "target_ref=refs/heads/codeql-autofixes" -f "message=AI-generated autofix for alert $alertNumber"
# }

# finally - create a pull request with all the generated autofixes


function New-PR {

  param (
      [Parameter(Mandatory = $true)]
      [string]$defaultBranch
  )

  gh api `
      --method POST `
      -H "Accept: application/vnd.github.v3+json" `
      "/repos/$org/$folder/pulls" `
      -f title="AI-generated CodeQL autofixes" `
      -f body="This PR batches together all C# AI-generated autofixable CodeQL alerts found in the repository. Consider testing these changes rather than blindly trusting the AI. This PR attempts to fix the following issues: $alerts" `
      -f head='codeql-autofixes' `
      -f base=$defaultBranch
      #-f draft='false'
}

# foreach ($repoGroup in $alertsByRepo) {
#     $mostRecentAlert = $repoGroup.Group | Sort-Object -Property { $_.most_recent_instance.ref } -Descending | Select-Object -First 1

#     # Create a new PR for the repository
#     New-PR -defaultBranch ($mostRecentAlert.most_recent_instance.ref).Split("/")[-1]
# }