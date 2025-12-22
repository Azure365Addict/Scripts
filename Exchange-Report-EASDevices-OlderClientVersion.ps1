<#
.SYNOPSIS
    Exports a report of Exchange ActiveSync (EAS) mobile devices running an Outlook/EAS client version older than a specified threshold.

.DESCRIPTION
    This script was created as part of an investigation related to Microsoft advisory MC1197103.

    It scans all mobile devices in Exchange Online, filters EAS/ActiveSync clients, and
    outputs devices where the client version is lower than a defined minimum version (default: 16.1).

    The report includes:
    - Mailbox display name + primary SMTP (resolved once per mailbox via cache)
    - Device metadata (model, client type/version, DeviceId)
    - MobileDeviceStatistics details (OS, user agent, sync timestamps)
    - Full device identity string (DeviceIdentity) for follow-up actions

    Output:
    - CSV report (semicolon-delimited by default)
    - Optional console output (top rows)

.PARAMETER MinClientVersion
    Minimum allowed client version. Devices below this version are included in the report.
    Default: 16.1

.PARAMETER OutputPath
    Output CSV path.
    Default: .\EAS_Devices_OlderThan_<MinClientVersion>_Detailed.csv

.PARAMETER Delimiter
    CSV delimiter. Default: ';'

.PARAMETER IncludeNonEas
    If specified, the script does not filter by ClientType (EAS/ActiveSync) and only applies version filtering.
    Useful if you want to validate the dataset.

.PARAMETER Top
    Number of rows to print to the console (in addition to exporting CSV).
    Default: 0 (no console output)

.EXAMPLE
    .\Exchange-Report-EASDevices-OlderClientVersion.ps1

    Exports devices with client version older than 16.1.

.EXAMPLE
    .\Exchange-Report-EASDevices-OlderClientVersion.ps1 -MinClientVersion 16.2 -Top 25

    Exports devices older than 16.2 and prints the top 25 rows to the console.

.NOTES
    Requirements:
    - ExchangeOnlineManagement module
    - Connected session to Exchange Online (Connect-ExchangeOnline)

    The script uses simple in-memory caches to reduce repeated calls:
    - mailbox cache: Identity -> Primary SMTP / Display Name
    - stats cache: device Identity -> Get-MobileDeviceStatistics result

    Script name:
    Exchange-Report-EASDevices-OlderClientVersion.ps1

.LINK
https://azure365addict.com/2025/12/22/reporting-legacy-exchange-activesync-clients-after-mc1197103/
#>

[CmdletBinding()]
param(
    [string]$MinClientVersion = "16.1",
    [string]$OutputPath,
    [string]$Delimiter = ";",
    [switch]$IncludeNonEas,
    [int]$Top = 0
)

# ---------------------------
# Helper: safe version parse
# ---------------------------
function Try-ParseVersion {
    param([string]$Value)

    try {
        return [version]$Value
    }
    catch {
        return $null
    }
}

# ---------------------------
# Build default output path
# ---------------------------
if (-not $OutputPath) {
    $safeVer = $MinClientVersion -replace '[^0-9\.]', '_'
    $OutputPath = ".\EAS_Devices_OlderThan_$safeVer`_Detailed.csv"
}

$minVerObj = Try-ParseVersion $MinClientVersion
if (-not $minVerObj) {
    throw "Invalid -MinClientVersion '$MinClientVersion'. Example valid value: 16.1"
}

# ---------------------------
# Caches
# ---------------------------
$mbxCache   = @{}  # mailboxIdentity -> @{ Smtp=...; Display=... }
$statsCache = @{}  # deviceIdentity  -> stats object (or $null)

Write-Host "Scanning mobile devices (MinClientVersion: $MinClientVersion)..." -ForegroundColor Cyan

$results =
    Get-MobileDevice -ResultSize Unlimited |
    Where-Object {

        # Version must exist and must be parseable
        $_.ClientVersion -and (Try-ParseVersion $_.ClientVersion) -and
        ((Try-ParseVersion $_.ClientVersion) -lt $minVerObj) -and

        # Default: only EAS / ActiveSync
        ($IncludeNonEas -or
            ( $_.ClientType -eq 'EAS' -or $_.ClientType -match 'ActiveSync' )
        )
    } |
    ForEach-Object {

        # Mailbox identity is embedded in the MobileDevice Identity
        $mailbox = ($_.Identity -replace '\\ExchangeActiveSyncDevices\\.*$','')

        if (-not $mbxCache.ContainsKey($mailbox)) {
            try {
                $m = Get-Mailbox -Identity $mailbox -ErrorAction Stop
                $mbxCache[$mailbox] = @{
                    Smtp    = $m.PrimarySmtpAddress.ToString()
                    Display = $m.DisplayName
                }
            }
            catch {
                # If mailbox cannot be resolved, keep whatever identity we have
                $mbxCache[$mailbox] = @{
                    Smtp    = $null
                    Display = $mailbox
                }
            }
        }

        $devId = $_.Identity.ToString()

        if (-not $statsCache.ContainsKey($devId)) {
            try {
                $statsCache[$devId] = Get-MobileDeviceStatistics -Identity $_.Identity -ErrorAction Stop
            }
            catch {
                $statsCache[$devId] = $null
            }
        }

        $s = $statsCache[$devId]

        [pscustomobject]@{
            MailboxDisplayName  = $mbxCache[$mailbox].Display
            PrimarySmtpAddress  = $mbxCache[$mailbox].Smtp
            DeviceId            = $_.DeviceId
            DeviceModel         = $_.DeviceModel
            ClientType          = $_.ClientType
            ClientVersion       = $_.ClientVersion
            DeviceOS            = $s.DeviceOS
            DeviceType          = $s.DeviceType
            DeviceUserAgent     = $s.DeviceUserAgent
            FirstSyncTime       = $s.FirstSyncTime
            LastSuccessSync     = $s.LastSuccessSync
            LastSyncAttemptTime = $s.LastSyncAttemptTime
            DeviceIdentity      = $devId
        }
    }

if (-not $results -or $results.Count -eq 0) {
    Write-Host "No devices found matching the criteria." -ForegroundColor Yellow
    return
}

$results =
    $results |
    Sort-Object PrimarySmtpAddress, MailboxDisplayName, DeviceModel

# Optional console view
if ($Top -gt 0) {
    Write-Host ""
    Write-Host "Top $Top results:" -ForegroundColor Cyan
    $results | Select-Object -First $Top | Format-Table -Wrap
    Write-Host ""
}

# Export
$results |
    Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8 -Delimiter $Delimiter

Write-Host "Report exported to: $OutputPath" -ForegroundColor Green

Write-Host ("Rows exported: {0}" -f $results.Count) -ForegroundColor Green
