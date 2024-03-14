# Finds all members of a groups which starts with "az rbac sub p-" and contains "contributors" in the display name
# These should be the only groups with contributor roles in relevant subscripions

Connect-MGGraph -Scopes "GroupMember.Read.All"

$groups = Get-MgGroup -Filter "startsWith(displayName, 'az rbac sub p-')" -Top 999 | Where-Object { $_.DisplayName -like "*contributors*" }
$members = @()

$groups | Foreach-Object { $member = (Get-MgGroupMember -GroupId $_.Id)

    foreach ($m in $member) {
        $members += [PSCustomObject]@{
            DisplayName = $m.AdditionalProperties.displayName
            Email       = $m.AdditionalProperties.userPrincipalName
        }
    }
}

$members = $members | Where-Object -Property Email -Like "*@miljodir.no" |  Sort-Object -Property Email | Get-Unique -AsString

$members.count