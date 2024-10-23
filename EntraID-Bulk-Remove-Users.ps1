# Description:
# Script remove users in bulk.
#
# Requirements:
# - Microsoft.Graph PowerShell module
# - User.ReadWrite.All permission

# This script is https://github.com/a365junkie/Scripts/EntraID-Bulk-Remove-Users.ps1
# See https://a365junkie.com/ for more information.
# V1.0 23-October-2024

# Connect Microsoft Graph
$Scopes = "User.ReadWrite.All "
Connect-MgGraph -Scopes $Scopes

# Get the list of users
$Users = Import-CSV "C:\Temp\EntraID-Bulk-Remove-Users_SAMPLE.csv" 

foreach ($User in $Users)

        {
        $UPN = $User.UserPrincipalName
                                                 
            try
            {
                $AADUser = Get-MgUser -UserId $UPN -ErrorAction Stop #Check if user exists
                Remove-MgUser -UserId $UPN
                Write-Host "Deleted user $UPN" -ForegroundColor Green
            }
    
                catch
                {
                Write-Host "WARNING: Could not delete user $UPN - User does not exist in Entra ID" -ForegroundColor Yellow
                }


        }