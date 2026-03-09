
param( 
    [string] $BaseUri = "http://xxx.miljodirektoratet.no",
    [string] $Repository
)


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

function New-OSRepository {
$body = @{
  type     = "azure"
  settings = @{
    client    = "default"
    container = "$($Repository)"
  }
}
    return Invoke-OsApi -Method POST -Path "/_snapshot/$($Repository)/" -Body $body
}

function New-OSRepositorySnapshot {
$body = @{
  indices     = "metadata_v1"
    ignore_unavailable = $true
    include_global_state = $true
}
    return Invoke-OsApi -Method POST -Path "/_snapshot/$($Repository)/060326" -Body $body
}

function Get-Snapshot {
    return Invoke-OsApi -Method GET -Path "/_snapshot/$($Repository)/_all"
}

function Set-OSSnapshotPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Description,
        [Parameter(Mandatory = $true)][string]$CronExpression,
        [Parameter(Mandatory = $true)][string]$MaxAge,
        [int]$MinCount = 1,
        [int]$MaxCount = 40,
        [string]$Repository = "$($Repository)",
        [string]$Indices = "*",
        # Europe/Oslo follows Norwegian standard time and DST automatically.
        [string]$TimeZone = "Europe/Oslo"
    )

    $body = @{
        description = $Description
        creation = @{
            schedule = @{
                cron = @{
                    expression = $CronExpression
                    timezone = $TimeZone
                }
            }
            time_limit = "1h"
        }
        deletion = @{
            condition = @{
                max_age = $MaxAge
                min_count = $MinCount
                max_count = $MaxCount
            }
        }
        snapshot_config = @{
            repository = $Repository
            indices = $Indices
            ignore_unavailable = $true
            include_global_state = $true
        }
    }

    return Invoke-OsApi -Method POST "/_plugins/_sm/policies/$Name" -Body $body
}

function Set-OSNightlySnapshotPolicy {
    param(
        [string]$Repository = "$($Repository)",
        [string]$TimeZone = "Europe/Oslo"
    )

    return Set-OSSnapshotPolicy `
        -Name "nightly-snapshots" `
        -Description "Nightly snapshots kept for 31 days" `
        -CronExpression "0 2 * * *" `
        -MaxAge "31d" `
        -MinCount 1 `
        -MaxCount 40 `
        -Repository $Repository `
        -TimeZone $TimeZone
}

function Set-OSMonthlySnapshotPolicy {
    param(
        [string]$Repository = "$($Repository)",
        [string]$TimeZone = "Europe/Oslo"
    )

    return Set-OSSnapshotPolicy `
        -Name "monthly-snapshots" `
        -Description "Monthly snapshots kept for 6 months" `
        -CronExpression "0 2 1 * *" `
        -MaxAge "180d" `
        -MinCount 1 `
        -MaxCount 12 `
        -Repository $Repository `
        -TimeZone $TimeZone
}