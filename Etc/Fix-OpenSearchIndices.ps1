<#
.SYNOPSIS

# ==========================================================
# OpenSearch bulk shard recovery (stale-first, empty fallback)
# ==========================================================

# Before running this script:
In case of index corruption, try: ./opensearch-shard remove-corrupted-data --index <myindex> --shard-id 0
After this, the ExecuteStale function will need to be invoked.
To remove indices, the Delete-Indices function can be used, but be careful as this will permanently delete data.

# - Finds all UNASSIGNED primary shards
# - Attempts allocate_stale_primary first (accept_data_loss=true required by API)
# - Optionally falls back to allocate_empty_primary
# - Supports dry-run mode by default
#
# IMPORTANT:
# - Stale allocation may still lose recent data
# - Empty allocation resets shard data (definite shard data loss)
# ==========================================================

.EXAMPLE
    # Dry-run mode (no changes, just print planned actions)
    .\Fix-OpenSearchIndices.ps1 -BaseUri "http://localhost:9200" -DryRun
#>

param( 
    [string] $BaseUri = "http://xxx.miljodirektoratet.no",
    [bool] $DryRun = $true,
    [bool] $ExecuteStale = $true,
    [bool] $ExecuteEmptyFallback = $false
)

# ---- Optional filters ----
$OnlyIndex = $null #"metadata_v1"                 # e.g. "metadata_v1" to limit scope; keep $null for all
$MaxShards = 0                     # 0 = no limit, >0 = process first N matching primaries

# ---- Safer in single-node recovery ----
$SetReplicasToZero = $true         # recommended for single-node cluster

# ---------------------------
# Helpers
# ---------------------------
function Invoke-OsApi {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET","POST","PUT","DELETE")] [string]$Method,
        [Parameter(Mandatory = $true)][string]$Path,
        [object]$Body = $null
    )

    # Ensure exactly one slash between base and path
    $base = $BaseUri.TrimEnd('/')
    $p = if ($Path.StartsWith('/')) { $Path } else { "/$Path" }
    $fullUri = "$base$p"

    if ($null -ne $Body) {
        $json = $Body | ConvertTo-Json -Depth 100
        return Invoke-RestMethod -Uri $fullUri -Method $Method -ContentType "application/json" -Body $json
    } else {
        return Invoke-RestMethod -Uri $fullUri -Method $Method
    }
}

function Get-TargetNodeName {
    $nodes = Invoke-OsApi -Method GET -Path "/_cat/nodes?format=json&h=name,roles,node.role"
    if (-not $nodes) { throw "No nodes returned from /_cat/nodes." }

    $normalized = foreach ($n in @($nodes)) {
        $roleString = @($n.roles, $n.'node.role') | Where-Object { $_ -and $_.ToString().Trim() -ne "" } | Select-Object -First 1
        [pscustomobject]@{
            name  = $n.name
            roles = $roleString
        }
    }

    $dataNode = $normalized | Where-Object { $_.roles -match "d" } | Select-Object -First 1
    if ($dataNode) { return $dataNode.name }

    # single-node fallback
    return ($normalized | Select-Object -First 1).name
}

function Set-ReplicasZero {
    $body = @{
        index = @{
            number_of_replicas = 0
        }
    }

    if ($DryRun) {
        Write-Host "[DRY-RUN] PUT /_all/_settings?expand_wildcards=all with number_of_replicas=0" -ForegroundColor Yellow
        return
    }

    Invoke-OsApi -Method PUT -Path "/_all/_settings?expand_wildcards=all&pretty" -Body $body | Out-Null
    Write-Host "[OK] Replicas set to 0 on all indices." -ForegroundColor Green
}

function Get-UnassignedPrimaryShards {
    $shards = Invoke-OsApi -Method GET -Path "/_cat/shards?format=json&h=index,shard,prirep,state,unassigned.reason,node"
    $items = @($shards | Where-Object { $_.prirep -eq "p" -and $_.state -eq "UNASSIGNED" })

    if ($OnlyIndex) {
        $items = @($items | Where-Object { $_.index -eq $OnlyIndex })
    }
    if ($MaxShards -gt 0) {
        $items = @($items | Select-Object -First $MaxShards)
    }
    return $items
}


function Delete-Indices {
    param(
        [string]$Pattern = ".opensearch-observability*"
    )
    return Invoke-OsApi -Method DELETE -Path $Pattern
}

function Explain-Primary {
    param(
        [string]$Index,
        [int]$Shard
    )
    $body = @{
        index   = $Index
        shard   = $Shard
        primary = $true
    }
    return Invoke-OsApi -Method POST -Path "/_cluster/allocation/explain?pretty" -Body $body
}

function Reroute-StalePrimary {
    param(
        [string]$Index,
        [int]$Shard,
        [string]$Node
    )
    $body = @{
        commands = @(
            @{
                allocate_stale_primary = @{
                    index            = $Index
                    shard            = $Shard
                    node             = $Node
                    accept_data_loss = $true
                }
            }
        )
    }
    if ($DryRun -or -not $ExecuteStale) {
        Write-Host "[DRY-RUN] POST /_cluster/reroute?retry_failed=true : allocate_stale_primary $Index/$Shard on $Node" -ForegroundColor Yellow
        return $null
    }
    return Invoke-OsApi -Method POST -Path "/_cluster/reroute?retry_failed=true&pretty" -Body $body
}

function Reroute-EmptyPrimary {
    param(
        [string]$Index,
        [int]$Shard,
        [string]$Node
    )
    $body = @{
        commands = @(
            @{
                allocate_empty_primary = @{
                    index            = $Index
                    shard            = $Shard
                    node             = $Node
                    accept_data_loss = $true
                }
            }
        )
    }
    if ($DryRun -or -not $ExecuteEmptyFallback) {
        Write-Host "[DRY-RUN] POST /_cluster/reroute?retry_failed=true : allocate_empty_primary $Index/$Shard on $Node" -ForegroundColor DarkYellow
        return $null
    }
    return Invoke-OsApi -Method POST -Path "/_cluster/reroute?retry_failed=true&pretty" -Body $body
}

function Get-ShardState {
    param(
        [string]$Index,
        [int]$Shard
    )

    # Query all shards, filter in PowerShell (avoids path/index parsing issues)
    $rows = Invoke-OsApi -Method GET -Path "/_cat/shards?format=json"

    $p = @(
        $rows | Where-Object {
            $_.index -eq $Index -and
            [int]$_.shard -eq $Shard -and
            $_.prirep -eq "p"
        }
    ) | Select-Object -First 1

    return $p
}

# ---------------------------
# Main
# ---------------------------
Write-Host "Base URI: $BaseUri" -ForegroundColor Cyan
Write-Host "Mode: DryRun=$DryRun ExecuteStale=$ExecuteStale ExecuteEmptyFallback=$ExecuteEmptyFallback" -ForegroundColor Cyan
if ($OnlyIndex) { Write-Host "Filter: OnlyIndex=$OnlyIndex" -ForegroundColor Cyan }
if ($MaxShards -gt 0) { Write-Host "Limit: MaxShards=$MaxShards" -ForegroundColor Cyan }

if (-not $DryRun -and -not $ExecuteStale -and -not $ExecuteEmptyFallback) {
    throw "Execution is enabled but no action flags are true. Set ExecuteStale and/or ExecuteEmptyFallback."
}

if ($SetReplicasToZero) {
    Set-ReplicasZero
}

$targetNode = Get-TargetNodeName
if (-not $targetNode) { throw "Could not determine target node." }
Write-Host "Target node: $targetNode" -ForegroundColor Cyan

$primaries = Get-UnassignedPrimaryShards
if ($primaries.Count -eq 0) {
    Write-Host "No unassigned primary shards found." -ForegroundColor Green
    Invoke-OsApi -Method GET -Path "/_cluster/health?pretty"
    return
}

Write-Host "Found $($primaries.Count) unassigned primaries." -ForegroundColor Magenta

$results = New-Object System.Collections.Generic.List[object]

foreach ($s in $primaries) {
    $index = [string]$s.index
    $shard = [int]$s.shard

    Write-Host ""
    Write-Host "=== Processing $index / shard $shard ===" -ForegroundColor White

    $explain = $null
    try {
        $explain = Explain-Primary -Index $index -Shard $shard
        Write-Host "can_allocate: $($explain.can_allocate)" -ForegroundColor DarkCyan
        Write-Host "explain     : $($explain.allocate_explanation)" -ForegroundColor DarkCyan
    }
    catch {
        Write-Host "Explain failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    $staleStatus = "not-run"
    $emptyStatus = "not-run"
    $finalState = "unknown"

    # 1) Try stale first
    try {
        Reroute-StalePrimary -Index $index -Shard $shard -Node $targetNode
        $staleStatus = if ($DryRun -or -not $ExecuteStale) { "planned" } else { "requested" }
    }
    catch {
        $staleStatus = "failed-request"
        Write-Host "stale reroute request failed: $($_.Exception.Message)" -ForegroundColor Red
    }

    Start-Sleep -Seconds 1
    try {
        $stateAfterStale = Get-ShardState -Index $index -Shard $shard
        if ($stateAfterStale) {
            $finalState = $stateAfterStale.state
            Write-Host "state after stale attempt: $finalState" -ForegroundColor Gray
        }
    }
    catch {
        Write-Host "state check after stale failed: $($_.Exception.Message)" -ForegroundColor DarkRed
    }

    # 2) Fallback to empty if still unassigned
    if ($finalState -eq "UNASSIGNED" -or $finalState -eq "unknown") {
        try {
            #Reroute-EmptyPrimary -Index $index -Shard $shard -Node $targetNode | Out-Null
            $emptyStatus = if ($DryRun -or -not $ExecuteEmptyFallback) { "planned" } else { "requested" }
        }
        catch {
            $emptyStatus = "failed-request"
            Write-Host "empty reroute request failed: $($_.Exception.Message)" -ForegroundColor Red
        }

        Start-Sleep -Seconds 1
        try {
            $stateAfterEmpty = Get-ShardState -Index $index -Shard $shard
            if ($stateAfterEmpty) {
                $finalState = $stateAfterEmpty.state
                Write-Host "state after empty attempt: $finalState" -ForegroundColor Gray
            }
        }
        catch {
            Write-Host "state check after empty failed: $($_.Exception.Message)" -ForegroundColor DarkRed
        }
    }

    $results.Add([pscustomobject]@{
        index       = $index
        shard       = $shard
        stale       = $staleStatus
        empty       = $emptyStatus
        final_state = $finalState
    })
}

Write-Host ""
Write-Host "=== Summary ===" -ForegroundColor Cyan
$results | Sort-Object index, shard | Format-Table -AutoSize

Write-Host ""
Write-Host "=== Cluster health ===" -ForegroundColor Cyan
Invoke-OsApi -Method GET -Path "/_cluster/health?pretty"

Write-Host ""
Write-Host "=== Remaining unassigned shards ===" -ForegroundColor Cyan
$remaining = Invoke-OsApi -Method GET -Path "/_cat/shards?format=json&h=index,shard,prirep,state,unassigned.reason,node" |
    Where-Object { $_.state -eq "UNASSIGNED" }

if ($remaining) {
    $remaining | Format-Table -AutoSize
} else {
    Write-Host "None." -ForegroundColor Green
}