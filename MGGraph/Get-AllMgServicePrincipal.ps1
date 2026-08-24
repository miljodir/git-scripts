# One-time installation:
# Install-Module Microsoft.Graph -Scope CurrentUser

param(
    [string]$OutputPath = ".\EntraServicePrincipals.csv",

    # Use this if you cannot consent to AuditLog.Read.All.
    [switch]$SkipCreatedByAudit
)

$ErrorActionPreference = "Stop"
$now = [DateTimeOffset]::UtcNow

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

$scopes = @(
    "Application.Read.All"
    "Directory.Read.All"
)

if (-not $SkipCreatedByAudit) {
    Import-Module Microsoft.Graph.Reports
    $scopes += "AuditLog.Read.All"
}

Connect-MgGraph -Scopes $scopes -NoWelcome

$tenantId = (Get-MgContext).TenantId

function Format-UtcDate {
    param($Value)

    if ($null -eq $Value) {
        return $null
    }

    return ([DateTimeOffset]$Value).ToUniversalTime().ToString("o")
}

function Get-OwnerSummary {
    param(
        [Parameter(Mandatory)]
        [ValidateSet("Application", "ServicePrincipal")]
        [string]$ObjectType,

        [Parameter(Mandatory)]
        [string]$ObjectId
    )

    $owners = if ($ObjectType -eq "Application") {
        @(Get-MgApplicationOwner -ApplicationId $ObjectId -All)
    }
    else {
        @(Get-MgServicePrincipalOwner -ServicePrincipalId $ObjectId -All)
    }

    $ownerDetails = foreach ($owner in $owners) {
        $properties = $owner.AdditionalProperties
        $odataType = [string]$properties["@odata.type"]

        $displayName = [string]$properties["displayName"]
        if ([string]::IsNullOrWhiteSpace($displayName)) {
            $displayName = $owner.Id
        }

        [pscustomobject]@{
            Id                = $owner.Id
            Type              = $odataType -replace "#microsoft.graph.", ""
            DisplayName       = $displayName
            UserPrincipalName = [string]$properties["userPrincipalName"]
            AppId             = [string]$properties["appId"]
        }
    }

    return [pscustomobject]@{
        Count = $ownerDetails.Count
        Names = ($ownerDetails.DisplayName | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }) -join "; "
        Ids = ($ownerDetails.Id | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_)
        }) -join "; "
        DetailsJson = if ($ownerDetails.Count -gt 0) {
            ConvertTo-Json -InputObject @($ownerDetails) -Compress -Depth 4
        }
        else {
            "[]"
        }
    }
}

function Get-PasswordCredentialSummary {
    param(
        [AllowNull()]
        [object[]]$Credentials
    )

    $credentials = @($Credentials | Where-Object {
        $null -ne $_
    })

    $details = foreach ($credential in $credentials) {
        $startDate = if ($null -ne $credential.StartDateTime) {
            [DateTimeOffset]$credential.StartDateTime
        }

        $endDate = if ($null -ne $credential.EndDateTime) {
            [DateTimeOffset]$credential.EndDateTime
        }

        $status = if ($null -eq $endDate) {
            "Unknown"
        }
        elseif ($endDate -le $now) {
            "Expired"
        }
        elseif (($null -eq $startDate -or $startDate -le $now) -and
                $endDate -le $now.AddDays(30)) {
            "ExpiringWithin30Days"
        }
        elseif ($null -eq $startDate -or $startDate -le $now) {
            "Active"
        }
        else {
            "NotYetValid"
        }

        [pscustomobject]@{
            KeyId         = [string]$credential.KeyId
            DisplayName   = [string]$credential.DisplayName
            Hint          = [string]$credential.Hint
            StartDateTime = Format-UtcDate $credential.StartDateTime
            EndDateTime   = Format-UtcDate $credential.EndDateTime
            Status        = $status
        }
    }

    $active = @($details | Where-Object {
        $_.Status -in @("Active", "ExpiringWithin30Days")
    })

    $expired = @($details | Where-Object {
        $_.Status -eq "Expired"
    })

    $expiringSoon = @($details | Where-Object {
        $_.Status -eq "ExpiringWithin30Days"
    })

    $expiryDates = @(
        $credentials |
            Where-Object { $null -ne $_.EndDateTime } |
            ForEach-Object { [DateTimeOffset]$_.EndDateTime }
    )

    return [pscustomobject]@{
        TotalCount       = $details.Count
        ActiveCount      = $active.Count
        ExpiredCount     = $expired.Count
        Expiring30dCount = $expiringSoon.Count
        EarliestExpiry   = if ($expiryDates.Count -gt 0) {
            Format-UtcDate (($expiryDates | Sort-Object)[0])
        }
        else {
            $null
        }
        LatestExpiry = if ($expiryDates.Count -gt 0) {
            Format-UtcDate (($expiryDates | Sort-Object)[-1])
        }
        else {
            $null
        }
        DetailsJson = if ($details.Count -gt 0) {
            ConvertTo-Json -InputObject @($details) -Compress -Depth 4
        }
        else {
            "[]"
        }
    }
}

function Get-CertificateCredentialSummary {
    param(
        [AllowNull()]
        [object[]]$Credentials
    )

    $credentials = @($Credentials | Where-Object {
        $null -ne $_
    })

    $details = foreach ($credential in $credentials) {
        $endDate = if ($null -ne $credential.EndDateTime) {
            [DateTimeOffset]$credential.EndDateTime
        }

        [pscustomobject]@{
            KeyId         = [string]$credential.KeyId
            DisplayName   = [string]$credential.DisplayName
            Type          = [string]$credential.Type
            Usage         = [string]$credential.Usage
            StartDateTime = Format-UtcDate $credential.StartDateTime
            EndDateTime   = Format-UtcDate $credential.EndDateTime
            Status        = if ($null -eq $endDate) {
                "Unknown"
            }
            elseif ($endDate -le $now) {
                "Expired"
            }
            else {
                "Active"
            }
        }
    }

    return [pscustomobject]@{
        TotalCount = $details.Count
        ActiveCount = @($details | Where-Object {
            $_.Status -eq "Active"
        }).Count
        ExpiredCount = @($details | Where-Object {
            $_.Status -eq "Expired"
        }).Count
        DetailsJson = if ($details.Count -gt 0) {
            ConvertTo-Json -InputObject @($details) -Compress -Depth 4
        }
        else {
            "[]"
        }
    }
}

function Get-AuditActor {
    param($AuditEvent)

    if ($null -eq $AuditEvent) {
        return [pscustomobject]@{
            ActivityDateTime = $null
            ActorType        = $null
            ActorId          = $null
            ActorDisplayName = $null
            ActorIdentifier  = $null
        }
    }

    if ($null -ne $AuditEvent.InitiatedBy.User) {
        $actor = $AuditEvent.InitiatedBy.User

        return [pscustomobject]@{
            ActivityDateTime = Format-UtcDate $AuditEvent.ActivityDateTime
            ActorType        = "User"
            ActorId          = $actor.Id
            ActorDisplayName = $actor.DisplayName
            ActorIdentifier  = $actor.UserPrincipalName
        }
    }

    if ($null -ne $AuditEvent.InitiatedBy.App) {
        $actor = $AuditEvent.InitiatedBy.App

        return [pscustomobject]@{
            ActivityDateTime = Format-UtcDate $AuditEvent.ActivityDateTime
            ActorType        = "Application"
            ActorId          = $actor.ServicePrincipalId
            ActorDisplayName = $actor.DisplayName
            ActorIdentifier  = $actor.AppId
        }
    }

    return [pscustomobject]@{
        ActivityDateTime = Format-UtcDate $AuditEvent.ActivityDateTime
        ActorType        = "Unknown"
        ActorId          = $null
        ActorDisplayName = $null
        ActorIdentifier  = $null
    }
}

Write-Host "Reading application registrations..."

$applications = @(
    Get-MgApplication -All -Property @(
        "id"
        "appId"
        "displayName"
        "createdDateTime"
        "signInAudience"
        "publisherDomain"
        "passwordCredentials"
        "keyCredentials"
        "web"
        "spa"
        "publicClient"
    )
)

$applicationByAppId = @{}

foreach ($application in $applications) {
    if (-not [string]::IsNullOrWhiteSpace($application.AppId)) {
        $applicationByAppId[$application.AppId.ToLowerInvariant()] = $application
    }
}

Write-Host "Reading service principals..."

$servicePrincipals = @(
    Get-MgServicePrincipal -All -Property @(
        "id"
        "appId"
        "displayName"
        "servicePrincipalType"
        "accountEnabled"
        "createdDateTime"
        "appOwnerOrganizationId"
        "passwordCredentials"
        "keyCredentials"
        "tags"
    )
)

$creationAuditByTargetId = @{}

if (-not $SkipCreatedByAudit) {
    Write-Host "Reading available Entra creation audit events..."

    try {
        $auditEvents = @(
            Get-MgAuditLogDirectoryAudit `
                -Filter "activityDisplayName eq 'Add service principal'" `
                -All
        ) + @(
            Get-MgAuditLogDirectoryAudit `
                -Filter "activityDisplayName eq 'Add application'" `
                -All
        )

        foreach ($event in ($auditEvents | Sort-Object ActivityDateTime)) {
            foreach ($target in $event.TargetResources) {
                if (-not [string]::IsNullOrWhiteSpace($target.Id) -and
                    -not $creationAuditByTargetId.ContainsKey($target.Id)) {
                    $creationAuditByTargetId[$target.Id] = $event
                }
            }
        }
    }
    catch {
        Write-Warning (
            "Creation audit events could not be read. Creator columns will be empty. " +
            "Error: $($_.Exception.Message)"
        )
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$position = 0

foreach ($servicePrincipal in $servicePrincipals) {
    $position++

    Write-Progress `
        -Activity "Building service-principal inventory" `
        -Status "$position of $($servicePrincipals.Count): $($servicePrincipal.DisplayName)" `
        -PercentComplete (($position / $servicePrincipals.Count) * 100)

    $application = $null

    if (-not [string]::IsNullOrWhiteSpace($servicePrincipal.AppId)) {
        $applicationKey = $servicePrincipal.AppId.ToLowerInvariant()

        if ($applicationByAppId.ContainsKey($applicationKey)) {
            $application = $applicationByAppId[$applicationKey]
        }
    }

    $servicePrincipalOwners = Get-OwnerSummary `
        -ObjectType ServicePrincipal `
        -ObjectId $servicePrincipal.Id

    if ($null -ne $application) {
        $applicationOwners = Get-OwnerSummary `
            -ObjectType Application `
            -ObjectId $application.Id

        $applicationSecrets = Get-PasswordCredentialSummary `
            -Credentials $application.PasswordCredentials

        $applicationCertificates = Get-CertificateCredentialSummary `
            -Credentials $application.KeyCredentials

        $redirectUris = @(
            $application.Web.RedirectUris
            $application.Spa.RedirectUris
            $application.PublicClient.RedirectUris
        ) |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
            Sort-Object -Unique
    }
    else {
        $applicationOwners = [pscustomobject]@{
            Count       = 0
            Names       = ""
            Ids         = ""
            DetailsJson = "[]"
        }

        $applicationSecrets = Get-PasswordCredentialSummary -Credentials @()
        $applicationCertificates = Get-CertificateCredentialSummary -Credentials @()
        $redirectUris = @()
    }

    $servicePrincipalSecrets = Get-PasswordCredentialSummary `
        -Credentials $servicePrincipal.PasswordCredentials

    $servicePrincipalCertificates = Get-CertificateCredentialSummary `
        -Credentials $servicePrincipal.KeyCredentials

    $servicePrincipalAudit = if (
        $creationAuditByTargetId.ContainsKey($servicePrincipal.Id)
    ) {
        Get-AuditActor $creationAuditByTargetId[$servicePrincipal.Id]
    }
    else {
        Get-AuditActor $null
    }

    $applicationAudit = if (
        $null -ne $application -and
        $creationAuditByTargetId.ContainsKey($application.Id)
    ) {
        Get-AuditActor $creationAuditByTargetId[$application.Id]
    }
    else {
        Get-AuditActor $null
    }

$results.Add([pscustomobject][ordered]@{
    AppId                                  = $servicePrincipal.AppId
    ServicePrincipalObjectId               = $servicePrincipal.Id
    ServicePrincipalName                   = $servicePrincipal.DisplayName
    ServicePrincipalType                   = $servicePrincipal.ServicePrincipalType
    AccountEnabled                         = $servicePrincipal.AccountEnabled
    ServicePrincipalCreatedDateTime        = Format-UtcDate $servicePrincipal.CreatedDateTime
    AppOwnerOrganizationId                 = $servicePrincipal.AppOwnerOrganizationId
    IsTenantOwned                          = (
        [string]$servicePrincipal.AppOwnerOrganizationId -eq
        [string]$tenantId
    )

    ServicePrincipalOwnerCount             = $servicePrincipalOwners.Count
    ServicePrincipalOwnerNames             = $servicePrincipalOwners.Names
    ServicePrincipalOwnersJson             = $servicePrincipalOwners.DetailsJson

    ServicePrincipalCreatedByType          = $servicePrincipalAudit.ActorType
    ServicePrincipalCreatedByName          = $servicePrincipalAudit.ActorDisplayName
    ServicePrincipalCreatedByIdentifier    = $servicePrincipalAudit.ActorIdentifier
    ServicePrincipalCreatedByObjectId      = $servicePrincipalAudit.ActorId
    ServicePrincipalCreationAuditTime      = $servicePrincipalAudit.ActivityDateTime

    ApplicationObjectId                    = $application.Id
    ApplicationDisplayName                 = $application.DisplayName
    ApplicationCreatedDateTime             = Format-UtcDate $application.CreatedDateTime
    ApplicationSignInAudience              = $application.SignInAudience

    ApplicationOwnerCount                  = $applicationOwners.Count
    ApplicationOwnerNames                  = $applicationOwners.Names
    ApplicationOwnersJson                  = $applicationOwners.DetailsJson

    ApplicationCreatedByType               = $applicationAudit.ActorType
    ApplicationCreatedByName               = $applicationAudit.ActorDisplayName
    ApplicationCreatedByIdentifier         = $applicationAudit.ActorIdentifier
    ApplicationCreatedByObjectId           = $applicationAudit.ActorId
    ApplicationCreationAuditTime           = $applicationAudit.ActivityDateTime

    HasRedirectUris                        = ($redirectUris.Count -gt 0)
    RedirectUris                           = $redirectUris -join "; "

    ApplicationClientSecretCount           = $applicationSecrets.TotalCount
    ApplicationActiveSecretCount           = $applicationSecrets.ActiveCount
    ApplicationExpiredSecretCount          = $applicationSecrets.ExpiredCount
    ApplicationSecretsExpiringWithin30Days = $applicationSecrets.Expiring30dCount
    ApplicationClientSecretsJson           = $applicationSecrets.DetailsJson

    ApplicationCertificateCount            = $applicationCertificates.TotalCount
    ApplicationActiveCertificateCount      = $applicationCertificates.ActiveCount
    ApplicationExpiredCertificateCount     = $applicationCertificates.ExpiredCount

    ServicePrincipalPasswordCount          = $servicePrincipalSecrets.TotalCount
    ServicePrincipalActivePasswordCount    = $servicePrincipalSecrets.ActiveCount
    ServicePrincipalExpiredPasswordCount   = $servicePrincipalSecrets.ExpiredCount
    ServicePrincipalPasswordsExpiringWithin30Days = $servicePrincipalSecrets.Expiring30dCount
    ServicePrincipalPasswordsJson          = $servicePrincipalSecrets.DetailsJson

    ServicePrincipalCertificateCount       = $servicePrincipalCertificates.TotalCount
    ServicePrincipalActiveCertificateCount = $servicePrincipalCertificates.ActiveCount
    ServicePrincipalExpiredCertificateCount = $servicePrincipalCertificates.ExpiredCount

    Tags                                   = @($servicePrincipal.Tags) -join "; "
    InventoryGeneratedUtc                  = $now.ToString("o")
})
}

Write-Progress -Activity "Building service-principal inventory" -Completed

$resolvedOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath(
    $OutputPath
)

$results |
    Sort-Object ServicePrincipalName, ServicePrincipalObjectId |
    Export-Csv -Path $resolvedOutputPath -NoTypeInformation -Encoding utf8

Write-Host ""
Write-Host "Exported $($results.Count) service principals to:"
Write-Host $resolvedOutputPath
Write-Host ""
Write-Host "Use AppId as the Sentinel watchlist SearchKey."