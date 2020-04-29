$emails = @(

    "auls@equinor.com"
    "roarla@equinor.com"

)


$orgs= @(
    "https://dev.azure.com/audunsorg1"
    "https://dev.azure.com/roartest1"

)

if ($orgs.Length -eq $emails.Length)

{

    $cred = Get-Credential -username "gm_sds_rdi@equinor.com"

    for ($i = 0; $i -lt $orgs.Length; $i++) { 

        Send-MailMessage -From "SDP Team <gm_sds_rdi@equinor.com>" -To $emails[$i] -Subject "Info Regarding your Azure DevOps organizaion at $($orgs[$i])" `
        -Body "
        You are receiving this email because you are the owner of an Azure DevOps organization using Equinor Azure AD authentication.
        
        Equinor has 500+ Azure DevOps organisations and we need to collect some information about its use to understand demand and governance, but also to clean-up organisations which are not in use.
        This simple survey will provide us with useful data to understand Equinor's use of Azure DevOps.

        The survey can be found here: https://forms.office.com/Pages/ResponsePage.aspx?id=NaKkOuK21UiRlX_PBbRZsB131KVwPclEvyzMgDkmOaVURFZEVzgxTUdSSlEwRFQyRjQwODJPQ1AyWS4u

        We also wish that everyone in Equinor who uses Azure DevOps use the www.dev.azure.com/equinor organization. Apply for access in AccessIT.

        We do not have access to delete your organization, and we ask that you do this unless you are actively using your self created organization.
        Your organization is located here: $($orgs[$i])

        If you have any questions, either reach out to @toolbox in the #sdpteam channel on equinor.slack.com, or send an email to gm_toolbox@equinor.com" `
        -SmtpServer "mrrr.statoil.com" -Port 25 -Credential $cred -UseSsl

    }

} else 
{
    Write-Host "Email and org arrays must be of the same length!"
}
