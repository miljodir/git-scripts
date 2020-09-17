$ErrorActionPreference = "Continue"


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
$excelFile = "C:\appl\ghmails2.xlsx"
$list = Import-Excel -Path $excelFile -WorksheetName "Sheet1"

if ($?)

    {
        $users = $list.login
        $emails = $list.mail
    }
else
    {
        Write-host "Error on import of users"
        exit
    }

$cred = Get-Credential -username $userFrom

for ($i = 0; $i -lt $emails.Length; $i++) { 

    Write-host "Sending email to user: $($emails[$i]) with Github username: $($users[$i])"

    Send-MailMessage -From "GM IT Toolbox <gm_toolbox@equinor.com>" -To $emails[$i] -Subject "Action required for your Github account $($users[$i])" `
    -Cc $userFrom -Body "

    You are receiving this email because you are part of Equinor's organization on Github, as we believe the Github account $($users[$i]) https://github.com/$($users[$i]) belongs to you.
    If this information is incorrect, or you do not use Github anymore, you may safely ignore this email.

    Equinor intends to enforce Single Sign-on (SSO) through Azure AD. Your Github account is currently NOT linked with SSO.

    We ask you to fix this by:
    1) Clicking this URL to complete linking to your account: https://github.com/orgs/equinor/sso
    2) Ensure that your existing Personal Access tokens (if any) will continue to work, by clicking 'Enable SSO' per token: https://github.com/settings/tokens

    If you are getting an error during the linking process or during sign-in after linking your account:
    Ensure you are part of the AccessIT group 'Github' https://accessit.equinor.com/Search/Search?term=github
    You may need to wait up to 75 minutes after AccessIT request approval before the account linking will work.

    Please take a few minutes to do this, as this will save both yourself and the Toolbox team time down the line. 
    Your account will eventually be removed from Equinor's Github organization if you do not take action. 
    
    If you have any questions, either reach out to @toolbox in the #sdpteam channel on https://equinor.slack.com, or reply to this email." `
    -SmtpServer "mrrr.statoil.com" -Port 25 -Credential $cred -UseSsl
}

if ($?) 
{
    Write-Host "Script completed Successfully." -ForegroundColor Green
}
