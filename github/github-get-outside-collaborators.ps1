if ($env:github_token)
{
    $token = $env:github_token
}
else {
    Write-Host "You must set the 'github_token' env variable!" -ForegroundColor Red
    Exit
}

$allEquinorRepos

# Fetch org admins so we can filter them out from repo admins later on
$orgAdmins = Invoke-RestMethod -Method Get -Uri "https://api.github.com/orgs/equinor/members?role=admin" -Headers @{Authorization="Token $token"} -ContentType "application/json"

$url = "https://api.github.com/graphql"
$offset = ""
[array]$fulltable = New-Object PsObject -Property @{name=''; collaborators='' }

# Fetch all repos, get all outside collabs
$body = @'
{"query":"query { organization(login: \"Equinor\") { repositories(first: 100) { edges { node { name collaborators(affiliation: OUTSIDE) { edges { permission node {login}}}}} pageInfo {endCursor, hasNextPage}}}}"}
'@

Do
{
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

} While ($hasNextPage) 

$apiBase = "https://api.github.com/"

$collection = @()

## This part fetches saml identities so we can get emails of the repo admins (first all github members)
$offset2 = ""

$bodyB = '{"query":"query { organization(login: \"Equinor\") { samlIdentityProvider { ssoUrl, externalIdentities(first: 100) { edges { node { samlIdentity {nameId}, user {name, login} } } pageInfo {endCursor, hasNextPage}  } } } }"}'

[array]$fullTable2 = New-Object PsObject -Property @{ login='' ; name='' }
[array]$fullLogin = New-Object PsObject -Property @{ nameId = '' }

$collection2 = @()

Do
{
    $resp2 = Invoke-RestMethod -Uri $url -Method Post -Body $bodyB -Headers @{Authorization="Token $token"}

    $offset2 = $resp2.data.organization.samlIdentityProvider.externalIdentities.pageInfo.endCursor
    $hasNextPage2 = $resp2.data.organization.samlIdentityProvider.externalIdentities.pageInfo.hasNextPage
    $hashtable2 = $resp2.data.organization.samlIdentityProvider.externalIdentities.edges.node

    $bodyB = '{"query":"query { organization(login: \"Equinor\") { samlIdentityProvider { ssoUrl, externalIdentities(first: 100 after: \"$offset2\") { edges { node { samlIdentity {nameId}, user {name, login} } } pageInfo {endCursor, hasNextPage}  } } } }"}'
    $bodyB = $ExecutionContext.InvokeCommand.ExpandString($bodyB)

    echo "Has next page: $hasNextPage2"

    echo "offset: $offset2"
    $fullTable2 += $hashtable2.user
    $fullLogin += $hashtable2.samlIdentity

    echo "SAML Page completed. Next iteration: "

} While ($hasNextPage2) 

for ($i = 0; $i -lt $fullTable2.Length; $i++)
{
  $collection2 += [pscustomobject] @{
    FullName  = $fullTable2[$i].name
    GithubLogin  = $fullTable2[$i].login
    SamlIdentity = $fullLogin[$i].nameId
  }
}

# Summaraize outside collabs + permissions and repo names into a table.
foreach ($item in $fulltable)
{
    if ($item.collaborators.edges.node.login -ne $null)
    {
        $collection += [pscustomobject] @{
            RepoName   = "equinor/$($item.name)"
            OutsideCollaborators = ($item.collaborators.edges.node.login -join ', ')
            CollabsPermissions   = ($item.collaborators.edges.permission -join ', ')
        }
    }
}

# Get the repo admins
foreach ($repo in $collection)
{
    $api2 = $apiBase + "repos/$($repo.RepoName)/collaborators" #GET /collabs of repo with permissions
    $call = Invoke-RestMethod -Method Get -Uri $api2 -Headers @{Authorization="Token $token"}

    $admins = ""
    $adminEmails = ""

        foreach ($user in $call)
        {
            if ($user.login -notin $orgAdmins.login -and $user.permissions.admin)
            {
                foreach ($id in $collection2)
                {
                    if ($user.login -eq $id.GithubLogin)
                    {
                        $adminEmails += $id.SamlIdentity + ", "
                        break
                    }
                }
                
                $admins += $user.login + ", "
            }
        }

        if ($adminEmails)
        {
            $adminEmails = $adminEmails.Substring(0, $adminEmails.length-2) #Remove last comma and space
        }

        $repo | Add-Member -NotePropertyName "RepoAdmins" -NotePropertyValue $admins
        $repo | Add-Member -NotePropertyName "RepoAdminsEmail" -NotePropertyValue $adminEmails   
        $repo | Add-Member -NotePropertyName "RepoSettingsUrl" -NotePropertyValue "https://github.com/equinor/$($repo.RepoName)/settings/access"
}

$collection | export-excel