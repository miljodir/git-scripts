# Find repos in an organization that have security alerts enabled but not automated security fixes enabled
$org = "miljodir"

$allRepos = gh api --paginate /orgs/$org/repos | jq -r .[].name

$deploykeys = @()
function Get-DeployKeys {
    $repokeys = gh api /repos/$org/$folder/keys | jq -r '.[].title'

    if ($null -ne $repokeys) {
        $script:deploykeys += [PSCustomObject]@{
            Repo       = $folder
            Deploykeys = $repokeys
        }
    }
}

foreach ($folder in $allRepos) {
    Get-DeployKeys
}

$deploykeys