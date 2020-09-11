$ErrorActionPreference = "Stop"


if (Get-InstalledModule -Name ImportExcel) 
{
    Write-Host "Required module ImportExcel is installed, continuing script"
} 
else 
{
    Write-host "Installing required ImportExcel module before continuing.."
    Install-Module ImportExcel -Confirm
}

$userFrom = "gm_toolbox@equinor.com"
$excelFile = "C:\github.xlsx"
$list = Import-Excel -Path $excelFile

if ($?)

    {
        $emails = $list.Email
        $users = $list.Login
    }
else
    {
        Write-host "Error on import of users"
        exit
    }

$cred = Get-Credential -username $userFrom

for ($i = 0; $i -lt $orgs.Length; $i++) { 

    Write-host "Sending email to user: $($emails[$i]) with username: $($users[$i])"

    Send-MailMessage -From "GM IT Toolbox <gm_toolbox@equinor.com>" -To $emails[$i] -Subject "Info regarding your Github account $($users[$i])" `
    -Body "
    You are receiving this email because you are part of Equinor's organization on Github.

    Equinor intends to enforce Single Sign-on (SSO) through Azure AD. Your Github account is currently NOT linked with SSO.

    We ask you to fix this by:
    1) Clicking this URL to complete linking to your account: https://github.com/settings/tokens
    2) Ensure that your existing Personal Access tokens (if any) will continue to work, by clicking 'Enable SSO' per token: https://github.com/settings/tokens
    Note that if you were not part of the group from before, you may need to wait up to 75 minutes before the latter link will work for you.

    If you are now getting an error during the linking process or during signing in:
    Ensure you are part of the AccessIT group 'Github' https://accessit.equinor.com/Search/Search?term=github

    Please take a few minutes to do this, as this will save both yourself and the SDP team time down the line.
    
    If you have any questions, either reach out to @toolbox in the #sdpteam channel on equinor.slack.com, or reply to this email" `
    -SmtpServer "mrrr.statoil.com" -Port 25 -Credential $cred -UseSsl
}

if ($?) 
{
    Write-Host "Script completed Successfully." -ForegroundColor Green
}
