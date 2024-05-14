param(
    [string] [Parameter(Mandatory = $false)]  $repo = "dummyrepo"
)

# TODO - only reads 100 artifacts at a time
# TODO - fetch list of repos automatically?
$ids = gh api /repos/miljodir/$repo/actions/artifacts --paginate --jq .[].[].id

Write-Host "Deleting $($ids.count) artifacts from $repo"
foreach ($id in $ids) {
    gh api /repos/miljodir/$repo/actions/artifacts/$id --method DELETE
    if ($?)
    {
        Write-Host "Deleting artifact $id"
    }
}