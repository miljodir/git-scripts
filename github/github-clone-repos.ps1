<#
.SYNOPSIS
    Clones all repositories in a GitHub organization with a given language.
#>

param (
    [string] [Parameter(Mandatory=$false)] $org = "myorg",
    [string] [Parameter(Mandatory=$false)] $language = "hcl"
)

$repos = gh repo list $org --limit 100 --json name --language $language --jq .[].name

function Reset {
    git -C $repo reset --hard
    git -C $repo clean -fd
    git -C $repo checkout main
    git -C $repo pull
}

Write-Host "Found the following repos in org $($org):"
$repos

foreach ($repo in $repos) {

        Write-Host "Cloning $repo"
        gh repo clone "$org/$repo"

        if (!$?) {
            Write-Host "Failed to clone $repo, assuming it already existis in parent folder, attempting to pull latest branch"
            Reset
        }
    }