<#
.SYNOPSIS
Update the permissions of a Github team across all repositories it has access to
#>

param (
  [string] [Parameter(Mandatory=$true)] $team = "myteam",
  [string] [Parameter(Mandatory=$true)] $org = "miljodir",
  [string] [Parameter(Mandatory=$true)] $role = "SecurityAlertManagement"
)

#$internalrepos = gh api /orgs/miljodir/teams/$team/repos --paginate | ConvertFrom-Json

#$internalrepos2 = gh api /orgs/miljodir/teams/miljodir-internal/repos | ConvertFrom-Json

#foreach ($repo in $internalrepos2[0])
foreach ($repo in $internalrepos[0])
{
    gh api --method PUT /orgs/$org/teams/$team/repos/$($repo.full_name) -f "role_name=$($role)"
}