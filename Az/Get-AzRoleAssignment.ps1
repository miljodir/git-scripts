#requires -Version 7.0
<#
    .DESCRIPTION
    Fetches role assignments for a specific object id in all platform subscriptions in the current tenant.
    Subscriptions are queried in parallel without changing the current Az context.

    .PARAMETER ObjectId
    The object Id to use. This is required.

    .PARAMETER ThrottleLimit
    The maximum number of subscriptions to query at the same time.

#>
param(
    [string] [Parameter(Mandatory=$true)]  $ObjectId,

    [ValidateRange(1, 64)]
    [int] $ThrottleLimit = 16
)

$context = Get-AzContext
if (-not $context) {
    throw "Run Connect-AzAccount before running this script."
}

# Fetch all platform subscriptions
$allsubs = @(Get-AzSubscription -TenantId $context.Tenant.Id | Where-Object Name -Match "[ptd]-.*")

$results = $allsubs | ForEach-Object -ThrottleLimit $ThrottleLimit -Parallel {
    Write-Host "Processing subscription $($_.Name)"

    [pscustomobject]@{
        SubscriptionId  = $_.Id
        RoleAssignments  = @(Get-AzRoleAssignment -ObjectId $using:ObjectId -Scope "/subscriptions/$($_.Id)" -DefaultProfile $using:context)
    }
}

$resultsBySubscription = @{}
foreach ($result in $results) {
    $resultsBySubscription[$result.SubscriptionId] = $result.RoleAssignments
}

# Keep the output in subscription order, as when the subscriptions were processed one by one.
foreach ($sub in $allsubs) {
    $resultsBySubscription[$sub.Id]
}
