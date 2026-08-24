# To be used in Microsoft Sentinel watchlist to correlate with Azure AD sign-in logs and other data sources to inspect usage patterns of all service principals
# Import the CSV file as a Sentinel watchlist with SearchKey "AppId".

Import-Module Microsoft.Graph.Authentication
Import-Module Microsoft.Graph.Applications

Connect-MgGraph -Scopes "Application.Read.All" -NoWelcome

$tenantId = (Get-MgContext).TenantId

$applications = Get-MgApplication -All -Property @(
    "id",
    "appId",
    "displayName",
    "createdDateTime",
    "signInAudience",
    "web",
    "spa",
    "publicClient"
)

$applicationsByAppId = @{}

foreach ($application in $applications) {
    if ($application.AppId) {
        $applicationsByAppId[$application.AppId.ToLowerInvariant()] = $application
    }
}

$inventory = Get-MgServicePrincipal -All -Property @(
    "id",
    "appId",
    "displayName",
    "accountEnabled",
    "createdDateTime",
    "servicePrincipalType",
    "appOwnerOrganizationId"
) | ForEach-Object {
    $servicePrincipal = $_
    $application = $null

    if ($servicePrincipal.AppId) {
        $application =
            $applicationsByAppId[$servicePrincipal.AppId.ToLowerInvariant()]
    }

    $redirectUris = @(
        $application.Web.RedirectUris
        $application.Spa.RedirectUris
        $application.PublicClient.RedirectUris
    ) |
        Where-Object { $_ } |
        Sort-Object -Unique

    [PSCustomObject]@{
        AppId                    = $servicePrincipal.AppId
        ServicePrincipalObjectId = $servicePrincipal.Id
        ServicePrincipalName     = $servicePrincipal.DisplayName
        ServicePrincipalType     = $servicePrincipal.ServicePrincipalType
        AccountEnabled           = $servicePrincipal.AccountEnabled
        CreatedDateTime          = $servicePrincipal.CreatedDateTime
        AppOwnerTenantId         = $servicePrincipal.AppOwnerOrganizationId
        IsTenantOwned            = (
            "$($servicePrincipal.AppOwnerOrganizationId)" -eq $tenantId
        )
        ApplicationObjectId      = $application.Id
        SignInAudience           = $application.SignInAudience
        HasRedirectUris          = ($redirectUris.Count -gt 0)
        RedirectUris             = ($redirectUris -join ";")
    }
}

$inventory |
    Export-Csv ".\EntraServicePrincipals.csv" `
        -NoTypeInformation `
        -Encoding UTF8