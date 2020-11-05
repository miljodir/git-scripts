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

for ($i=1; $i -lt 3; $i++)
{
    $api = "https://api.github.com/orgs/equinor/repos?q&page=$i&per_page=3"
    $repos = Invoke-WebRequest -Uri $api -Headers @{Authorization="Token $token"}
    $allEquinorRepos += $repos.Content | ConvertFrom-Json | select name, html_url
}

for ($i=1; $i -lt $allEquinorRepos.Length; $i++)
{
    $api = "https://api.github.com/repos/equinor/$($allEquinorRepos[$i].name)/collaborators?q&affiliation=outside"

    $response = Invoke-WebRequest -Uri $api -Headers @{Authorization="Token $token"}

    if ($response.Content -notlike '`[]')
    {
        Write-Host "REPO: $($allEquinorRepos[$i].html_url) has outside collaborators:" -ForegroundColor Yellow
        $response.Content | ConvertFrom-Json | select login, html_url, permissions | out-default
    }
}