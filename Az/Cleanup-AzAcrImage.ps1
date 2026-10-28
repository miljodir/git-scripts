#requires -Version 7.0
<#
.SYNOPSIS
Deletes ACR manifests that are not used by the configured AKS clusters.

.DESCRIPTION
The script reads image references from pods and workload specs in the selected
Kubernetes contexts, protects matching ACR tags and digests, always protects
manifests tagged latest, and makes every other manifest eligible for deletion.
Repositories are only cleaned when their owning Kubernetes namespace exists in
at least one configured context, unless a repository-to-namespace mapping exists.
Deletion is disabled by default; pass -EnableDelete to actually remove
manifests.

For performance, kubectl reads run concurrently, and manifest listing and
deletion call the ACR data-plane REST API directly over a pooled HTTP client
instead of starting one az process per repository or manifest. Azure CLI is
only used to resolve the registry and to get a single Entra ID token, which is
exchanged for short-lived, repository-scoped ACR tokens. Throttled (429) and
transient failures are retried with backoff.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -RegistryName myacr -AksResourceGroup my-rg

Dry-runs cleanup for myacr after refreshing the configured AKS credentials.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -RegistryName myacr -AksResourceGroup my-rg -EnableDelete

Deletes manifests from myacr that are not referenced by the configured
Kubernetes contexts.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -SkipAksCredentials -EnableDelete -DeleteThrottleLimit 12

Deletes unused manifests with up to 12 concurrent delete requests.

.EXAMPLE
.\Cleanup-AzAcrImage.ps1 -SkipAksCredentials -IncludeRepositoryPrefix avdekl,testteam1

Optionally limits cleanup to repositories below the avdekl/ and testteam1/
prefixes, and only scans those Kubernetes namespaces in each configured context.

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
    [ValidateRange(1, 64)]
    [int] $DeleteThrottleLimit = 8,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 64)]
    [int] $ListThrottleLimit = 16,

    [Parameter(Mandatory = $false)]
    [switch] $SkipAksCredentials,

    # Overrides the registry data-plane base URI. Used by tests.
    [Parameter(Mandatory = $false, DontShow = $true)]
    [string] $RegistryEndpoint
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

function Start-NativeProcess {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FilePath,

        [Parameter(Mandatory = $true)]
        [string[]] $ArgumentList
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $FilePath
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [System.Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [System.Text.Encoding]::UTF8

    foreach ($argument in $ArgumentList) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [System.Diagnostics.Process]::Start($startInfo)

    return [pscustomobject]@{
        Process        = $process
        StandardOutput = $process.StandardOutput.ReadToEndAsync()
        StandardError  = $process.StandardError.ReadToEndAsync()
        Exited         = $process.WaitForExitAsync()
    }
}

function Invoke-NativeCommandBatch {
    <#
    Runs native commands concurrently and returns a hashtable of Key -> standard output.
    Each command is an object with Key, FilePath, ArgumentList and ErrorMessage properties.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Commands,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 64)]
        [int] $ThrottleLimit
    )

    $results = @{}
    $pending = [System.Collections.Generic.Queue[object]]::new()
    $running = [System.Collections.Generic.List[object]]::new()

    foreach ($command in $Commands) {
        $pending.Enqueue($command)
    }

    try {
        while ($pending.Count -gt 0 -or $running.Count -gt 0) {
            while ($running.Count -lt $ThrottleLimit -and $pending.Count -gt 0) {
                $command = $pending.Dequeue()
                $running.Add([pscustomobject]@{
                    Command = $command
                    Started = Start-NativeProcess -FilePath $command.FilePath -ArgumentList $command.ArgumentList
                })
            }

            $tasks = [System.Threading.Tasks.Task[]]::new($running.Count)
            for ($index = 0; $index -lt $running.Count; $index++) {
                $tasks[$index] = $running[$index].Started.Exited
            }

            # A timeout keeps the loop responsive to Ctrl+C.
            $completedIndex = [System.Threading.Tasks.Task]::WaitAny($tasks, 500)
            if ($completedIndex -lt 0) {
                continue
            }

            $entry = $running[$completedIndex]
            $running.RemoveAt($completedIndex)

            $standardOutput = $entry.Started.StandardOutput.GetAwaiter().GetResult()
            $standardError = $entry.Started.StandardError.GetAwaiter().GetResult()
            $exitCode = $entry.Started.Process.ExitCode
            $entry.Started.Process.Dispose()

            if ($exitCode -ne 0) {
                throw "$($entry.Command.ErrorMessage) Exit code: $exitCode. $($standardError.Trim())"
            }

            if (-not [string]::IsNullOrWhiteSpace($standardError)) {
                Write-Warning "$($entry.Command.Key): $($standardError.Trim())"
            }

            $results[$entry.Command.Key] = $standardOutput
        }
    }
    finally {
        foreach ($entry in $running) {
            if (-not $entry.Started.Process.HasExited) {
                $entry.Started.Process.Kill($true)
            }

            $entry.Started.Process.Dispose()
        }
    }

    return $results
}

function ConvertFrom-JsonText {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return $null
    }

    return ConvertFrom-Json -InputObject $Json -ErrorAction Stop
}

function ConvertFrom-JwtExpiry {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Token
    )

    try {
        $payload = $Token.Split(".")[1].Replace("-", "+").Replace("_", "/")
        switch ($payload.Length % 4) {
            2 { $payload += "==" }
            3 { $payload += "=" }
        }

        $claims = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payload)) | ConvertFrom-Json
        if ($claims.exp) {
            return [DateTimeOffset]::FromUnixTimeSeconds([long] $claims.exp)
        }
    }
    catch {
        Write-Verbose "Could not read token expiry: $($_.Exception.Message)"
    }

    return [DateTimeOffset]::UtcNow.AddMinutes(10)
}

function New-AcrClient {
    param(
        [Parameter(Mandatory = $true)]
        [string] $LoginServer,

        [Parameter(Mandatory = $true)]
        [string] $Endpoint,

        [Parameter(Mandatory = $true)]
        [int] $MaxConnections
    )

    $handler = [System.Net.Http.SocketsHttpHandler]::new()
    $handler.MaxConnectionsPerServer = $MaxConnections
    $handler.PooledConnectionLifetime = [TimeSpan]::FromMinutes(5)
    $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::All

    $httpClient = [System.Net.Http.HttpClient]::new($handler)
    $httpClient.Timeout = [TimeSpan]::FromSeconds(100)

    return [pscustomobject]@{
        LoginServer           = $LoginServer
        Endpoint              = $Endpoint.TrimEnd("/")
        HttpClient            = $httpClient
        RefreshToken          = $null
        RefreshTokenExpiresOn = [DateTimeOffset]::MinValue
        AccessTokens          = @{}
    }
}

function New-AcrFormRequest {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary] $Form
    )

    $pairs = [System.Collections.Generic.List[System.Collections.Generic.KeyValuePair[string, string]]]::new()
    foreach ($key in $Form.Keys) {
        $pairs.Add([System.Collections.Generic.KeyValuePair[string, string]]::new($key, [string] $Form[$key]))
    }

    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::Post, "$($Client.Endpoint)$Path")
    $request.Content = [System.Net.Http.FormUrlEncodedContent]::new($pairs)
    return $request
}

function Update-AcrRefreshToken {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client
    )

    Write-Host "Exchanging an Entra ID token for an ACR refresh token for '$($Client.LoginServer)'..."

    $aadToken = Invoke-JsonCommand `
        -Command { az account get-access-token --resource "https://containerregistry.azure.net" --output json } `
        -ErrorMessage "Failed to get an Entra ID access token for Azure Container Registry."

    if (-not $aadToken -or [string]::IsNullOrWhiteSpace($aadToken.accessToken)) {
        throw "Azure CLI did not return an access token for Azure Container Registry."
    }

    $form = [ordered]@{
        grant_type   = "access_token"
        service      = $Client.LoginServer
        access_token = $aadToken.accessToken
    }

    if (-not [string]::IsNullOrWhiteSpace($aadToken.tenant)) {
        $form.tenant = $aadToken.tenant
    }

    $request = New-AcrFormRequest -Client $Client -Path "/oauth2/exchange" -Form $form
    try {
        $response = $Client.HttpClient.SendAsync($request).GetAwaiter().GetResult()
        try {
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if (-not $response.IsSuccessStatusCode) {
                throw "Failed to exchange the Entra ID token for an ACR refresh token. HTTP $([int] $response.StatusCode): $body"
            }

            $refreshToken = (ConvertFrom-JsonText -Json $body).refresh_token
        }
        finally {
            $response.Dispose()
        }
    }
    finally {
        $request.Dispose()
    }

    if ([string]::IsNullOrWhiteSpace($refreshToken)) {
        throw "The ACR token exchange did not return a refresh token."
    }

    $Client.RefreshToken = $refreshToken
    $Client.RefreshTokenExpiresOn = ConvertFrom-JwtExpiry -Token $refreshToken
    $Client.AccessTokens.Clear()
}

function Get-AcrCachedAccessToken {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client,

        [Parameter(Mandatory = $true)]
        [string] $Scope
    )

    $cachedToken = $Client.AccessTokens[$Scope]
    if ($null -ne $cachedToken -and $cachedToken.ExpiresOn -gt [DateTimeOffset]::UtcNow.AddMinutes(2)) {
        return $cachedToken.Token
    }

    return $null
}

function Start-AcrAccessTokenRequest {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client,

        [Parameter(Mandatory = $true)]
        [string] $Scope
    )

    if ($Client.RefreshTokenExpiresOn -le [DateTimeOffset]::UtcNow.AddMinutes(5)) {
        Update-AcrRefreshToken -Client $Client
    }

    $request = New-AcrFormRequest -Client $Client -Path "/oauth2/token" -Form ([ordered]@{
        grant_type    = "refresh_token"
        service       = $Client.LoginServer
        scope         = $Scope
        refresh_token = $Client.RefreshToken
    })

    return [pscustomobject]@{
        Kind    = "Token"
        Scope   = $Scope
        Request = $request
        Task    = $Client.HttpClient.SendAsync($request)
    }
}

function New-AcrOperation {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Method,

        [Parameter(Mandatory = $true)]
        [string] $Path,

        [Parameter(Mandatory = $true)]
        [string] $Scope,

        [Parameter(Mandatory = $true)]
        [string] $Repository,

        [Parameter(Mandatory = $false)]
        [string] $Label,

        [Parameter(Mandatory = $false)]
        [int[]] $AcceptedStatusCodes = @()
    )

    return [pscustomobject]@{
        Method              = $Method
        Path                = $Path
        Scope               = $Scope
        Repository          = $Repository
        Label               = $Label
        AcceptedStatusCodes = $AcceptedStatusCodes
        Attempts            = 0
        AuthRetries         = 0
        NotBefore           = [DateTimeOffset]::MinValue
    }
}

function Get-RetryAfterDelay {
    param(
        [Parameter(Mandatory = $false)]
        [AllowNull()]
        [System.Net.Http.HttpResponseMessage] $Response
    )

    if ($null -eq $Response -or $null -eq $Response.Headers.RetryAfter) {
        return $null
    }

    if ($null -ne $Response.Headers.RetryAfter.Delta) {
        return $Response.Headers.RetryAfter.Delta.Value
    }

    if ($null -ne $Response.Headers.RetryAfter.Date) {
        return $Response.Headers.RetryAfter.Date.Value - [DateTimeOffset]::UtcNow
    }

    return $null
}

function Get-NextLinkPath {
    param(
        [Parameter(Mandatory = $true)]
        [System.Net.Http.HttpResponseMessage] $Response
    )

    $values = $null
    if (-not $Response.Headers.TryGetValues("Link", [ref] $values)) {
        return $null
    }

    foreach ($value in $values) {
        if ($value -match '<([^>]+)>\s*;\s*rel="?next"?') {
            $link = $Matches[1]
            if ($link -match "^https?://") {
                return ([uri] $link).PathAndQuery
            }

            return $link
        }
    }

    return $null
}

function Invoke-AcrRequestQueue {
    <#
    Sends ACR data-plane requests with at most ThrottleLimit requests in flight.
    Repository-scoped ACR access tokens are requested on demand and cached.
    Throttled (429), transient (5xx, network) and expired-token (401) responses are retried.
    OnSuccess receives (operation, statusCode, body, response) and may return follow-up operations.
    Returns the list of operations that failed permanently.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]] $Operations,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 64)]
        [int] $ThrottleLimit,

        [Parameter(Mandatory = $true)]
        [scriptblock] $OnSuccess,

        [Parameter(Mandatory = $false)]
        [int] $MaxAttempts = 8
    )

    $transientStatusCodes = @(0, 408, 429, 500, 502, 503, 504)
    $ready = [System.Collections.Generic.Queue[object]]::new()
    $delayed = [System.Collections.Generic.List[object]]::new()
    $inFlight = [System.Collections.Generic.List[object]]::new()
    $waitingForToken = @{}
    $failures = [System.Collections.Generic.List[object]]::new()

    foreach ($operation in $Operations) {
        $ready.Enqueue($operation)
    }

    $registerFailure = {
        param($FailedOperation, [int] $StatusCode, [string] $Message, $RetryAfter)

        if ($StatusCode -eq 401 -and $FailedOperation.AuthRetries -lt 1) {
            $FailedOperation.AuthRetries++
            $ready.Enqueue($FailedOperation)
            return
        }

        $FailedOperation.Attempts++
        if ($transientStatusCodes -contains $StatusCode -and $FailedOperation.Attempts -lt $MaxAttempts) {
            $delay = if ($null -ne $RetryAfter -and $RetryAfter -gt [TimeSpan]::Zero) {
                $RetryAfter
            }
            else {
                [TimeSpan]::FromSeconds([Math]::Min(60, [Math]::Pow(2, $FailedOperation.Attempts)))
            }

            $delay = $delay + [TimeSpan]::FromMilliseconds((Get-Random -Minimum 0 -Maximum 1000))
            $FailedOperation.NotBefore = [DateTimeOffset]::UtcNow + $delay
            Write-Verbose "Retrying $($FailedOperation.Method) $($FailedOperation.Path) in $([int] $delay.TotalSeconds)s (attempt $($FailedOperation.Attempts)/$MaxAttempts): $Message"
            $delayed.Add($FailedOperation)
            return
        }

        $failures.Add([pscustomobject]@{
            Operation  = $FailedOperation
            StatusCode = $StatusCode
            Message    = $Message
        })
    }

    try {
        while ($ready.Count -gt 0 -or $delayed.Count -gt 0 -or $inFlight.Count -gt 0) {
            $now = [DateTimeOffset]::UtcNow
            for ($index = $delayed.Count - 1; $index -ge 0; $index--) {
                if ($delayed[$index].NotBefore -le $now) {
                    $ready.Enqueue($delayed[$index])
                    $delayed.RemoveAt($index)
                }
            }

            while ($inFlight.Count -lt $ThrottleLimit -and $ready.Count -gt 0) {
                $operation = $ready.Dequeue()
                $token = Get-AcrCachedAccessToken -Client $Client -Scope $operation.Scope

                if ($token) {
                    $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($operation.Method), "$($Client.Endpoint)$($operation.Path)")
                    $request.Headers.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $token)
                    $inFlight.Add([pscustomobject]@{
                        Kind      = "Operation"
                        Operation = $operation
                        Request   = $request
                        Task      = $Client.HttpClient.SendAsync($request)
                    })
                    continue
                }

                if (-not $waitingForToken.ContainsKey($operation.Scope)) {
                    $waitingForToken[$operation.Scope] = [System.Collections.Generic.List[object]]::new()
                    $inFlight.Add((Start-AcrAccessTokenRequest -Client $Client -Scope $operation.Scope))
                }

                $waitingForToken[$operation.Scope].Add($operation)
            }

            if ($inFlight.Count -eq 0) {
                if ($delayed.Count -gt 0) {
                    $earliest = $delayed[0].NotBefore
                    foreach ($delayedOperation in $delayed) {
                        if ($delayedOperation.NotBefore -lt $earliest) {
                            $earliest = $delayedOperation.NotBefore
                        }
                    }

                    $sleepMilliseconds = [Math]::Max(10, [Math]::Min(1000, ($earliest - [DateTimeOffset]::UtcNow).TotalMilliseconds))
                    Start-Sleep -Milliseconds ([int] $sleepMilliseconds)
                }

                continue
            }

            $tasks = [System.Threading.Tasks.Task[]]::new($inFlight.Count)
            for ($index = 0; $index -lt $inFlight.Count; $index++) {
                $tasks[$index] = $inFlight[$index].Task
            }

            # A timeout keeps the loop responsive to Ctrl+C and lets delayed retries mature.
            $completedIndex = [System.Threading.Tasks.Task]::WaitAny($tasks, 250)
            if ($completedIndex -lt 0) {
                continue
            }

            $entry = $inFlight[$completedIndex]
            $inFlight.RemoveAt($completedIndex)

            $response = $null
            $statusCode = 0
            $body = $null
            $message = $null

            try {
                $response = $entry.Task.GetAwaiter().GetResult()
                $statusCode = [int] $response.StatusCode
                $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            }
            catch {
                $message = $_.Exception.Message
            }
            finally {
                $entry.Request.Dispose()
            }

            try {
                if (-not $message) {
                    $message = "HTTP $statusCode"
                    if (-not [string]::IsNullOrWhiteSpace($body)) {
                        $message += ": $($body.Substring(0, [Math]::Min(500, $body.Length)))"
                    }
                }

                $retryAfter = Get-RetryAfterDelay -Response $response

                if ($entry.Kind -eq "Token") {
                    $waitingOperations = $waitingForToken[$entry.Scope]
                    $waitingForToken.Remove($entry.Scope)

                    $accessToken = $null
                    if ($statusCode -eq 200) {
                        $accessToken = (ConvertFrom-JsonText -Json $body).access_token
                    }

                    if (-not [string]::IsNullOrWhiteSpace($accessToken)) {
                        $Client.AccessTokens[$entry.Scope] = [pscustomobject]@{
                            Token     = $accessToken
                            ExpiresOn = ConvertFrom-JwtExpiry -Token $accessToken
                        }

                        foreach ($waitingOperation in $waitingOperations) {
                            $ready.Enqueue($waitingOperation)
                        }
                    }
                    else {
                        if ($statusCode -eq 401) {
                            $Client.RefreshTokenExpiresOn = [DateTimeOffset]::MinValue
                        }

                        foreach ($waitingOperation in $waitingOperations) {
                            & $registerFailure $waitingOperation $statusCode "ACR token request for scope '$($entry.Scope)' failed: $message" $retryAfter
                        }
                    }

                    continue
                }

                $operation = $entry.Operation
                if (($statusCode -ge 200 -and $statusCode -lt 300) -or $operation.AcceptedStatusCodes -contains $statusCode) {
                    foreach ($followUp in @(& $OnSuccess $operation $statusCode $body $response)) {
                        if ($null -ne $followUp) {
                            $ready.Enqueue($followUp)
                        }
                    }

                    continue
                }

                if ($statusCode -eq 401) {
                    $Client.AccessTokens.Remove($operation.Scope)
                }

                & $registerFailure $operation $statusCode $message $retryAfter
            }
            finally {
                if ($null -ne $response) {
                    $response.Dispose()
                }
            }
        }
    }
    finally {
        foreach ($entry in $inFlight) {
            $entry.Request.Dispose()
        }
    }

    return , $failures
}

function Get-AcrManifestMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $Repositories,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 64)]
        [int] $ThrottleLimit
    )

    $manifestsByRepository = @{}
    $listProgress = [pscustomobject]@{ Completed = 0; Total = $Repositories.Count }
    $listOperations = foreach ($repository in $Repositories) {
        $manifestsByRepository[$repository] = [System.Collections.Generic.List[object]]::new()
        New-AcrOperation -Method "GET" -Path "/acr/v1/$repository/_manifests?n=1000&orderby=timeasc" -Scope "repository:$($repository):metadata_read" -Repository $repository -AcceptedStatusCodes @(404)
    }

    Write-Host "Fetching manifest metadata for $($Repositories.Count) repositories with up to $ThrottleLimit concurrent request(s)..."

    $listFailures = Invoke-AcrRequestQueue -Client $Client -Operations @($listOperations) -ThrottleLimit $ThrottleLimit -OnSuccess {
        param($Operation, $StatusCode, $Body, $Response)

        if ($StatusCode -eq 404) {
            Write-Warning "Repository '$($Operation.Repository)' was not found while listing manifests. Treating it as empty."
        }
        else {
            $page = ConvertFrom-JsonText -Json $Body
            foreach ($manifest in @($page.manifests)) {
                if ($null -ne $manifest) {
                    $manifestsByRepository[$Operation.Repository].Add($manifest)
                }
            }

            $nextPath = Get-NextLinkPath -Response $Response
            if ($nextPath) {
                return New-AcrOperation -Method "GET" -Path $nextPath -Scope $Operation.Scope -Repository $Operation.Repository -AcceptedStatusCodes @(404)
            }
        }

        $listProgress.Completed++
        Write-Host "[$($listProgress.Completed)/$($listProgress.Total)] Fetched $($manifestsByRepository[$Operation.Repository].Count) manifest(s) for $($Operation.Repository)."
    }

    if ($listFailures.Count -gt 0) {
        foreach ($failure in $listFailures) {
            Write-Error "Failed to list manifests for repository '$($failure.Operation.Repository)': $($failure.Message)"
        }

        throw "Failed to list manifests for $(@($listFailures | ForEach-Object { $_.Operation.Repository } | Sort-Object -Unique).Count) repositories."
    }

    return $manifestsByRepository
}

function Remove-AcrManifest {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Client,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $ImageNames,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 64)]
        [int] $ThrottleLimit
    )

    if ($ImageNames.Count -eq 0) {
        return 0
    }

    Write-Host "Deleting $($ImageNames.Count) manifest(s) with up to $ThrottleLimit concurrent delete request(s)..."

    $deleteProgress = [pscustomobject]@{ Completed = 0; Total = $ImageNames.Count }
    $deleteOperations = foreach ($imageName in $ImageNames) {
        $repository, $digest = $imageName -split "@", 2
        New-AcrOperation -Method "DELETE" -Path "/v2/$repository/manifests/$digest" -Scope "repository:$($repository):delete" -Repository $repository -Label $imageName -AcceptedStatusCodes @(404)
    }

    $deleteFailures = Invoke-AcrRequestQueue -Client $Client -Operations @($deleteOperations) -ThrottleLimit $ThrottleLimit -OnSuccess {
        param($Operation, $StatusCode, $Body, $Response)

        $deleteProgress.Completed++
        if ($StatusCode -eq 404) {
            Write-Warning "Manifest $($Operation.Label) was already deleted."
        }

        Write-Host "Deleted $($deleteProgress.Completed)/$($deleteProgress.Total): $($Operation.Label)"
    }

    if ($deleteFailures.Count -gt 0) {
        foreach ($failedDelete in $deleteFailures) {
            Write-Error "Failed to delete $($failedDelete.Operation.Label): $($failedDelete.Message)"
        }

        throw "Failed to delete $($deleteFailures.Count) of $($ImageNames.Count) manifest(s)."
    }

    return $ImageNames.Count
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

    foreach ($normalizedValue in $normalizedValues) {
        $normalizedValue
    }
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

    return ,$filteredReferences
}

function Get-KubernetesNamespaceFromRepositoryPrefix {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [string[]] $IncludeRepositoryPrefix = @(),

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]] $RepositoryNamespaceMapping = @()
    )

    $namespaces = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($prefix in @($IncludeRepositoryPrefix)) {
        $mapping = Get-RepositoryNamespaceInfo -Repository $prefix -RepositoryNamespaceMapping $RepositoryNamespaceMapping
        $namespace = $mapping.Namespace

        if (-not [string]::IsNullOrWhiteSpace($namespace)) {
            [void] $namespaces.Add($namespace)
        }
    }

    foreach ($namespace in $namespaces) {
        $namespace
    }
}

function Get-RepositoryNamespaceInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Repository,

        [Parameter(Mandatory = $false)]
        [AllowEmptyCollection()]
        [object[]] $RepositoryNamespaceMapping = @()
    )

    foreach ($mapping in @($RepositoryNamespaceMapping)) {
        if (Test-RepositoryPrefix -Repository $Repository -IncludeRepositoryPrefix @($mapping.RepositoryPrefix)) {
            return [pscustomobject]@{
                RepositoryPrefix = $mapping.RepositoryPrefix
                Namespace        = $mapping.Namespace
                KubeContext      = @($mapping.KubeContext)
                IsMapped         = $true
            }
        }
    }

    return [pscustomobject]@{
        RepositoryPrefix = @($Repository -split "/")[0]
        Namespace        = @($Repository -split "/")[0]
        KubeContext      = @()
        IsMapped         = $false
    }
}

function Get-AvailableNamespaceContexts {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Namespace,

        [Parameter(Mandatory = $true)]
        [hashtable] $NamespacesByContext,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]] $KubeContext
    )

    foreach ($context in @($KubeContext)) {
        if ($NamespacesByContext.ContainsKey($context) -and $NamespacesByContext[$context].Contains($Namespace)) {
            $context
        }
    }
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

if (-not ("AcrCleanup.KubernetesImageScanner" -as [type])) {
    # Scanning large kubectl JSON documents node by node in PowerShell takes minutes; this helper takes milliseconds.
    Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Text.Json;

namespace AcrCleanup
{
    public sealed class KubernetesImageScanResult
    {
        public string[] Images { get; set; }
        public int ItemCount { get; set; }
        public int SkippedDeepNodeCount { get; set; }
    }

    public static class KubernetesImageScanner
    {
        public static KubernetesImageScanResult Scan(string json, int maxDepth)
        {
            var images = new HashSet<string>(StringComparer.Ordinal);
            var result = new KubernetesImageScanResult();

            if (string.IsNullOrWhiteSpace(json))
            {
                result.Images = new string[0];
                return result;
            }

            using (var document = JsonDocument.Parse(json, new JsonDocumentOptions { MaxDepth = 4096 }))
            {
                var root = document.RootElement;
                if (root.ValueKind == JsonValueKind.Object)
                {
                    JsonElement items;
                    if (root.TryGetProperty("items", out items) && items.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in items.EnumerateArray())
                        {
                            if (item.ValueKind != JsonValueKind.Null)
                            {
                                result.ItemCount++;
                            }
                        }
                    }
                }

                var stack = new Stack<KeyValuePair<JsonElement, int>>();
                stack.Push(new KeyValuePair<JsonElement, int>(root, 0));

                while (stack.Count > 0)
                {
                    var entry = stack.Pop();
                    var node = entry.Key;
                    var depth = entry.Value;

                    if (node.ValueKind != JsonValueKind.Object && node.ValueKind != JsonValueKind.Array)
                    {
                        continue;
                    }

                    if (depth > maxDepth)
                    {
                        result.SkippedDeepNodeCount++;
                        continue;
                    }

                    if (node.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var child in node.EnumerateArray())
                        {
                            stack.Push(new KeyValuePair<JsonElement, int>(child, depth + 1));
                        }

                        continue;
                    }

                    foreach (var property in node.EnumerateObject())
                    {
                        var name = property.Name;
                        if (name.Equals("metadata", StringComparison.OrdinalIgnoreCase) ||
                            name.Equals("apiVersion", StringComparison.OrdinalIgnoreCase) ||
                            name.Equals("kind", StringComparison.OrdinalIgnoreCase))
                        {
                            continue;
                        }

                        var value = property.Value;
                        if (value.ValueKind == JsonValueKind.String)
                        {
                            if (name.Equals("image", StringComparison.OrdinalIgnoreCase) ||
                                name.Equals("imageID", StringComparison.OrdinalIgnoreCase))
                            {
                                images.Add(value.GetString());
                            }
                        }
                        else
                        {
                            stack.Push(new KeyValuePair<JsonElement, int>(value, depth + 1));
                        }
                    }
                }
            }

            var imageArray = new string[images.Count];
            images.CopyTo(imageArray);
            result.Images = imageArray;
            return result;
        }
    }
}
"@
}

function Add-ImageReferencesFromJson {
    <#
    Collects image and imageID values from kubectl JSON output. Like the previous object walk,
    metadata, apiVersion and kind properties are skipped and nesting deeper than 50 levels is ignored.
    Returns the number of Kubernetes resources in the document.
    #>
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [AllowNull()]
        [string] $Json,

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

    $scanResult = [AcrCleanup.KubernetesImageScanner]::Scan($Json, 50)

    if ($scanResult.SkippedDeepNodeCount -gt 0) {
        Write-Warning "Skipped $($scanResult.SkippedDeepNodeCount) Kubernetes object node(s) nested deeper than 50 levels while scanning for image references."
    }

    foreach ($image in $scanResult.Images) {
        Add-UsedImageReference -Image $image -LoginServer $LoginServer -UsedTags $UsedTags -UsedDigests $UsedDigests -UsedTagContexts $UsedTagContexts -ContextName $ContextName
    }

    return $scanResult.ItemCount
}


Assert-CommandExists -Name "az"
Assert-CommandExists -Name "kubectl"

Write-Host "Starting ACR cleanup for registry '$RegistryName'. Delete enabled: $($EnableDelete.IsPresent). Delete throttle: $DeleteThrottleLimit."
Write-Host "Resolving login server for registry '$RegistryName'..."

$loginServer = (Invoke-NativeCommand `
    -Command { az acr show --name $RegistryName --query "loginServer" --output tsv } `
    -ErrorMessage "Failed to resolve the login server for registry '$RegistryName'.").Trim()

if ([string]::IsNullOrWhiteSpace($loginServer)) {
    throw "Could not resolve an ACR login server for registry '$RegistryName'."
}

Write-Host "Resolved login server: $loginServer"

$repositoryNamespaceMapping = @(
    [pscustomobject]@{
        RepositoryPrefix = "cloud-platform"
        Namespace        = "cmgt"
        KubeContext      = @("p-aks")
    },
    [pscustomobject]@{
        RepositoryPrefix = "feltstotte"
        Namespace        = "nis"
        KubeContext      = @()
    }
)

$normalizedKubeContexts = @(Get-NormalizedStringList -Values $KubeContext)
$normalizedIncludeRepositoryPrefix = @(Get-NormalizedStringList -Values $IncludeRepositoryPrefix)
$kubernetesNamespacesToScan = @(Get-KubernetesNamespaceFromRepositoryPrefix -IncludeRepositoryPrefix $normalizedIncludeRepositoryPrefix -RepositoryNamespaceMapping $repositoryNamespaceMapping)

if ($normalizedKubeContexts.Count -eq 0) {
    throw "At least one Kubernetes context must be configured."
}

Write-Host "Repository namespace mappings enabled: cloud-platform/* -> cmgt (p-aks), feltstotte/* -> nis."

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
$namespacesByContext = @{}

Write-Host "Reading Kubernetes resources from $($normalizedKubeContexts.Count) context(s): $resourceKinds..."

if ($kubernetesNamespacesToScan.Count -gt 0) {
    Write-Host "Include prefixes configured. Kubernetes scan is limited to namespace(s): $($kubernetesNamespacesToScan -join ', ')."
}
else {
    Write-Host "No include prefixes configured. Kubernetes scan will read all namespaces."
}

$kubectlPath = (Get-Command kubectl -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$kubectlThrottleLimit = [Math]::Min($ListThrottleLimit, 8)

function Get-KubectlContextArgument {
    param(
        [Parameter(Mandatory = $false)]
        [AllowEmptyString()]
        [string] $Context
    )

    if (-not [string]::IsNullOrWhiteSpace($Context)) {
        return @("--context", $Context)
    }

    return @()
}

Write-Host "Listing namespaces in context(s) $($normalizedKubeContexts -join ', ') concurrently..."
$namespaceCommands = foreach ($context in $normalizedKubeContexts) {
    [pscustomobject]@{
        Key          = $context
        FilePath     = $kubectlPath
        ArgumentList = @(Get-KubectlContextArgument -Context $context) + @("get", "namespaces", "--output", "json")
        ErrorMessage = "Failed to list namespaces from context '$context'."
    }
}

$namespaceOutputs = Invoke-NativeCommandBatch -Commands @($namespaceCommands) -ThrottleLimit $kubectlThrottleLimit
$resourceCommands = [System.Collections.Generic.List[object]]::new()

foreach ($context in $normalizedKubeContexts) {
    $namespaceResources = ConvertFrom-JsonText -Json $namespaceOutputs[$context]
    $namespacesInContext = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($namespaceResource in @($namespaceResources.items)) {
        if ($null -ne $namespaceResource -and -not [string]::IsNullOrWhiteSpace($namespaceResource.metadata.name)) {
            [void] $namespacesInContext.Add($namespaceResource.metadata.name)
        }
    }

    $namespacesByContext[$context] = $namespacesInContext
    Write-Host "Found $($namespacesInContext.Count) namespace(s) in context '$context'."

    if ($kubernetesNamespacesToScan.Count -gt 0) {
        foreach ($namespace in $kubernetesNamespacesToScan) {
            if (-not $namespacesInContext.Contains($namespace)) {
                Write-Warning "Namespace '$namespace' was not found in context '$context'. Skipping this namespace in this context."
                continue
            }

            $resourceCommands.Add([pscustomobject]@{
                Key          = "$context/$namespace"
                Context      = $context
                Namespace    = $namespace
                FilePath     = $kubectlPath
                ArgumentList = @(Get-KubectlContextArgument -Context $context) + @("--namespace", $namespace, "get", $resourceKinds, "--output", "json")
                ErrorMessage = "Failed to read Kubernetes resources from context '$context', namespace '$namespace'."
            })
        }
    }
    else {
        $resourceCommands.Add([pscustomobject]@{
            Key          = "$context/"
            Context      = $context
            Namespace    = $null
            FilePath     = $kubectlPath
            ArgumentList = @(Get-KubectlContextArgument -Context $context) + @("get", $resourceKinds, "--all-namespaces", "--output", "json")
            ErrorMessage = "Failed to read Kubernetes resources from context '$context'."
        })
    }
}

Write-Host "Reading Kubernetes resources with $($resourceCommands.Count) concurrent kubectl request(s) (up to $kubectlThrottleLimit at a time)..."
$resourceOutputs = Invoke-NativeCommandBatch -Commands $resourceCommands.ToArray() -ThrottleLimit $kubectlThrottleLimit

foreach ($context in $normalizedKubeContexts) {
    $tagsBeforeContext = $usedTags.Count
    $digestsBeforeContext = $usedDigests.Count
    $resourcesScannedInContext = 0
    $contextCommands = @($resourceCommands | Where-Object { $_.Context -eq $context })

    foreach ($resourceCommand in $contextCommands) {
        $kubernetesResourceCount = Add-ImageReferencesFromJson -Json $resourceOutputs[$resourceCommand.Key] -LoginServer $loginServer -UsedTags $usedTags -UsedDigests $usedDigests -UsedTagContexts $usedTagContexts -ContextName $context
        $resourceOutputs.Remove($resourceCommand.Key)
        $resourcesScannedInContext += $kubernetesResourceCount

        if ($resourceCommand.Namespace) {
            Write-Host "Scanned $kubernetesResourceCount Kubernetes resource(s) in context '$context', namespace '$($resourceCommand.Namespace)' for '$loginServer' image references."
        }
        else {
            Write-Host "Scanned $kubernetesResourceCount Kubernetes resource(s) in context '$context' for '$loginServer' image references."
        }
    }

    if ($kubernetesNamespacesToScan.Count -gt 0) {
        Write-Host "Context '$context' scanned $resourcesScannedInContext resource(s) in $($contextCommands.Count)/$($kubernetesNamespacesToScan.Count) requested namespace(s), adding $($usedTags.Count - $tagsBeforeContext) new tag reference(s) and $($usedDigests.Count - $digestsBeforeContext) new digest reference(s)."
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

$repositories = @($repositories | Sort-Object)
$normalizedExcludeRepository = @(Get-NormalizedStringList -Values $ExcludeRepository)

if ($normalizedIncludeRepositoryPrefix.Count -gt 0) {
    Write-Host "Only repositories matching these prefixes are eligible for deletion: $($normalizedIncludeRepositoryPrefix -join ', ')"
}
else {
    Write-Host "No repository include prefixes configured. All repositories are eligible before exclusions and will be processed alphabetically."
}

$repositoriesMatchingPrefix = @($repositories | Where-Object { Test-RepositoryPrefix -Repository $_ -IncludeRepositoryPrefix $normalizedIncludeRepositoryPrefix })
$repositoriesWithNamespace = [System.Collections.Generic.List[string]]::new()
$repositoriesSkippedWithoutNamespace = [System.Collections.Generic.List[string]]::new()
$repositoryNamespaceInfoByRepository = @{}

foreach ($repository in $repositoriesMatchingPrefix) {
    $repositoryNamespaceInfo = Get-RepositoryNamespaceInfo -Repository $repository -RepositoryNamespaceMapping $repositoryNamespaceMapping
    $contextsToCheck = @($normalizedKubeContexts)

    if ($repositoryNamespaceInfo.KubeContext.Count -gt 0) {
        $contextsToCheck = @($repositoryNamespaceInfo.KubeContext | Where-Object { $normalizedKubeContexts -contains $_ })
    }

    $availableNamespaceContexts = @(Get-AvailableNamespaceContexts -Namespace $repositoryNamespaceInfo.Namespace -NamespacesByContext $namespacesByContext -KubeContext $contextsToCheck)

    if ($availableNamespaceContexts.Count -gt 0) {
        [void] $repositoriesWithNamespace.Add($repository)
        $repositoryNamespaceInfoByRepository[$repository] = [pscustomobject]@{
            Namespace = $repositoryNamespaceInfo.Namespace
            Contexts  = $availableNamespaceContexts
            IsMapped  = $repositoryNamespaceInfo.IsMapped
        }
    }
    else {
        [void] $repositoriesSkippedWithoutNamespace.Add($repository)
    }
}

$repositoriesToProcess = @($repositoriesWithNamespace | Where-Object { $normalizedExcludeRepository -notcontains $_ } | Sort-Object)
$prefixSkippedRepositoryCount = @($repositories).Count - $repositoriesMatchingPrefix.Count
$excludedRepositoryCount = @($repositoriesWithNamespace | Where-Object { $normalizedExcludeRepository -contains $_ }).Count
$excludedRepositoriesInScope = @($repositoriesWithNamespace | Where-Object { $normalizedExcludeRepository -contains $_ })

Write-Host "Found $(@($repositories).Count) repositories. Prefix filter skipped $prefixSkippedRepositoryCount. Namespace guard skipped $($repositoriesSkippedWithoutNamespace.Count). Excluding $excludedRepositoryCount. Processing $($repositoriesToProcess.Count)."

if ($repositoriesSkippedWithoutNamespace.Count -gt 0) {
    Write-Host "Skipping repositories with no matching Kubernetes namespace or mapping in the configured context(s): $($repositoriesSkippedWithoutNamespace -join ', ')"
}

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
    Write-Host "$($usedTags.Count - $usedTagsForCleanup.Count) tag reference(s) were found outside the cleanup repository scope and do not affect this run."
}

$usedTagNamesByRepository = @{}
foreach ($tagReference in $usedTagsForCleanup) {
    $separatorIndex = $tagReference.LastIndexOf(":")
    $tagRepository = $tagReference.Substring(0, $separatorIndex).ToLowerInvariant()
    if (-not $usedTagNamesByRepository.ContainsKey($tagRepository)) {
        $usedTagNamesByRepository[$tagRepository] = [System.Collections.Generic.List[string]]::new()
    }

    $usedTagNamesByRepository[$tagRepository].Add($tagReference.Substring($separatorIndex + 1))
}

$usedDigestCountByRepository = @{}
foreach ($digestReference in $usedDigestsForCleanup) {
    $digestRepository = $digestReference.Substring(0, $digestReference.IndexOf("@")).ToLowerInvariant()
    $usedDigestCountByRepository[$digestRepository] = 1 + [int] $usedDigestCountByRepository[$digestRepository]
}

$totalDeleteCandidates = 0
$approvedImagesToDelete = [System.Collections.Generic.List[string]]::new()
$repositoryIndex = 0
$acrClient = $null
$manifestsByRepository = @{}

if ($repositoriesToProcess.Count -gt 0) {
    $acrEndpoint = if ([string]::IsNullOrWhiteSpace($RegistryEndpoint)) { "https://$loginServer" } else { $RegistryEndpoint }
    $acrClient = New-AcrClient -LoginServer $loginServer -Endpoint $acrEndpoint -MaxConnections ([Math]::Max($ListThrottleLimit, $DeleteThrottleLimit))
    $manifestsByRepository = Get-AcrManifestMetadata -Client $acrClient -Repositories $repositoriesToProcess -ThrottleLimit $ListThrottleLimit
}

foreach ($repository in $repositoriesToProcess) {
    $repositoryIndex++
    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Processing repository: $repository"

    if ($repositoryNamespaceInfoByRepository.ContainsKey($repository)) {
        $namespaceInfo = $repositoryNamespaceInfoByRepository[$repository]
        $mappingLabel = if ($namespaceInfo.IsMapped) { "mapped namespace" } else { "namespace" }
        Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Repository is eligible through $mappingLabel '$($namespaceInfo.Namespace)' in context(s): $($namespaceInfo.Contexts -join ', ')."
    }

    $manifests = $manifestsByRepository[$repository]
    $imagesToDelete = [System.Collections.Generic.List[object]]::new()
    $protectedByLatestCount = 0
    $protectedByDigestCount = 0
    $protectedByTagCount = 0
    $usedTagsProtectedByLatest = [System.Collections.Generic.List[string]]::new()
    $manifestCount = @($manifests).Count
    $repositoryKey = $repository.ToLowerInvariant()
    $usedTagNamesForRepository = @($usedTagNamesByRepository[$repositoryKey] | Where-Object { $null -ne $_ })
    $usedDigestCountForRepository = [int] $usedDigestCountByRepository[$repositoryKey]

    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Kubernetes references for $($repository): $($usedTagNamesForRepository.Count) tag(s), $usedDigestCountForRepository digest(s)."
    Write-Host "[$repositoryIndex/$($repositoriesToProcess.Count)] Evaluating $manifestCount manifest(s) in $repository..."

    foreach ($manifest in @($manifests)) {
        $digest = $manifest.digest
        if ([string]::IsNullOrWhiteSpace($digest)) {
            Write-Warning "Skipping manifest without digest in repository '$repository'."
            continue
        }

        $manifestTags = @($manifest.tags | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        $usedTagsOnManifest = [System.Collections.Generic.List[string]]::new()

        foreach ($tag in $manifestTags) {
            if ($usedTagsForCleanup.Contains("$($repository):$tag")) {
                $usedTagsOnManifest.Add($tag)
            }
        }

        $hasLatestTag = $false
        foreach ($tag in $manifestTags) {
            if (-not [string]::IsNullOrWhiteSpace($tag) -and $tag.Equals("latest", [System.StringComparison]::OrdinalIgnoreCase)) {
                $hasLatestTag = $true
                break
            }
        }

        if ($hasLatestTag) {
            $protectedByLatestCount++

            if ($usedTagsOnManifest.Count -gt 0) {
                $protectedByTagCount++

                foreach ($usedTagOnManifest in $usedTagsOnManifest) {
                    [void] $usedTagsProtectedByLatest.Add($usedTagOnManifest)
                }
            }

            continue
        }

        $digestKey = "$repository@$($digest.ToLowerInvariant())"
        if ($usedDigestsForCleanup.Contains($digestKey)) {
            $protectedByDigestCount++
            continue
        }

        $hasUsedTag = $false
        if ($usedTagsOnManifest.Count -gt 0) {
            $hasUsedTag = $true
            $protectedByTagCount++
        }

        if (-not $hasUsedTag) {
            $imagesToDelete.Add($manifest)
        }
    }

    foreach ($image in $imagesToDelete) {
        $imageName = "$repository@$($image.digest)"

        if ($EnableDelete) {
            if ($PSCmdlet.ShouldProcess("$RegistryName/$imageName", "Delete ACR manifest")) {
                [void] $approvedImagesToDelete.Add($imageName)
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

    if ($usedTagsProtectedByLatest.Count -gt 0) {
        Write-Warning "Kubernetes tag reference(s) in '$repository' matched manifest(s) that are also protected by latest tag: $(@($usedTagsProtectedByLatest | Sort-Object -Unique) -join ', ')"
    }

    if ($EnableDelete) {
        Write-Host "Queued $($imagesToDelete.Count) unused image manifest(s) from repository $repository for deletion" -ForegroundColor Green
    }
    else {
        Write-Host "Would delete $($imagesToDelete.Count) unused image manifest(s) from repository $repository" -ForegroundColor Green
    }
}

if ($EnableDelete) {
    $deletedCount = 0
    if ($approvedImagesToDelete.Count -gt 0) {
        $deletedCount = Remove-AcrManifest -Client $acrClient -ImageNames $approvedImagesToDelete.ToArray() -ThrottleLimit $DeleteThrottleLimit
    }

    Write-Host "Deleted $deletedCount of $totalDeleteCandidates unused image manifest(s) from registry '$RegistryName'." -ForegroundColor Green
}
else {
    Write-Host "Dry run complete. Would delete $totalDeleteCandidates unused image manifest(s) from registry '$RegistryName'. Pass -EnableDelete to delete them." -ForegroundColor Green
}
