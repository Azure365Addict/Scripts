<#
.SYNOPSIS
Retrieves all users with eligible Microsoft Entra ID (Azure AD) role assignments.

.DESCRIPTION
This script connects to Microsoft Graph and retrieves all users who have eligible role assignments
in Microsoft Entra ID (Azure Active Directory).
It queries role eligibility schedules via the Microsoft.Graph.Identity.Governance module,
filters for user principals, and collects their display name, UPN, and role name.
The results are displayed in an interactive Out-GridView window and can optionally be exported to CSV.

.PARAMETER None
The script requires no parameters. Update variables inside the script (e.g., $Path) if exporting to CSV.

.NOTES
Requirements:
- Microsoft.Graph.Identity.Governance PowerShell module
- Microsoft Graph delegated permissions:
  RoleEligibilitySchedule.Read.Directory
  RoleManagement.Read.Directory

More information:
https://azure365addict.com/2025/03/04/auditing-azure-role-assignments-with-powershell/
#>

# Connect Microsoft Graph
$Scopes = "RoleEligibilitySchedule.Read.Directory, RoleManagement.Read.Directory" # Define permissions
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

