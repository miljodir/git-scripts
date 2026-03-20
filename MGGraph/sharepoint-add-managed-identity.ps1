# This script will grant the Managed Identity the correct permissions to the SharePoint site

# The user running this has to be owner of the SharePoint site AND be sharepoint admin

# Add the correct 'Application (APP) ID' and 'displayName' for the Managed Identity

param( 
    [string] $ApplicationId = "placeholder",
    [string] $ApplicationDisplayName = "placeholder",
    [string] $SharePointSiteName = "placeholdersitename",
    [string] $AppRole = "write"
)


$application = @{
    id = $ApplicationId
    displayName = $ApplicationDisplayName
}

Import-Module Microsoft.Graph.Sites
Connect-MgGraph -Scope Sites.FullControl.All, Application.Read.All

$site = Invoke-MgGraphRequest -Uri "v1.0/sites?search=$($SharePointSiteName)"
$spoSiteId = ($site.value.id -split ",")[1]

New-MgSitePermission -SiteId $spoSiteId -Roles $AppRole -GrantedToIdentities @{ Application = $application }

#To check the permissions run the following command
Get-MgSitePermission -SiteId $spoSiteId | Format-List
