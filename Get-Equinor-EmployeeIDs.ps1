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

$excelFile = "C:\userlist.xlsx"
$list = Import-Excel -Path $excelFile

if ($?)

    {
        $emails = $list.Email
    }
else
    {
        Write-host "Error on import of users"
        exit
    }

$employeeIds = @()


for ($i = 0; $i -lt $emails.Length; $i++) { 

    $employeeIds += Get-Aduser -Filter "UserPrincipalName -eq $($emails[$i]) -Properties extensionAttribute12" | Select-Object extensionAttribute12 #aka EmployeeID |

}

if ($?) 
{
    $employeeIds | Export-Excel $excelFile -Append
}


if ($?) 
{
    Write-Host "Script completed Successfully." -ForegroundColor Green
}
