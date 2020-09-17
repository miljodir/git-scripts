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
$excelFile = "C:\Github unlinked details.xlsx"
$list = Import-Excel -Path $excelFile
[array]$suggestedEmailList

if ($?)

    {
        $userNames = $list.login
        $humanNames = $list.name
    }
else
    {
        Write-host "Error on import of users"
        exit
    }

    [System.DirectoryServices.DirectorySearcher] $searcher = New-Object System.DirectoryServices.DirectorySearcher


    for ($i = 0; $i -lt $humanNames.Length; $i++) { 

        if ($($humanNames[$i]) -ne "") { 

        
        $split = $($humanNames[$i]) -split " "

        $firstName = $split[0]
        $lastName = $split[$split.Count - 1]

        $searcher.Filter = "(&(objectCategory=User)(name=$firstName* $lastName))"

        $s = $searcher.FindOne() | select Properties -ExpandProperty Properties

        }
            if ($s -ne $null || $s -ne "")
            {
             $userMail= $s['userprincipalname']

                if ($userMail -contains "f_PRSALTSFA@statoil.net")
                {
                    $userMail = "USER NOT FOUND DUE TO EMPTY NAME"
                }

            }
            else {
                $userMail = "USER NOT FOUND FROM AUTOMATED AD LOOKUP"
            }
            echo $userMail
            $suggestedEmailList += $userMail
    }

$suggestedEmailList | export-excel