$ErrorActionPreference = "Continue"

if ($env:ado_pat)
{
    $token = $env:ado_pat
}
else {
    Write-Host "You must set the 'ado_pat' env variable!" -ForegroundColor Red
    Exit
}

$csv = Import-Csv -Path "C:\maps\orgsv5.csv" | sort-object Url

$newAdmin = "HAKE@equinor.com"

foreach ($org in $csv)
{
    echo "Updating memberships in org: $($org.Url) "
    az devops user add --email-id $newAdmin --license-type express --org $org.Url --send-email-invite false

    if ($?)
    { echo "Added $($user) to $($org.Url)" }

try {
    Set-VSTeamAccount -Account $org."Organization Name" -PersonalAccessToken $token

    $user = Get-VSTeamUser | ? DisplayName -eq 'Håkon Eriksson'
    $group = Get-VSTeamGroup | ? DisplayName -eq 'Project Collection Administrators'
    Add-VSTeamMembership -MemberDescriptor $user.Descriptor -ContainerDescriptor $group.Descriptor
}
    catch {
        echo "Probably org is deleted or someone threw you out"
     }
}
