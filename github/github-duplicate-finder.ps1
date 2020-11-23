### To find unlinked users, join two lists of usernames and list user accounts + fullNames of ones with a 1 count.

$excelFile = "C:\appl\ghequinormails.xlsx"

$list = Import-Excel -Path $excelFile -WorksheetName "Ha2"
$list2 = Import-Excel -Path $excelFile -WorksheetName "Ha3"

$list3 

    if ($?)

        {
            #$knownMails = $list2.nameId
            $Github = $list.Email.ToUpper()
            $VS = $list2.Email.ToUpper()

            $list3 = $Github + $VS

            $HaveBoth = $list3 | group | where-object -Property Count -EQ 2
        }
    else
        {
            exit
        }

        $employeeIds = @()

$HaveBoth.Group | Export-Excel