# Convert "legacy private" repos to "internal" - dev toolbox

if ($env:github_token)
{
    $token = $env:github_token
}
else {
    Write-Host "You must set the 'github_token' env variable!" -ForegroundColor Red
    Exit
}

$allRepos

for ($i=1; $i -lt 4; $i++)
{
    $api = "https://api.github.com/orgs/equinor/teams/Equinor/repos?q&page=$i&per_page=100"
    $repos = Invoke-RestMethod -Uri $api -Headers @{Authorization="Token $token"}
    $allRepos += $repos | select html_url, description, updated_at, permissions 
}

$collection2= @() 

for ($i =0; $i -lt $allRepos.Length; $i++) # This step is only necessary due to pwsh having a hard time with deserialiing hashtables...
{
    $collection2 += [pscustomobject] @{
        Repo    = $allRepos[$i].html_url
        Description = $allRepos[$i].description
        HasPull       = $allRepos[$i].permissions.pull
        HasTriage = $allRepos[$i].permissions.triage
        HasPush      = $allRepos[$i].permissions.push
        HasMaintainer       = $allRepos[$i].permissions.maintain
        HasAdmin       = $allRepos[$i].permissions.admin
    }
}

$collection2 | export-excel