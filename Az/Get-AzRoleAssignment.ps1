param(
    [string] [Parameter(Mandatory=$true)]  $ObjectId
    )

<#
    .DESCRIPTION
    Loops over all available subscriptions and fetches role assignments for a specific object id.

    .PARAMETER ObjectId
    The object Id to use. This is required.

#>


# Fetch all platform subscriptions
$allsubs = Get-AzSubscription | Where-Object Name -Match "[ptd]-.*"
$roleassignments = @()

foreach ($sub in $allsubs) {

    Set-AzContext $sub.Name | Out-Null
    Write-Host "Processing subscription $($sub.Name)"
    $roleassignments += Get-AzRoleAssignment -ObjectId $ObjectId

}

$roleassignments