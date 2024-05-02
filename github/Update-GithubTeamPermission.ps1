<#
.SYNOPSIS
Update the permissions of a Github team across all repositories it has access to
#>

param (
  [string] [Parameter(Mandatory=$false)] $team = "mysecurityteam",
  [string] [Parameter(Mandatory=$false)] $org = "miljodir",
  [string] [Parameter(Mandatory=$false)] $role = "SecurityAlertManagement" # Custom or built-in role.
)

$internalrepos = gh api /orgs/$org/teams/$team/repos --paginate | ConvertFrom-Json

#$internalrepos2 = gh api /orgs/$org/teams/$team/repos | ConvertFrom-Json

#foreach ($repo in $internalrepos2[0])
foreach ($repo in $internalrepos)
{
    gh api --method PUT /orgs/$org/teams/$team/repos/$($repo.full_name) -f "permission=$role"
}