﻿# Description:
# Script connects to MgGraph and gets all users with Eligible Microsoft Entra ID Roles.
#
# Requirements:
# - Microsoft.Graph.Identity.Governance PowerShell module
# - RoleEligibilitySchedule.Read.Directory and RoleManagement.Read.Directory permissions

# This script is https://github.com/365ScriptJunkie/Scripts/EntraID-Get-Eligible-Role-Assignments.ps1
# See https://365ScriptJunkie.com/ for more information.
# V1.0 22-October-2024

# Connect Microsoft Graph
$Scopes = "RoleEligibilitySchedule.Read.Directory, RoleManagement.Read.Directory"
Connect-MgGraph -Scopes $Scopes

$EligibleAADUserData = @()
$EligibleAssignments = Get-MgRoleManagementDirectoryRoleEligibilityScheduleInstance -ExpandProperty "*" -All
foreach($Role in $EligibleAssignments){

    $RoleName = Get-MgRoleManagementDirectoryRoleDefinition -UnifiedRoleDefinitionId $Role.RoleDefinitionId

    if($Role.Principal.AdditionalProperties.'@odata.type' -eq "#microsoft.graph.user"){
        $UserProperties = [pscustomobject]@{
            PrincipalDisplayName = $Role.Principal.AdditionalProperties.displayName
            UserPrincipalName = $Role.Principal.AdditionalProperties.userPrincipalName
            RoleName = $RoleName.DisplayName
        }
        $EligibleAADUserData += $UserProperties
    }
}

$EligibleAADUserData | Out-GridView

# Export to CSV (unhash and change $Path if needed)
#$Path = "C:\Temp\EntraID-Get-Eligible-Role-Assignments.csv"
#$EligibleAzureUserData | Export-Csv -Path $Path -NoTypeInformation