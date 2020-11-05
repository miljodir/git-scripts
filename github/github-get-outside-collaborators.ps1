if ($env:github_token)
{
    $token = $env:github_token
}
else {
    Write-Host "You must set the 'github_token' env variable!" -ForegroundColor Red
    Exit
}

$allOutsideCollabs

for ($i=1; $i -lt 5; $i++)
{
    $api = "https://api.github.com/orgs/equinor/outside_collaborators?q&page=$i&per_page=100"
    $collabs = Invoke-WebRequest -Uri $api -Headers @{Authorization="Token $token"}
    $allOutsideCollabs += $collabs.Content | ConvertFrom-Json | select login, html_url
}

$allOutsideCollabs
