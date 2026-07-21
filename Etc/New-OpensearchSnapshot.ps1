
param( 
    [string] $BaseUri = "http://xxx.miljodirektoratet.no",
    [string] $Repository
)

function ConvertTo-OSPathSegment {
    param(
        [Parameter(Mandatory)]
        [string] $Value
    )

    return [uri]::EscapeDataString($Value)
}

function Invoke-OSApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet("GET", "POST", "PUT", "DELETE")]
        [string] $Method,

        [Parameter(Mandatory)]
        [string] $Path,

        [hashtable] $Query,
        [object] $Body
    )

    $base = $BaseUri.TrimEnd("/")
    $apiPath = if ($Path.StartsWith("/")) { $Path } else { "/$Path" }
    $uriBuilder = [System.UriBuilder]::new("$base$apiPath")

    if ($Query.Count -gt 0) {
        $uriBuilder.Query = ($Query.GetEnumerator() | ForEach-Object {
            "{0}={1}" -f [uri]::EscapeDataString($_.Key), [uri]::EscapeDataString([string]$_.Value)
        }) -join "&"
    }

    $request = @{
        Uri         = $uriBuilder.Uri.AbsoluteUri
        Method      = $Method
        ErrorAction = "Stop"
    }

    if ($null -ne $Body) {
        $request.ContentType = "application/json"
        $request.Body = $Body | ConvertTo-Json -Depth 100
    }

    return Invoke-RestMethod @request
}

function Resolve-OSRepository {
    param(
        [string] $Name
    )

    $resolvedName = if ($Name) { $Name } else { $Repository }
    if (-not $resolvedName) {
        throw "Specify -Repository or set the script's -Repository parameter when dot-sourcing it."
    }

    return $resolvedName
}

function Get-OSRepository {
    [CmdletBinding()]
    param(
        [string] $Name
    )

    $path = if ($Name) {
        "/_snapshot/$(ConvertTo-OSPathSegment $Name)"
    }
    else {
        "/_snapshot/_all"
    }

    $response = Invoke-OSApi -Method GET -Path $path
    foreach ($property in $response.PSObject.Properties) {
        [pscustomobject]@{
            Name     = $property.Name
            Type     = $property.Value.type
            Settings = $property.Value.settings
        }
    }
}

function New-OSRepository {
    [CmdletBinding()]
    param(
        [string] $Name,
        [string] $Container,
        [string] $Client = "default",
        [string] $Type = "azure"
    )

    $repositoryName = Resolve-OSRepository $Name
    $containerName = if ($Container) { $Container } else { $repositoryName }
    $body = @{
        type     = $Type
        settings = @{
            client    = $Client
            container = $containerName
        }
    }

    return Invoke-OSApi -Method PUT -Path "/_snapshot/$(ConvertTo-OSPathSegment $repositoryName)" -Body $body
}

function New-OSRepositorySnapshot {
    [CmdletBinding()]
    param(
        [string] $Name = (Get-Date -Format "yyyyMMdd-HHmmss"),
        [string] $RepositoryName,
        [string[]] $Indices = @("*"),
        [bool] $IgnoreUnavailable = $true,
        [bool] $IncludeGlobalState = $true,
        [switch] $Wait
    )

    $repositoryName = Resolve-OSRepository $RepositoryName
    $body = @{
        indices              = $Indices -join ","
        ignore_unavailable   = $IgnoreUnavailable
        include_global_state = $IncludeGlobalState
    }

    return Invoke-OSApi `
        -Method PUT `
        -Path "/_snapshot/$(ConvertTo-OSPathSegment $repositoryName)/$(ConvertTo-OSPathSegment $Name)" `
        -Query @{ wait_for_completion = $Wait.IsPresent.ToString().ToLowerInvariant() } `
        -Body $body
}

function Get-OSSnapshot {
    [CmdletBinding()]
    param(
        [string] $RepositoryName,
        [string] $Name = "*",
        [string] $Index,
        [string] $State,
        [switch] $Detailed
    )

    $repositoryName = Resolve-OSRepository $RepositoryName
    $response = Invoke-OSApi `
        -Method GET `
        -Path "/_snapshot/$(ConvertTo-OSPathSegment $repositoryName)/_all"

    $snapshots = @($response.snapshots) | Where-Object {
        $_.snapshot -like $Name -and
        (-not $State -or $_.state -eq $State) -and
        (-not $Index -or @($_.indices).Where({ $_ -like $Index }).Count -gt 0)
    } | Sort-Object start_time_in_millis -Descending

    if ($Detailed) {
        return $snapshots
    }

    return $snapshots | ForEach-Object {
        [pscustomobject]@{
            Repository = $repositoryName
            Name       = $_.snapshot
            State      = $_.state
            StartTime  = if ($_.start_time) { [datetime]$_.start_time } else { $null }
            EndTime    = if ($_.end_time) { [datetime]$_.end_time } else { $null }
            Indices    = @($_.indices)
            Shards     = "{0}/{1}" -f $_.shards.successful, $_.shards.total
            Failures   = @($_.failures).Count
        }
    }
}

function Get-OSSnapshotStatus {
    [CmdletBinding()]
    param(
        [string] $RepositoryName,
        [string] $Name = "_all"
    )

    $repositoryName = Resolve-OSRepository $RepositoryName
    $response = Invoke-OSApi `
        -Method GET `
        -Path "/_snapshot/$(ConvertTo-OSPathSegment $repositoryName)/$(ConvertTo-OSPathSegment $Name)/_status"

    return $response.snapshots
}

function Restore-OSSnapshot {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = "High")]
    param(
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("Name")]
        [string] $Snapshot,

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias("Repository")]
        [string] $RepositoryName,

        [string[]] $Indices = @("*"),
        [bool] $IgnoreUnavailable = $true,
        [bool] $IncludeGlobalState = $false,
        [string] $RenamePattern,
        [string] $RenameReplacement,
        [switch] $Wait
    )

    process {
        $repositoryName = Resolve-OSRepository $RepositoryName
        if ([bool]$RenamePattern -ne [bool]$RenameReplacement) {
            throw "Specify both -RenamePattern and -RenameReplacement when renaming restored indices."
        }

        $body = @{
            indices              = $Indices -join ","
            ignore_unavailable   = $IgnoreUnavailable
            include_global_state = $IncludeGlobalState
        }

        if ($RenamePattern) {
            $body.rename_pattern = $RenamePattern
            $body.rename_replacement = $RenameReplacement
        }

        $target = "$repositoryName/$Snapshot"
        if ($PSCmdlet.ShouldProcess($target, "Restore OpenSearch snapshot")) {
            return Invoke-OSApi `
                -Method POST `
                -Path "/_snapshot/$(ConvertTo-OSPathSegment $repositoryName)/$(ConvertTo-OSPathSegment $Snapshot)/_restore" `
                -Query @{ wait_for_completion = $Wait.IsPresent.ToString().ToLowerInvariant() } `
                -Body $body
        }
    }
}

function Get-OSRecovery {
    [CmdletBinding()]
    param(
        [string] $Index = "*",
        [switch] $ActiveOnly
    )

    return Invoke-OSApi `
        -Method GET `
        -Path "/_cat/recovery/$(ConvertTo-OSPathSegment $Index)" `
        -Query @{
            format      = "json"
            active_only = $ActiveOnly.IsPresent.ToString().ToLowerInvariant()
        }
}

function Set-OSSnapshotPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [string] $Description,

        [Parameter(Mandatory)]
        [string] $CronExpression,

        [Parameter(Mandatory)]
        [string] $MaxAge,

        [int] $MinCount = 1,
        [int] $MaxCount = 40,
        [string] $RepositoryName,
        [string] $Indices = "*",
        [string] $TimeZone = "Europe/Oslo"
    )

    $repositoryName = Resolve-OSRepository $RepositoryName
    $body = @{
        description = $Description
        creation = @{
            schedule = @{
                cron = @{
                    expression = $CronExpression
                    timezone   = $TimeZone
                }
            }
            time_limit = "1h"
        }
        deletion = @{
            condition = @{
                max_age   = $MaxAge
                min_count = $MinCount
                max_count = $MaxCount
            }
        }
        snapshot_config = @{
            repository         = $repositoryName
            indices            = $Indices
            ignore_unavailable = $true
            include_global_state = $true
        }
    }

    return Invoke-OSApi -Method POST -Path "/_plugins/_sm/policies/$(ConvertTo-OSPathSegment $Name)" -Body $body
}

function Set-OSNightlySnapshotPolicy {
    [CmdletBinding()]
    param(
        [string] $RepositoryName,
        [string] $TimeZone = "Europe/Oslo"
    )

    return Set-OSSnapshotPolicy `
        -Name "nightly-snapshots" `
        -Description "Nightly snapshots kept for 31 days" `
        -CronExpression "0 2 * * *" `
        -MaxAge "31d" `
        -MinCount 1 `
        -MaxCount 40 `
        -RepositoryName $RepositoryName `
        -TimeZone $TimeZone
}

function Set-OSMonthlySnapshotPolicy {
    [CmdletBinding()]
    param(
        [string] $RepositoryName,
        [string] $TimeZone = "Europe/Oslo"
    )

    return Set-OSSnapshotPolicy `
        -Name "monthly-snapshots" `
        -Description "Monthly snapshots kept for 6 months" `
        -CronExpression "0 2 1 * *" `
        -MaxAge "180d" `
        -MinCount 1 `
        -MaxCount 12 `
        -RepositoryName $RepositoryName `
        -TimeZone $TimeZone
}
