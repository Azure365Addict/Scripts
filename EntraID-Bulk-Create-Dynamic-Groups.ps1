# Description:
# Script creates bulk dynamic device groups with appropriate membership rules.
#
# Requirements:
# - Microsoft.Graph PowerShell module
# - Group.ReadWrite.All or Directory.ReadWRite.All permissions

# This script is https://github.com/a365junkie/Scripts/EntraID-Bulk-Create-Dynamic-Groups.ps1
# See https://a365junkie.com/ for more information.
# V1.0 23-October-2024

# Connect Microsoft Graph
$Scopes = "Group.ReadWrite.All"
Connect-MgGraph -Scopes $Scopes

$Path = "C:\Temp\EntraID-Bulk-Create-Dynamic-Groups_SAMPLE.txt"
$Groups = Import-CSV -Path $Path

# Create dynamic group and define membershuip rule
foreach ($Group in $Groups) 
        {
        $Ext1 = $Group.Region
        $Ext2 = $Group.Country
        $Ext3 = $Group.City
        $Description = $Group.Description

        $rule = "(device.extensionAttribute1 -eq `"$Ext1`") and (device.extensionAttribute2 -eq `"$Ext2`") and (device.extensionAttribute3 -eq `"$Ext3`")"

        New-MgGroup -DisplayName $Group.GroupName -MailEnabled:$false -SecurityEnabled:$true -GroupTypes "DynamicMembership" -MembershipRule $rule -MembershipRuleProcessingState "On" -MailNickname "NotSet" -Description $Description
        }