<#
.SYNOPSIS
Deletes ACR manifests that are not used by the configured AKS clusters.

.DESCRIPTION
The script reads image references from pods and workload specs in the selected
Kubernetes contexts, protects matching ACR tags and digests, always protects
manifests tagged latest, and makes every other manifest eligible for deletion.
Deletion is disabled by default; pass -EnableDelete to actually remove
manifests.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -RegistryName myacr -AksResourceGroup my-rg

Dry-runs cleanup for myacr after refreshing the configured AKS credentials.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -RegistryName myacr -AksResourceGroup my-rg -EnableDelete

Deletes manifests from myacr that are not referenced by the configured
Kubernetes contexts.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -SkipAksCredentials -IncludeRepositoryPrefix avdekl,testteam1

Only evaluates repositories below the avdekl/ and testteam1/ prefixes, and only
scans those Kubernetes namespaces in each configured context.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -SkipAksCredentials -KubeContext d-aks,t-aks,p-aks

Protects images referenced by all three Kubernetes contexts.
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $false)]
    [string] $RegistryName = "filtered",

    [Parameter(Mandatory = $false)]
    [string] $AksClusterName = "filtered-aks",

    [Parameter(Mandatory = $false)]
    [string] $AksResourceGroup = "filtered-aks",

    [Parameter(Mandatory = $false)]
    [string[]] $KubeContext = @("d-aks", "t-aks", "p-aks"),

    [Parameter(Mandatory = $false)]
    [string[]] $KubernetesResourceKind = @("pods", "deployments", "statefulsets", "daemonsets", "jobs", "cronjobs"),

    [Parameter(Mandatory = $false)]
    [Alias("Filter")]
    [string[]] $ExcludeRepository = @(""),

    [Parameter(Mandatory = $false)]
    [Alias("RepositoryPrefix", "Prefix")]
    [string[]] $IncludeRepositoryPrefix = @(),

    [Parameter(Mandatory = $false)]
    [switch] $EnableDelete,

    [Parameter(Mandatory = $false)]
    [switch] $SkipAksCredentials
)

function Assert-CommandExists {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command '$Name' was not found in PATH."
    }
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Command,

        [Parameter(Mandatory = $true)]
        [string] $ErrorMessage
    )

    $output = & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$ErrorMessage Exit code: $LASTEXITCODE."
    }

    return $output
}

function Invoke-JsonCommand {
    param(
        [Parameter(Mandatory = $true)]
        [scriptblock] $Command,

        [Parameter(Mandatory = $true)]
        [string] $ErrorMessage
    )

    $json = Invoke-NativeCommand -Command $Command -ErrorMessage $ErrorMessage
    if (-not $json) {
        return $null
    }

    return $json | ConvertFrom-Json -ErrorAction Stop
}

function Get-NormalizedStringList {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $Values = @()
    )

    $normalizedValues = [System.Collections.Generic.List[string]]::new()

    foreach ($value in @($Values)) {
        foreach ($item in @($value -split ",")) {
            $normalizedValue = $item.Trim().Trim("/")

            if (-not [string]::IsNullOrWhiteSpace($normalizedValue)) {
                $normalizedValues.Add($normalizedValue)
            }
        }
    }

    return @($normalizedValues)
}

function Test-RepositoryPrefix {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repository,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $IncludeRepositoryPrefix = @()
    )

    if (@($IncludeRepositoryPrefix).Count -eq 0) {
        return $true
    }

    foreach ($prefix in $IncludeRepositoryPrefix) {
        if ($Repository.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or
            $Repository.StartsWith("$prefix/", [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Get-RepositoryFromImageReference {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Reference
    )

    $digestSeparator = $Reference.IndexOf("@", [System.StringComparison]::Ordinal)
    if ($digestSeparator -ge 0) {
        return $Reference.Substring(0, $digestSeparator)
    }

    $tagSeparator = $Reference.LastIndexOf(":", [System.StringComparison]::Ordinal)
    if ($tagSeparator -ge 0) {
        return $Reference.Substring(0, $tagSeparator)
    }

    return $Reference
}

function Get-FilteredImageReferenceSet {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $References,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $Repositories
    )

    $filteredReferences = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($reference in $References) {
        $repository = Get-RepositoryFromImageReference -Reference $reference

        if ($Repositories.Contains($repository)) {
            [void] $filteredReferences.Add($reference)
        }
    }

    return $filteredReferences
}

function Get-KubernetesNamespaceFromRepositoryPrefix {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $IncludeRepositoryPrefix = @()
    )

    $namespaces = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($prefix in @($IncludeRepositoryPrefix)) {
        $namespace = @($prefix -split "/")[0]

        if (-not [string]::IsNullOrWhiteSpace($namespace)) {
            [void] $namespaces.Add($namespace)
        }
    }

    return @($namespaces)
}

function Test-KubernetesNamespaceExists {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Namespace,

        [Parameter(Mandatory = $true)]
        [string[]] $KubectlArguments
    )

    $output = Invoke-NativeCommand `
        -Command { kubectl @KubectlArguments get namespace $Namespace --ignore-not-found --output name } `
        -ErrorMessage "Failed to check namespace '$Namespace'."

    return -not [string]::IsNullOrWhiteSpace(($output -join "").Trim())
}

function Get-AcrImageReference {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Image,

        [Parameter(Mandatory = $true)]
        [string] $LoginServer
    )

    if ([string]::IsNullOrWhiteSpace($Image)) {
        return $null
    }

    $normalizedImage = $Image -replace "^[a-zA-Z][a-zA-Z0-9+.-]*://", ""
    $registryPrefix = "$LoginServer/"

    if (-not $normalizedImage.StartsWith($registryPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }

    $repositoryAndReference = $normalizedImage.Substring($registryPrefix.Length)
    $digestSeparator = $repositoryAndReference.IndexOf("@", [System.StringComparison]::Ordinal)

    if ($digestSeparator -ge 0) {
        $repository = $repositoryAndReference.Substring(0, $digestSeparator)
        $digest = $repositoryAndReference.Substring($digestSeparator + 1)

        if ([string]::IsNullOrWhiteSpace($repository) -or [string]::IsNullOrWhiteSpace($digest)) {
            return $null
        }

        return [pscustomobject]@{
            Repository = $repository
            Tag        = $null
            Digest     = $digest.ToLowerInvariant()
        }
    }

    $lastSlash = $repositoryAndReference.LastIndexOf("/", [System.StringComparison]::Ordinal)
    $tagSeparator = $repositoryAndReference.LastIndexOf(":", [System.StringComparison]::Ordinal)

    if ($tagSeparator -gt $lastSlash) {
        $repository = $repositoryAndReference.Substring(0, $tagSeparator)
        $tag = $repositoryAndReference.Substring($tagSeparator + 1)
    }
    else {
        $repository = $repositoryAndReference
        $tag = "latest"
    }

    if ([string]::IsNullOrWhiteSpace($repository) -or [string]::IsNullOrWhiteSpace($tag)) {
        return $null
    }

    return [pscustomobject]@{
        Repository = $repository
        Tag        = $tag
        Digest     = $null
    }
}

function Add-UsedImageReference {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Image,

        [Parameter(Mandatory = $true)]
        [string] $LoginServer,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $UsedTags,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $UsedDigests,

        [Parameter(Mandatory = $false)]
        [hashtable] $UsedTagContexts,

        [Parameter(Mandatory = $false)]
        [string] $ContextName
    )

    if ([string]::IsNullOrWhiteSpace($Image)) {
        return
    }

    $reference = Get-AcrImageReference -Image $Image -LoginServer $LoginServer
    if (-not $reference) {
        return
    }

    if ($reference.Digest) {
        [void] $UsedDigests.Add("$($reference.Repository)@$($reference.Digest)")
    }

    if ($reference.Tag) {
        $tagKey = "$($reference.Repository):$($reference.Tag)"
        [void] $UsedTags.Add($tagKey)

        if ($null -ne $UsedTagContexts -and -not [string]::IsNullOrWhiteSpace($ContextName)) {
            if (-not $UsedTagContexts.ContainsKey($tagKey)) {
                $UsedTagContexts[$tagKey] = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
            }

            [void] $UsedTagContexts[$tagKey].Add($ContextName)
        }
    }
}

function Add-ImageReferencesFromObject {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter(Mandatory = $true)]
        [string] $LoginServer,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $UsedTags,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[string]] $UsedDigests,

        [Parameter(Mandatory = $false)]
        [hashtable] $UsedTagContexts,

        [Parameter(Mandatory = $false)]
        [string] $ContextName,

        [Parameter(Mandatory = $false)]
        [int] $Depth = 0
    )

    if ($null -eq $InputObject -or $InputObject -is [string]) {
        return
    }

    if ($Depth -gt 50) {
        Write-Warning "Skipping image-reference scan below depth $Depth to avoid recursive object traversal."
        return
    }

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $value = $InputObject[$key]

            if ($key -eq "image" -or $key -eq "imageID") {
                Add-UsedImageReference -Image $value -LoginServer $LoginServer -UsedTags $UsedTags -UsedDigests $UsedDigests -UsedTagContexts $UsedTagContexts -ContextName $ContextName
            }

            Add-ImageReferencesFromObject -InputObject $value -LoginServer $LoginServer -UsedTags $UsedTags -UsedDigests $UsedDigests -UsedTagContexts $UsedTagContexts -ContextName $ContextName -Depth ($Depth + 1)
        }

        return
    }

    if ($InputObject -is [System.Collections.IEnumerable]) {
        foreach ($item in $InputObject) {
            Add-ImageReferencesFromObject -InputObject $item -LoginServer $LoginServer -UsedTags $UsedTags -UsedDigests $UsedDigests -UsedTagContexts $UsedTagContexts -ContextName $ContextName -Depth ($Depth + 1)
        }

        return
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        if ($property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty) {
            continue
        }

        if ($property.Name -eq "metadata" -or $property.Name -eq "apiVersion" -or $property.Name -eq "kind") {
            continue
        }

        if ($property.Name -eq "image" -or $property.Name -eq "imageID") {
            Add-UsedImageReference -Image $property.Value -LoginServer $LoginServer -UsedTags $UsedTags -UsedDigests $UsedDigests -UsedTagContexts $UsedTagContexts -ContextName $ContextName
        }

        Add-ImageReferencesFromObject -InputObject $property.Value -LoginServer $LoginServer -UsedTags $UsedTags -UsedDigests $UsedDigests -UsedTagContexts $UsedTagContexts -ContextName $ContextName -Depth ($Depth + 1)
    }
}

Assert-CommandExists -Name "az"
Assert-CommandExists -Name "kubectl"

Write-Host "Starting ACR cleanup for registry '$RegistryName'. Delete enabled: $($EnableDelete.IsPresent)."
Write-Host "Resolving login server for registry '$RegistryName'..."

$loginServer = (Invoke-NativeCommand `
    -Command { az acr show --name $RegistryName --query "loginServer" --output tsv } `
    -ErrorMessage "Failed to resolve the login server for registry '$RegistryName'.").Trim()

if ([string]::IsNullOrWhiteSpace($loginServer)) {
    throw "Could not resolve an ACR login server for registry '$RegistryName'."
}

Write-Host "Resolved login server: $loginServer"

$normalizedKubeContexts = Get-NormalizedStringList -Values $KubeContext
$normalizedIncludeRepositoryPrefix = Get-NormalizedStringList -Values $IncludeRepositoryPrefix
$kubernetesNamespacesToScan = Get-KubernetesNamespaceFromRepositoryPrefix -IncludeRepositoryPrefix $normalizedIncludeRepositoryPrefix

if ($normalizedKubeContexts.Count -eq 0) {
    throw "At least one Kubernetes context must be configured."
}

if (-not $SkipAksCredentials) {
    if ([string]::IsNullOrWhiteSpace($AksResourceGroup)) {
        Write-Warning "AksResourceGroup was not provided. Using existing kubectl contexts: $($normalizedKubeContexts -join ', ')."
    }
    else {
        Write-Host "Refreshing AKS credentials for cluster '$AksClusterName' in resource group '$AksResourceGroup'..."
        [void] (Invoke-NativeCommand `
            -Command { az aks get-credentials --resource-group $AksResourceGroup --name $AksClusterName --overwrite-existing } `
            -ErrorMessage "Failed to get AKS credentials for cluster '$AksClusterName'.")
    }
}
else {
    Write-Host "Skipping AKS credential refresh. Using existing kubectl contexts: $($normalizedKubeContexts -join ', ')."
}

$resourceKinds = $KubernetesResourceKind -join ","
$usedTags = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$usedDigests = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
$usedTagContexts = @{}

Write-Host "Reading Kubernetes resources from $($normalizedKubeContexts.Count) context(s): $resourceKinds..."

if ($kubernetesNamespacesToScan.Count -gt 0) {
    Write-Host "Include prefixes configured. Kubernetes scan is limited to namespace(s): $($kubernetesNamespacesToScan -join ', ')."
}
else {
    Write-Host "No include prefixes configured. Kubernetes scan will read all namespaces."
}

foreach ($context in $normalizedKubeContexts) {
    $kubectlArguments = @()
    if (-not [string]::IsNullOrWhiteSpace($context)) {
        $kubectlArguments += @("--context", $context)
    }

    Write-Host "Reading Kubernetes resources from context '$context'..."

    $tagsBeforeContext = $usedTags.Count
    $digestsBeforeContext = $usedDigests.Count
    $resourcesScannedInContext = 0
    $namespacesFoundInContext = 0

    if ($kubernetesNamespacesToScan.Count -gt 0) {
        foreach ($namespace in $kubernetesNamespacesToScan) {
            if (-not (Test-KubernetesNamespaceExists -Namespace $namespace -KubectlArguments $kubectlArguments)) {
                Write-Warning "Namespace '$namespace' was not found in context '$context'. Skipping this namespace in this context."
                continue
            }

            $namespacesFoundInContext++
            Write-Host "Reading Kubernetes resources from context '$context', namespace '$namespace'..."

            $kubernetesResources = Invoke-JsonCommand `
                -Command { kubectl @kubectlArguments --namespace $namespace get $resourceKinds --output json } `
                -ErrorMessage "Failed to read Kubernetes resources from context '$context', namespace '$namespace'."

            $kubernetesResourceCount = @($kubernetesResources.items).Count
            $resourcesScannedInContext += $kubernetesResourceCount

            Write-Host "Scanning $kubernetesResourceCount Kubernetes resource(s) in context '$context', namespace '$namespace' for '$loginServer' image references..."
            Add-ImageReferencesFromObject -InputObject $kubernetesResources -LoginServer $loginServer -UsedTags $usedTags -UsedDigests $usedDigests -UsedTagContexts $usedTagContexts -ContextName $context
        }
    }
    else {
        $kubernetesResources = Invoke-JsonCommand `
            -Command { kubectl @kubectlArguments get $resourceKinds --all-namespaces --output json } `
            -ErrorMessage "Failed to read Kubernetes resources from context '$context'."

        $kubernetesResourceCount = @($kubernetesResources.items).Count
        $resourcesScannedInContext += $kubernetesResourceCount

        Write-Host "Scanning $kubernetesResourceCount Kubernetes resource(s) in context '$context' for '$loginServer' image references..."
        Add-ImageReferencesFromObject -InputObject $kubernetesResources -LoginServer $loginServer -UsedTags $usedTags -UsedDigests $usedDigests -UsedTagContexts $usedTagContexts -ContextName $context
    }

    if ($kubernetesNamespacesToScan.Count -gt 0) {
        Write-Host "Context '$context' scanned $resourcesScannedInContext resource(s) in $namespacesFoundInContext/$($kubernetesNamespacesToScan.Count) requested namespace(s), adding $($usedTags.Count - $tagsBeforeContext) new tag reference(s) and $($usedDigests.Count - $digestsBeforeContext) new digest reference(s)."
    }
    else {
        Write-Host "Context '$context' added $($usedTags.Count - $tagsBeforeContext) new tag reference(s) and $($usedDigests.Count - $digestsBeforeContext) new digest reference(s)."
    }
}

if (($usedTags.Count + $usedDigests.Count) -eq 0) {
    if ($kubernetesNamespacesToScan.Count -gt 0) {
        Write-Warning "No references to '$loginServer' were found in requested namespace(s) '$($kubernetesNamespacesToScan -join ', ')' across Kubernetes contexts: $($normalizedKubeContexts -join ', '). Continuing because include-prefix cleanup is namespace-scoped."
    }
    else {
        throw "No references to '$loginServer' were found in Kubernetes contexts: $($normalizedKubeContexts -join ', '). Refusing to continue because every manifest would be considered unused."
    }
}

Write-Host "Found $($usedTags.Count) unique tag reference(s) and $($usedDigests.Count) unique digest reference(s) across Kubernetes contexts: $($normalizedKubeContexts -join ', ')."
Write-Host "Listing repositories in registry '$RegistryName'..."

$repositories = Invoke-JsonCommand `
    -Command { az acr repository list --name $RegistryName --output json } `
    -ErrorMessage "Failed to list repositories in registry '$RegistryName'."

$normalizedExcludeRepository = Get-NormalizedStringList -Values $ExcludeRepository

if ($normalizedIncludeRepositoryPrefix.Count -gt 0) {
    Write-Host "Only repositories matching these prefixes are eligible for deletion: $($normalizedIncludeRepositoryPrefix -join ', ')"
}
else {
    Write-Host "No repository include prefixes configured. All repositories are eligible before exclusions."
}

$repositoriesMatchingPrefix = @($repositories | Where-Object { Test-RepositoryPrefix -Repository $_ -IncludeRepositoryPrefix $normalizedIncludeRepositoryPrefix })
$repositoriesToProcess = @($repositoriesMatchingPrefix | Where-Object { $normalizedExcludeRepository -notcontains $_ })
$prefixSkippedRepositoryCount = @($repositories).Count - $repositoriesMatchingPrefix.Count
$excludedRepositoryCount = @($repositoriesMatchingPrefix | Where-Object { $normalizedExcludeRepository -contains $_ }).Count
$excludedRepositoriesInScope = @($repositoriesMatchingPrefix | Where-Object { $normalizedExcludeRepository -contains $_ })

Write-Host "Found $(@($repositories).Count) repositories. Prefix filter skipped $prefixSkippedRepositoryCount. Excluding $excludedRepositoryCount. Processing $($repositoriesToProcess.Count)."

if ($excludedRepositoriesInScope.Count -gt 0) {
    Write-Host "Excluded repositories in this cleanup scope: $($excludedRepositoriesInScope -join ', ')"
}

if ($repositoriesToProcess.Count -eq 0 -and $repositoriesMatchingPrefix.Count -gt 0 -and $excludedRepositoryCount -gt 0) {
    Write-Warning "No repositories will be processed because all repositories matching the include prefix are excluded. Adjust -ExcludeRepository if this is not intended."
}

$repositoriesToProcessSet = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
foreach ($repository in $repositoriesToProcess) {
    [void] $repositoriesToProcessSet.Add($repository)
}

$usedTagsForCleanup = Get-FilteredImageReferenceSet -References $usedTags -Repositories $repositoriesToProcessSet
$usedDigestsForCleanup = Get-FilteredImageReferenceSet -References $usedDigests -Repositories $repositoriesToProcessSet

Write-Host "Protecting $($usedTagsForCleanup.Count) tag reference(s) and $($usedDigestsForCleanup.Count) digest reference(s) for repositories in this cleanup scope."
Write-Host "Tag references protected in this cleanup scope:"

if ($usedTagsForCleanup.Count -eq 0) {
    Write-Host "  (none)"
}
else {
    foreach ($tagReference in @($usedTagsForCleanup | Sort-Object)) {
        $contexts = @()

        if ($usedTagContexts.ContainsKey($tagReference)) {
            $contexts = @($usedTagContexts[$tagReference] | Sort-Object)
        }

        if ($contexts.Count -gt 0) {
            Write-Host "  - $tagReference (contexts: $($contexts -join ', '))"
        }
        else {
            Write-Host "  - $tagReference"
        }
    }
}

if ($usedTags.Count -gt $usedTagsForCleanup.Count) {
    Write-Host "Ignoring $($usedTags.Count - $usedTagsForCleanup.Count) tag reference(s) outside the cleanup repository scope."
}

$totalDeleteCandidates = 0
$repositoryIndex = 0

foreach ($repository in $repositoriesToProcess) {
    $repositoryIndex++
    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Processing repository: $repository"
    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Fetching manifest metadata for $repository..."

    $manifests = Invoke-JsonCommand `
        -Command { az acr manifest list-metadata --registry $RegistryName --name $repository --orderby time_asc --output json } `
        -ErrorMessage "Failed to list manifests for repository '$repository'."

    $imagesToDelete = @()
    $protectedByLatestCount = 0
    $protectedByDigestCount = 0
    $protectedByTagCount = 0
    $manifestCount = @($manifests).Count
    $tagPrefix = "$($repository):"
    $digestPrefix = "$repository@"
    $usedTagNamesForRepository = @($usedTagsForCleanup | Where-Object { $_.StartsWith($tagPrefix, [System.StringComparison]::OrdinalIgnoreCase) } | ForEach-Object { $_.Substring($tagPrefix.Length) })
    $usedDigestsForRepository = @($usedDigestsForCleanup | Where-Object { $_.StartsWith($digestPrefix, [System.StringComparison]::OrdinalIgnoreCase) })

    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Kubernetes references for $($repository): $($usedTagNamesForRepository.Count) tag(s), $($usedDigestsForRepository.Count) digest(s)."
    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Evaluating $manifestCount manifest(s) in $repository..."

    foreach ($manifest in @($manifests)) {
        $digest = $manifest.digest
        if ([string]::IsNullOrWhiteSpace($digest)) {
            Write-Warning "Skipping manifest without digest in repository '$repository'."
            continue
        }

        $hasLatestTag = $false
        foreach ($tag in @($manifest.tags)) {
            if (-not [string]::IsNullOrWhiteSpace($tag) -and $tag.Equals("latest", [System.StringComparison]::OrdinalIgnoreCase)) {
                $hasLatestTag = $true
                break
            }
        }

        if ($hasLatestTag) {
            $protectedByLatestCount++
            continue
        }

        $digestKey = "$repository@$($digest.ToLowerInvariant())"
        if ($usedDigestsForCleanup.Contains($digestKey)) {
            $protectedByDigestCount++
            continue
        }

        $hasUsedTag = $false
        foreach ($tag in @($manifest.tags)) {
            if (-not [string]::IsNullOrWhiteSpace($tag) -and $usedTagsForCleanup.Contains("$($repository):$tag")) {
                $hasUsedTag = $true
                $protectedByTagCount++
                break
            }
        }

        if (-not $hasUsedTag) {
            $imagesToDelete += $manifest
        }
    }

    foreach ($image in $imagesToDelete) {
        $imageName = "$repository@$($image.digest)"

        if ($EnableDelete) {
            if ($PSCmdlet.ShouldProcess("$RegistryName/$imageName", "Delete ACR manifest")) {
                [void] (Invoke-NativeCommand `
                    -Command { az acr repository delete --name $RegistryName --image $imageName --yes --output none } `
                    -ErrorMessage "Failed to delete image '$imageName'.")
            }
        }
        else {
            Write-Host "Would delete $imageName"
        }
    }

    $totalDeleteCandidates += $imagesToDelete.Count
    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] $repository summary: $protectedByLatestCount manifest(s) protected by latest tag, $protectedByDigestCount manifest(s) protected by digest, $protectedByTagCount manifest(s) protected by cluster tag reference, $($imagesToDelete.Count) deletion candidate(s)."

    if ($usedTagNamesForRepository.Count -gt 0 -and $protectedByTagCount -eq 0) {
        if ($protectedByDigestCount -gt 0) {
            Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Note: Kubernetes references $($usedTagNamesForRepository.Count) tag(s) in '$repository', but none matched current ACR manifest tags. $protectedByDigestCount manifest(s) were protected by running digest instead."
        }
        else {
            Write-Warning "Kubernetes references $($usedTagNamesForRepository.Count) tag(s) in '$repository', but none matched current ACR manifest tags and no running digest matched. Referenced tag(s): $($usedTagNamesForRepository -join ', ')"
        }
    }

    if ($EnableDelete) {
        Write-Host "Deleted $($imagesToDelete.Count) unused image manifest(s) from repository $repository"
    }
    else {
        Write-Host "Would delete $($imagesToDelete.Count) unused image manifest(s) from repository $repository"
    }
}

if ($EnableDelete) {
    Write-Host "Deleted $totalDeleteCandidates unused image manifest(s) from registry '$RegistryName'."
}
else {
    Write-Host "Dry run complete. Would delete $totalDeleteCandidates unused image manifest(s) from registry '$RegistryName'. Pass -EnableDelete to delete them."
}
