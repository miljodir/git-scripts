if ($env:github_token)
{
    $token = $env:github_token
}
else {
    Write-Host "You must set the 'github_token' env variable!" -ForegroundColor Red
    Exit
}

#$allOutsideCollabs
$allEquinorRepos
<#
for ($i=1; $i -lt 5; $i++)
{
    $api = "https://api.github.com/orgs/equinor/outside_collaborators?q&page=$i&per_page=100"
    $collabs = Invoke-WebRequest -Uri $api -Headers @{Authorization="Token $token"}
    $allOutsideCollabs += $collabs.Content | ConvertFrom-Json | select login, html_url
}#>

$orgAdmins = Invoke-RestMethod -Method Get -Uri "https://api.github.com/orgs/equinor/members?role=admin" -Headers @{Authorization="Token $token"} -ContentType "application/json"


$url = "https://api.github.com/graphql"
$offset = ""
[array]$fulltable = New-Object PsObject -Property @{name=''; collaborators='' }

$body = @'
{"query":"query { organization(login: \"Equinor\") { repositories(first: 100) { edges { node { name collaborators(affiliation: OUTSIDE) { edges { permission node {login}}}}} pageInfo {endCursor, hasNextPage}}}}"}
'@

#Do

#{
    $response = Invoke-RestMethod -Uri $url -Method Post -Body $body -Headers @{Authorization="Token $token"} -ContentType "application/json"

    $offset = $response.data.organization.repositories.pageInfo.endCursor
    $hasNextPage = $response.data.organization.repositories.pageInfo.hasNextPage
    $hashtable = $response.data.organization.repositories.edges.node

$body = @'
    {"query":"query { organization(login: \"Equinor\") { repositories(first: 100 after: \"$offset\") { edges { node { name collaborators(affiliation: OUTSIDE) { edges { permission node {login}}}}} pageInfo {endCursor, hasNextPage}}}}"}
'@

    $body = $ExecutionContext.InvokeCommand.ExpandString($body)

    echo "Has next page: $hasNextPage"
    echo "offset: $offset"

    $fulltable += $hashtable

    echo "Member Page completed. Next iteration: "

#} While ($hasNextPage) 

$apiBase = "https://api.github.com/"

$collection = @()

foreach ($item in $fulltable)
{
    if ($item.collaborators.edges.node.login -ne $null)
    {
        $collection += [pscustomobject] @{
            Name   = $item.name
            OutsideCollaborators = ($item.collaborators.edges.node.login -join ', ')
            CollabsPermissions   = ($item.collaborators.edges.permission -join ', ')
        }
    }
}

foreach ($repo in $collection)
{
    $api2 = $apiBase + "repos/equinor/$($repo.Name)/collaborators" #GET /collabs of repo with permissions
    $call = Invoke-RestMethod -Method Get -Uri $api2 -Headers @{Authorization="Token $token"}

    $admins = ""

        foreach ($user in $call)
        {
            if ($user.login -notin $orgAdmins.login -and $user.permissions.admin)
            {
                $admins += $user.login + ", "
            }
        }
        $repo | Add-Member -NotePropertyName "RepoAdmins" -NotePropertyValue $admins
        $repo | Add-Member -NotePropertyName "RepoSettingsUrl" -NotePropertyValue "https://github.com/equinor/$($repo.Name)/settings/access"
}

$collection | export-excel