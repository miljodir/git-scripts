$org = "miljodir"

$allRepos = gh api --paginate /orgs/$org/repos | jq .[].name
$allRepos = $allRepos.Replace('"', '')
$envSecrets = @()
$regularSecrets = @()

function Find-GHSecrets {

    $normalsecrets = gh api repos/$org/$folder/actions/secrets | jq .secrets[].name
    if ($null -ne $normalsecrets) {
        $normalsecrets = $normalsecrets.Replace('"', '')
    }

    $script:regularSecrets += [PSCustomObject]@{
        Repo   = $folder
        Secret = $normalsecrets
    }

    $envs = gh api repos/$org/$folder/environments | jq .environments[].name
    if ($null -ne $envs) {
        $envs = $envs.Replace('"', '')
    }

    foreach ($env in $envs) {
        $secrets = gh api repos/$org/$folder/environments/$env/secrets | jq .secrets
        $name = $secrets | jq .[].name
        if ($null -ne $name) {
            $name = $name.Replace('"', '')
        }

        $script:envSecrets += [PSCustomObject]@{
            Repo        = $folder
            Environment = $env
            Secret      = $name
        }
    }
}

foreach ($folder in $allRepos) {
    Find-GHSecrets
}

$regularSecrets | Format-Table
$envSecrets | Format-Table