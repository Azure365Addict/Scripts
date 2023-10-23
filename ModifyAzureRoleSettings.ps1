# Connect to AzureAD
Connect-AzureAD

# Get Tenant Id
$Tenant = Get-AzureADTenantDetail
$TenantID = $Tenant.ObjectId

# Get Role Assignments for Enterprise subscription / Number of assignments per subscription / Not needed in order to run the script
#$RoleAssignments = Get-AzureADMSPrivilegedRoleAssignment –ProviderId AzureResources –ResourceId $Resource.Id

# Get all subscriptions
$Subscriptions = Get-AzureADMSPrivilegedResource -ProviderId AzureResources -Filter "Type eq 'subscription'"

# Get particular resource [in this case Enterprise Subscription]
$Resource = Get-AzureADMSPrivilegedResource -ProviderId AzureResources -Filter "DisplayName eq 'Enterprise'"

#####################################################################################

# Get available roles for Enterprise subscription
$Roles = Get-AzureADMSPrivilegedRoleDefinition -ProviderId AzureResources -ResourceId $Resource.Id

#####################################################################################

# Declare Role settings

$settingaes = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingaes.RuleIdentifier = "ExpirationRule"
$settingaes.Setting = '{"permanentAssignment":true,"maximumGrantPeriodInMinutes":525600}'
$settingaes2 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingaes2.RuleIdentifier = "AttributeConditionRule"
$settingaes2.Setting = '{"condition":null,"conditionVersion":null,"conditionDescription":null,"enableEnforcement":false}'
$settingaes3 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingaes3.RuleIdentifier = "MfaRule"
$settingaes3.Setting = '{"required":true}'

$settingams = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingams.RuleIdentifier = "ExpirationRule"
$settingams.Setting = '{"permanentAssignment":true,"maximumGrantPeriodInMinutes":259200}'
$settingams2 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingams2.RuleIdentifier = "MfaRule"
$settingams2.Setting = '{"mfaRequired":true}'
$settingams3 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingams3.RuleIdentifier = "JustificationRule"
$settingams3.Setting = '{"required":true}'
$settingams4 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingams4.RuleIdentifier = "AttributeConditionRule"
$settingams4.Setting = '{"condition":null,"conditionVersion":null,"conditionDescription":null,"enableEnforcement":false}'

$settingums = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingums.RuleIdentifier = "ExpirationRule"
$settingums.Setting = '{"permanentAssignment":true,"maximumGrantPeriodInMinutes":660}'
$settingums2 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingums2.RuleIdentifier = "MfaRule"
$settingums2.Setting = '{"mfaRequired":true}'
$settingums3 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingums3.RuleIdentifier = "JustificationRule"
$settingums3.Setting = '{"required":true}'
$settingums4 = New-Object Microsoft.Open.MSGraph.Model.AzureADMSPrivilegedRuleSetting
$settingums4.RuleIdentifier = "TicketingRule"
$settingums4.Setting = '{"ticketingRequired":false}'

#####################################################################################

foreach($Role in $Roles)

    {
    # Get Role Settings
    $RoleSettings = Get-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Filter "ResourceId eq '$($Resource.Id)' and RoleDefinitionId eq '$($Role.Id)'"
    
    if ($Role.DisplayName -eq "Owner")
        {
        Write-Host "$($Role.DisplayName) role will not be modified" -ForegroundColor Yellow
        }

        else 
            {

            # Modify Role Settings
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminEligibleSettings $settingaes3
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminEligibleSettings $settingaes
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminEligibleSettings $settingaes2
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminEligibleSettings $settingaes3

            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminMemberSettings $settingams
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminMemberSettings $settingams2
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminMemberSettings $settingams3
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -AdminMemberSettings $settingams4

            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -UserMemberSettings $settingums
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -UserMemberSettings $settingums2
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -UserMemberSettings $settingums3
            Set-AzureADMSPrivilegedRoleSetting -ProviderId AzureResources -Id $RoleSettings.Id -ResourceId $TenantID -RoleDefinitionId $Role.Id -UserMemberSettings $settingums4

            Write-Host "$($Role.DisplayName) role settings have been modified" -ForegroundColor Green
            }
    }