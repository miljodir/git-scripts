## Per September 2020, Github API does not provide a direct API to list "SAML unlinked" members. Only all members, and linked members. The diff between thoes should re-create the list of unlinked members.
## Github also doesn't enforce users to put their Equinor email, so creating a mailing list for those users will need another lookup.

$url = "https://api.github.com/graphql"

if ($env:github_token)
{
    $token = $env:github_token
}
else {
    Write-Host "You must set the 'github_token' env variable!" -ForegroundColor Red
    Exit
}


$headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
$headers.Add("content-type","application/json")
$headers.Add("Authorization","bearer $token")

$offset2 = ""

$bodyB = '{"query":"query { organization(login: \"Equinor\") { samlIdentityProvider { ssoUrl, externalIdentities(first: 100) { edges { node { samlIdentity {nameId}, user {name, login} } } pageInfo {endCursor, hasNextPage}  } } } }"}'

[array]$fulltable = New-Object PsObject -Property @{ login='' ; name='' }
[array]$fullLogin = New-Object PsObject -Property @{ nameId = '' }

Do

{
    $response2 = Invoke-WebRequest -Uri $url -Method Post -Body $bodyB -Headers $headers

    $resp2 = $response2.Content | convertfrom-json
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

$fulltable | Export-Excel
$fullLogin | Export-Excel
