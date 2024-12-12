# This script will grant the Managed Identity the correct permissions to the SharePoint site

#The user running this has to be owner of the SharePoint sitem and be sharepoint admin

# Add the correct 'Application (APP) ID' and 'displayName' for the Managed Identity
$application = @{
    id = "APP ID"
    displayName = "APP DISPLAY NAME"
}

# Add the correct role to grant the Managed Identity (read or write)
$appRole = "write"

# Add the correct SharePoint Online tenant URL and site name
#$spoTenant = "miljodir.sharepoint.com"
$spoSite = "SITE ID"

# No need to change anything below
#$spoSiteId = $spoTenant + ":/sites/" + $spoSite + ":"

Import-Module Microsoft.Graph.Sites
Connect-MgGraph -Scope Sites.FullControl.All

#New-MgSitePermission -SiteId $spoSiteId -Roles $appRole -GrantedToIdentities @{ Application = $application }

New-MgSitePermission -SiteId $spoSite -Roles $appRole -GrantedToIdentities @{ Application = $application }

#To check the permissions run the following command
#get-mgsitepermission -siteid $spoSite | format-list
