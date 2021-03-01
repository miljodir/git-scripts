$ErrorActionPreference = "Continue"

if ($env:ado_pat)
{
    $token = $env:ado_pat
}
else {
    Write-Host "You must set the 'ado_pat' env variable!" -ForegroundColor Red
    Exit
}

$csv = Import-Csv -Path "C:\maps\orgsv2.csv" | sort-object Url

$existingAdmins = @(
"smnil@equinor.com"
"MMYH@equinor.com"
)

$newAdmin = "STEFOR@equinor.com"

foreach ($org in $csv)
{
    echo "Adding to org:" $org.Url
    az devops user add --email-id $newAdmin --license-type express --org $org.Url --send-email-invite false

    if ($?)
    echo "Added $($user) to $($org.Url)"

    foreach ($user in $existingAdmins)
    {
        az devops user update --user $user --license-type express --organization $org.Url

        if $(?)
        echo "Ensured $($user) has license in org $($org.Url)"
    }

    Set-VSTeamAccount -Account $org."Organization Name" -PersonalAccessToken $token

    $user = Get-VSTeamUser | ? DisplayName -eq 'Stefan Forbergskog'
    $group = Get-VSTeamGroup | ? DisplayName -eq 'Project Collection Administrators'
    Add-VSTeamMembership -MemberDescriptor $user.Descriptor -ContainerDescriptor $group.Descriptor
}
