<#
.SYNOPSIS
    Exports Microsoft Entra ID user authentication methods to CSV using Microsoft Graph.

.DESCRIPTION
    This script exports authentication methods configured for Microsoft Entra ID users
    by querying Microsoft Graph.

    Authentication modes:
    - App-only (certificate-based) authentication (default, recommended for automation)
    - Interactive delegated authentication (-Interactive switch)

    Execution modes:
    - Without parameters:
        * Exports authentication methods for ALL users.
    - With -UserPrincipalName:
        * Exports authentication methods for the specified user only.
        * Prints a formatted PIVOT summary to the console.

    Output:
    - DETAIL report:
        * One row per user per authentication method.
    - PIVOT report:
        * One row per user with authentication methods flattened into columns.

    Additional data included:
    - MethodCount       – number of configured authentication methods
    - Country
    - OfficeLocation
    - AccountEnabled

    Notes:
    - Password authentication is intentionally excluded.
      Having a password does NOT mean a user has MFA configured.
    - Logs execution details and automatically removes logs and reports
      older than 7 days.

.PARAMETER OutputPath
    Optional path for the DETAIL CSV report.
    If not specified, the script generates file names automatically.

.PARAMETER UserPrincipalName
    Optional.
    If specified, the script processes only the given user.

.PARAMETER Interactive
    Optional.
    Uses interactive delegated authentication instead of app-only authentication.
    Intended for ad-hoc admin execution and testing.

.EXAMPLE
    .\EntraID-Get-User-Authentication-Methods.ps1
    Runs in app-only mode and exports authentication methods for all users.

.EXAMPLE
    .\EntraID-Get-User-Authentication-Methods.ps1 -Interactive
    Runs interactively using the signed-in admin account.

.EXAMPLE
    .\EntraID-Get-User-Authentication-Methods.ps1 -UserPrincipalName john.doe@contoso.com -Interactive
    Runs interactively and exports authentication methods for a single user.

.NOTES
    Requirements:
    - Microsoft.Graph PowerShell SDK
    - App-only mode requires:
        * App registration with application permissions:
            - User.Read.All
            - UserAuthenticationMethod.Read.All
        * Certificate-based authentication
    - Interactive mode requires:
        * Delegated permissions for the signed-in user

    Script name:
    EntraID-Get-User-Authentication-Methods.ps1
#>

[CmdletBinding()]
param(
    [string]$OutputPath,
    [string]$UserPrincipalName,
    [switch]$Interactive
)

# ============================================================
# CONFIGURATION (REPLACE WITH YOUR VALUES)
# ============================================================

$AppId                 = "<APP_ID>"
$TenantId              = "<TENANT_ID>"
$CertificateThumbprint = "<CERTIFICATE_THUMBPRINT>"

$BasePath        = ".\"
$LogDirectory    = Join-Path $BasePath "Logs"
$ReportDirectory = Join-Path $BasePath "Reports"

# ============================================================
# INITIALIZATION
# ============================================================

foreach ($dir in @($BasePath, $LogDirectory, $ReportDirectory)) {
    if (-not (Test-Path $dir)) {
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }
}

if (-not $OutputPath) {
    $timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
    $OutputPath = Join-Path $ReportDirectory ("AuthMethods_{0}.csv" -f $timestamp)
}

$PivotOutputPath = $OutputPath -replace '\.csv$', '_Pivot.csv'

# ============================================================
# LOGGING
# ============================================================

$LogFile = Join-Path $LogDirectory ("AuthMethods_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet("INFO","WARN","ERROR","DEBUG")]
        [string]$Level = "INFO"
    )

    $entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    # console coloring (optional but nice)
    switch ($Level) {
        "INFO"  { Write-Host $entry }
        "WARN"  { Write-Host $entry -ForegroundColor Yellow }
        "ERROR" { Write-Host $entry -ForegroundColor Red }
        "DEBUG" { Write-Host $entry -ForegroundColor DarkGray }
    }

    Add-Content -Path $LogFile -Value $entry
}

# Rotate logs & reports (7 days)
$cutoff = (Get-Date).AddDays(-7)
Get-ChildItem $LogDirectory -Filter *.log -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -lt $cutoff |
    Remove-Item -Force -ErrorAction SilentlyContinue

Get-ChildItem $ReportDirectory -Filter *.csv -ErrorAction SilentlyContinue |
    Where-Object LastWriteTime -lt $cutoff |
    Remove-Item -Force -ErrorAction SilentlyContinue

# ============================================================
# CONNECT TO MICROSOFT GRAPH
# ============================================================

function Connect-ToGraph {
    param([switch]$Interactive)

    # Always start with a clean context
    Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null

    if ($Interactive) {
        Write-Log -Message "Connecting to Microsoft Graph using INTERACTIVE authentication." -Level "INFO"
        Connect-MgGraph `
            -Scopes "User.Read.All","UserAuthenticationMethod.Read.All" `
            -NoWelcome
    }
    else {
        Write-Log -Message "Connecting to Microsoft Graph using APP-ONLY (certificate-based) authentication." -Level "INFO"
        Connect-MgGraph `
            -ClientId $AppId `
            -TenantId $TenantId `
            -CertificateThumbprint $CertificateThumbprint `
            -NoWelcome
    }

    $ctx = Get-MgContext
    Write-Log -Message ("Connected to tenant {0} as {1}" -f $ctx.TenantId, $ctx.Account) -Level "INFO"
}

# ✅ This was missing in your version
Connect-ToGraph -Interactive:$Interactive

# ============================================================
# GET USERS
# ============================================================

try {
    if ($UserPrincipalName) {
        $users = @(Get-MgUser -UserId $UserPrincipalName -Property id,displayName,userPrincipalName,accountEnabled,country,officeLocation -ErrorAction Stop)
    }
    else {
        $users = Get-MgUser -All -Property id,displayName,userPrincipalName,accountEnabled,country,officeLocation -ErrorAction Stop
    }
}
catch {
    Write-Log -Message "Failed to retrieve users: $($_.Exception.Message)" -Level "ERROR"
    throw
}

Write-Log -Message ("Users to process: {0}" -f $users.Count) -Level "INFO"

# ============================================================
# COLLECT AUTH METHODS (DETAIL + PIVOT)
# ============================================================

$detailReport = @()
$pivotReport  = @()

foreach ($u in $users) {

    Write-Log -Message ("Processing user: {0}" -f $u.UserPrincipalName) -Level "DEBUG"

    try {
        $methods = Get-MgUserAuthenticationMethod -UserId $u.Id -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Failed to read auth methods for $($u.UserPrincipalName): $($_.Exception.Message)" -Level "WARN"
        $methods = @()
    }

    # Exclude password auth method
    if ($methods) {
        $methods = $methods | Where-Object {
            $_.AdditionalProperties.'@odata.type' -ne '#microsoft.graph.passwordAuthenticationMethod'
        }
    }

    $methodCount = if ($methods) { $methods.Count } else { 0 }

    # Build PIVOT row (one per user)
    $pivotRow = [ordered]@{
        UserDisplayName   = $u.DisplayName
        UserPrincipalName = $u.UserPrincipalName
        Country           = $u.Country
        OfficeLocation    = $u.OfficeLocation
        AccountEnabled    = $u.AccountEnabled
        Email             = $null
        Phone             = $null
        Authenticator     = $null
        PasswordlessAuth  = $null
        FIDO2             = $null
        WHfB              = $null
        SoftwareOATH      = $null
        TAP               = $null
        Passkey           = $null
        Other             = $null
        MethodCount       = $methodCount
    }

    if (-not $methods -or $methods.Count -eq 0) {
        $detailReport += [PSCustomObject]@{
            UserDisplayName   = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            Country           = $u.Country
            OfficeLocation    = $u.OfficeLocation
            AccountEnabled    = $u.AccountEnabled
            MethodType        = "None"
            MethodDetail      = $null
            MethodCount       = 0
        }

        $pivotReport += [PSCustomObject]$pivotRow
        continue
    }

    foreach ($m in $methods) {
        $ap = $m.AdditionalProperties
        $odataType = $ap.'@odata.type'

        $type  = $odataType -replace '#microsoft.graph.', ''
        $value = $ap.displayName

        switch ($odataType) {
            '#microsoft.graph.emailAuthenticationMethod' {
                $type  = 'Email'
                $value = $ap.emailAddress
                if ($value) { $pivotRow.Email = ($pivotRow.Email, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.phoneAuthenticationMethod' {
                $type  = 'Phone'
                $value = "{0}: {1}" -f $ap.phoneType, $ap.phoneNumber
                if ($value) { $pivotRow.Phone = ($pivotRow.Phone, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.microsoftAuthenticatorAuthenticationMethod' {
                $type  = 'Microsoft Authenticator'
                $value = $ap.displayName
                if ($value) { $pivotRow.Authenticator = ($pivotRow.Authenticator, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.passwordlessMicrosoftAuthenticatorAuthenticationMethod' {
                $type  = 'Passwordless Authenticator'
                $value = $ap.displayName
                if ($value) { $pivotRow.PasswordlessAuth = ($pivotRow.PasswordlessAuth, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.fido2AuthenticationMethod' {
                $type  = 'FIDO2'
                $value = $ap.model
                if ($value) { $pivotRow.FIDO2 = ($pivotRow.FIDO2, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.windowsHelloForBusinessAuthenticationMethod' {
                $type  = 'Windows Hello for Business'
                $value = $ap.displayName
                if ($value) { $pivotRow.WHfB = ($pivotRow.WHfB, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.softwareOathAuthenticationMethod' {
                $type  = 'Software OATH'
                $value = $ap.displayName
                if ($value) { $pivotRow.SoftwareOATH = ($pivotRow.SoftwareOATH, $value | Where-Object { $_ }) -join '; ' }
            }

            '#microsoft.graph.temporaryAccessPassAuthenticationMethod' {
                $type  = 'Temporary Access Pass'
                $value = 'TAP present'
                $pivotRow.TAP = 'Yes'
            }

            '#microsoft.graph.passkeyAuthenticationMethod' {
                $type  = 'Passkey'
                $value = $ap.displayName
                if ($value) { $pivotRow.Passkey = ($pivotRow.Passkey, $value | Where-Object { $_ }) -join '; ' }
            }

            default {
                $type  = "Other ($odataType)"
                $value = $ap.displayName
                $otherVal = if ($value) { "[$odataType] $value" } else { $odataType }
                $pivotRow.Other = ($pivotRow.Other, $otherVal | Where-Object { $_ }) -join '; '
            }
        }

        $detailReport += [PSCustomObject]@{
            UserDisplayName   = $u.DisplayName
            UserPrincipalName = $u.UserPrincipalName
            Country           = $u.Country
            OfficeLocation    = $u.OfficeLocation
            AccountEnabled    = $u.AccountEnabled
            MethodType        = $type
            MethodDetail      = $value
            MethodCount       = $methodCount
        }
    }

    $pivotReport += [PSCustomObject]$pivotRow
}

# ============================================================
# EXPORT
# ============================================================

$detailReport | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
Write-Log -Message "DETAIL report exported: $OutputPath" -Level "INFO"

$pivotReport | Export-Csv -Path $PivotOutputPath -NoTypeInformation -Encoding UTF8
Write-Log -Message "PIVOT report exported: $PivotOutputPath" -Level "INFO"

# Optional: show PIVOT nicely for single-user mode
if ($UserPrincipalName) {
    Write-Host ""
    Write-Host "Authentication methods (PIVOT) for: $UserPrincipalName" -ForegroundColor Cyan
    $pivotReport | Select `
    UserDisplayName,
    UserPrincipalName,
    Country,
    OfficeLocation,
    AccountEnabled,
    Email,
    Phone,
    Authenticator,
    PasswordlessAuth,
    FIDO2,
    WHfB,
    SoftwareOATH,
    TAP,
    Passkey,
    Other,
    MethodCount | Format-List
}

Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
Write-Log -Message "Script finished." -Level "INFO"

