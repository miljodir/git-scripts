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


$url = "https://api.github.com/graphql"
$offset = ""
[array]$fulltable = New-Object PsObject -Property @{name=''; collaborators='' }

$body = @'
{"query":"query { organization(login: \"Equinor\") { repositories(first: 100) { edges { node { name collaborators(affiliation: OUTSIDE) { edges { permission node {login}}}}} pageInfo {endCursor, hasNextPage}}}}"}
'@

Do

{
    $response = Invoke-WebRequest -Uri $url -Method Post -Body $body -Headers @{Authorization="Token $token"} -ContentType "application/json"

    $resp = $response.Content | convertfrom-json
    $offset = $resp.data.organization.repositories.pageInfo.endCursor
    $hasNextPage = $resp.data.organization.repositories.pageInfo.hasNextPage
    $hashtable = $resp.data.organization.repositories.edges.node

$body = @'
    {"query":"query { organization(login: \"Equinor\") { repositories(first: 100 after: \"$offset\") { edges { node { name collaborators(affiliation: OUTSIDE) { edges { permission node {login}}}}} pageInfo {endCursor, hasNextPage}}}}"}
'@

    $body = $ExecutionContext.InvokeCommand.ExpandString($body)

    echo "Has next page: $hasNextPage"
    echo "offset: $offset"

    $fulltable += $hashtable

    echo "Member Page completed. Next iteration: "

} While ($hasNextPage) 

$collection = @()

foreach ($item in $fulltable)
{
    $collection += [pscustomobject] @{
        Repo   = $item.name
        ExternalCollaborators = ($item.collaborators.edges.node.login -join ', ')
        Permissions   = ($item.collaborators.edges.permission -join ', ')
    }
}

$collection | export-excel