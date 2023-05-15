$group = Get-AzADgroup -DisplayName "github-tilgang-miljodir"

$sheet = Import-Excel -Path "c:/appl/users.xlsx"

foreach ($user in $sheet) {
    if ($user.mdir_bruker -ne "" -and $null -ne $user.mdir_bruker -and $user.mdir_bruker -ne "?" ) {
        #Write-Host "Login $($user.login) with presumed AAD account $($user.mdir_bruker) will be added" -ForegroundColor Green
        #$ad = Get-AzADUser -UserPrincipalName $user.mdir_bruker
        Add-AzADGroupMember -TargetGroupObjectId $group.Id -MemberUserPrincipalName $user.mdir_bruker #-MemberObjectId $ad.Id
    }
    else {
        Write-Host "User $($user.login) will not be added to group" -ForegroundColor Red
    }
}