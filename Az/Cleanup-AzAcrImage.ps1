param(
    [string] [Parameter(Mandatory=$true)]  $RegistryName,
    [string] [Parameter(Mandatory=$false)]  $Timestamp = "2019-08-14",
    [string[]] [Parameter(Mandatory=$false)]  $Filter = @("myteam1/myappA", "myteam2/myappB")
    )

# Based and improved off
# https://learn.microsoft.com/en-us/azure/container-registry/container-registry-delete#delete-digests-by-timestamp

# WARNING! This script deletes data!
# Run only if you do not have systems
# that pull images via manifest digest.

# Change to 'true' to enable image delete
$ENABLE_DELETE = $false

# Modify for your environment
# TIMESTAMP can be a date-time string such as 2019-03-15T17:55:00.

# image tags can be fetched with this command, but this will only work given that your image tags containts the date of creation
# kubectl get pods --all-namespaces -o jsonpath="{.items[*].spec.containers[*].image}"
$Timestamp = "2023-08-14" # ensure this is the same date as the oldest images you want to keep!

$filter = "myteam1/myappA", "myteam2/myappB" # image repositories to exclude from deletion
$repositories = az acr repository list --name $RegistryName | jq -r .[]
$repositories = $repositories | Where-Object { ($filter)  -notcontains $_ }

# Delete all images older than specified timestamp.


foreach ($repository in $repositories) {
    Write-Host "Processing repository: $repository"
    $imagestoDelete = @()
    $images = az acr manifest list-metadata -r $RegistryName -n $repository --orderby time_asc | convertfrom-json
    $imagestoDelete += $images | Where-Object { $_.lastUpdateTime -lt $Timestamp }  

    foreach ($image in $imagestoDelete) {
        if ($ENABLE_DELETE) {
            az acr repository delete --name $RegistryName --image "$($repository)@$($image.digest)" --yes
        }
        else {
            Write-Host "Would delete $repository@$($image.digest)"
        }
    }

    if ($ENABLE_DELETE) {
        Write-Host "Deleted $($imagestoDelete.Count) old image manifests from repository $repository"
    }
    else {
        Write-Host "Would delete $($imagestoDelete.Count) old image manifests from repository $repository"
    }
}