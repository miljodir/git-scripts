$ErrorActionPreference = "Stop"


if (Get-InstalledModule -Name ImportExcel) 
{
    Write-Host "Required module ImportExcel is installed, continuing script"
} 
else 
{
    Write-host "Installing required ImportExcel module before continuing.."
    Install-Module ImportExcel -Confirm -
}

$excelFile = "C:\userlist.xlsx"
$list = Import-Excel -Path $excelFile -WorksheetName "DevOps not in accessit"
$list2 = Import-Excel -Path $excelFile -WorksheetName "Accessit"


if ($?)

    {
        $allEmails = $list.Email
        $joinedEmails = $list2.epost

        $duplicatedEmails = $allEmails + $joinedEmails
        $nonAccessIT = $duplicatedEmails | group | where-object -Property Count -EQ 1
    }
else
    {
        Write-host "Error on import of users"
        exit
    }



$employeeIds = @()


for ($i = 0; $i -lt $nonAccessIT.Length; $i++) { 

    $filter = "UserPrincipalName -eq  ""$nonAccessIT[$i]"""
    $employeeIds += Get-Aduser -Filter "UserPrincipalName -eq '$($nonAccessIT[$i])'"  -Properties extensionAttribute12 | Select-Object extensionAttribute12 #aka EmployeeID |

}

if ($?) 
{
    Write-Host $employeeIds
    $employeeIds | Export-Excel -show
}


if ($?) 
{
    Write-Host "Script completed Successfully." -ForegroundColor Green
}
