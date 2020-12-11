$url = "https://api.github.com/graphql"

if ($env:github_token)
{
    $token = $env:github_token
}
else {
    Write-Host "You must set the 'github_token' env variable!" -ForegroundColor Red
    Exit
}

$offset2 = ""

$bodyB = '{"query":"query { organization(login: \"Equinor\") { samlIdentityProvider { ssoUrl, externalIdentities(first: 100) { edges { node { samlIdentity {nameId}, user {name, login} } } pageInfo {endCursor, hasNextPage}  } } } }"}'

[array]$fullTable = New-Object PsObject -Property @{ login='' ; name='' }
[array]$fullLogin = New-Object PsObject -Property @{ nameId = '' }

$collection = @()

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
    $fullTable += $hashtable2.user
    $fullLogin += $hashtable2.samlIdentity

    echo "SAML Page completed. Next iteration: "

} While ($hasNextPage2) 

for ($i = 0; $i -lt $fullTable.Length; $i++)
{
  $collection += [pscustomobject] @{
    FullName  = $fullTable[$i].name
    GithubLogin  = $fullTable[$i].login
    SamlIdentity = $fullLogin[$i].nameId
  }
}

$collection | Export-Excel