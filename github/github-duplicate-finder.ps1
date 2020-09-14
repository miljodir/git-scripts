### To find unlinked users, join two lists of usernames and list user accounts + fullNames of ones with a 1 count.

$excelFile = "C:\github.xlsx"

$list = Import-Excel -Path $excelFile -WorksheetName "All users"
$list2 = Import-Excel -Path $excelFile -WorksheetName "SAML linked users"

$list3 

    if ($?)

        {
            #$knownMails = $list2.nameId
            $alllogins = $list.login
            $linkedlogins = $list2.login

            $list3 = $list + $list2

            $unLinked = $list3 | group -Property login | where-object -Property Count -EQ 1
        }
    else
        {
            exit
        }

        $employeeIds = @()

$unLinked.Group | Export-Excel