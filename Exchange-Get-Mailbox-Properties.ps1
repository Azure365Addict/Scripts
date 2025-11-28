<#
.SYNOPSIS
    Generates a mailbox properties report in Exchange Online for user, shared, or specific mailbox.

.DESCRIPTION
    This script connects to Exchange Online using either interactive login or app-only certificate-based authentication.
    It collects detailed information on selected mailboxes, including size, quota usage, archive status, forwarding,
    hold settings, and more. Results are exported to a CSV file, and logs are saved locally.

.PARAMETER UserMailbox
    Include all User mailboxes in the report.

.PARAMETER SharedMailbox
    Include all Shared mailboxes in the report.

.PARAMETER UserUPN
    Report only for the specified user mailbox (overrides other switches).

.PARAMETER UseCertAuth
    Use certificate-based app-only authentication instead of interactive login.

.EXAMPLE
    .\Exchange-Get-MailboxPropertiesReport.ps1
    Runs the script for both User and Shared mailboxes using interactive login.

.EXAMPLE
    .\Exchange-Get-MailboxPropertiesReport.ps1 -UserUPN "john.doe@contoso.com"
    Runs the report only for the specified mailbox.

.EXAMPLE
    .\Exchange-Get-MailboxPropertiesReport.ps1 -UserMailbox -UseCertAuth
    Runs the script for all User mailboxes using app-only authentication.

.REQUIREMENTS
    - ExchangeOnlineManagement module
    - If using cert-based auth: App registration + certificate + necessary Exchange permissions

.LINK
    https://azure365addict.com/
#>

param (
    [switch]$UserMailbox,
    [switch]$SharedMailbox,
    [switch]$UseCertAuth,
    [string]$UserUPN
)

# Prepare paths
$LogsDir = ".\Logs"
$ReportsDir = ".\Reports"
New-Item -ItemType Directory -Path $LogsDir -Force | Out-Null
New-Item -ItemType Directory -Path $ReportsDir -Force | Out-Null

# Start transcript
Start-Transcript -Path "$LogsDir\MailboxesPropertiesReportLog_$((Get-Date -format yyyy-MM-dd-HH-mm)).txt"

function Log-Event {
    param ([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "$timestamp - $Message"
}

# Clean old files
$threshold = (Get-Date).AddDays(-30)
Get-ChildItem -Path $ReportsDir -File | Where-Object { $_.LastWriteTime -lt $threshold } | Remove-Item
Get-ChildItem -Path $LogsDir -File | Where-Object { $_.LastWriteTime -lt $threshold } | Remove-Item
Log-Event "Old logs and reports removed."

# Connect
if ($UseCertAuth) {
    $AppId = "<YOUR_APP_ID>"  # <- REPLACE
    $CertificateThumbprint = "<YOUR_CERT_THUMBPRINT>"  # <- REPLACE
    $Organization = "yourtenant.onmicrosoft.com"  # <- REPLACE

    Connect-ExchangeOnline -AppId $AppId -CertificateThumbprint $CertificateThumbprint -Organization $Organization -ShowBanner:$false
    Log-Event "Connected using certificate."
} else {
    Connect-ExchangeOnline -ShowBanner:$false
    Log-Event "Connected using interactive user login."
}

# Determine target mailboxes
$Mailboxes = @()
$reportLabel = ""

if ($UserUPN) {
    try {
        $Mailbox = Get-Mailbox -Identity $UserUPN -ErrorAction Stop
        Log-Event "Retrieved mailbox: $($Mailbox.PrimarySMTPAddress)"
        $Mailboxes += $Mailbox
        $reportLabel = "SingleUser_$($Mailbox.Alias)"
    } catch {
        Log-Event "ERROR: Could not find mailbox $UserUPN"
        Stop-Transcript
        return
    }
} else {
    $MailboxTypes = @()

    if ($UserMailbox -and $SharedMailbox) {
        $MailboxTypes = "UserMailbox", "SharedMailbox"
        $reportLabel = "UserAndShared"
    } elseif ($UserMailbox) {
        $MailboxTypes = "UserMailbox"
        $reportLabel = "User"
    } elseif ($SharedMailbox) {
        $MailboxTypes = "SharedMailbox"
        $reportLabel = "Shared"
    } else {
        $MailboxTypes = "UserMailbox", "SharedMailbox"
        $reportLabel = "UserAndShared"
        Log-Event "No mailbox type switch provided. Defaulting to UserMailbox + SharedMailbox."
    }

    $Mailboxes = Get-Mailbox -ResultSize Unlimited -RecipientTypeDetails $MailboxTypes
    Log-Event "Retrieved $($Mailboxes.Count) $reportLabel mailboxes."
}

# Output
$OutputCSV = "$ReportsDir\MailboxesPropertiesReport_$reportLabel`_$((Get-Date -format yyyy-MM-dd-HH-mm)).csv"

$ConfirmPreference = 'None'

foreach ($Mailbox in $Mailboxes) {
        try {
        $LastEmailSentDate = (Get-MailboxFolderStatistics -Identity $Mailbox.Guid -IncludeOldestAndNewestItems -ResultSize Unlimited | Where-Object {$_.FolderType -eq "SentItems"}).NewestItemReceivedDate.ToString("dd.MM.yyyy")
    } catch {
        $LastEmailSentDate= $null 
    }

    $Stats = Get-MailboxStatistics -Identity $Mailbox.Guid
    $ArchSize = ""
    if ($Mailbox.ArchiveStatus -eq "Active") {
        $ArchStats = Get-MailboxStatistics -Identity $Mailbox.Guid -Archive
        $ArchSize = $ArchStats.TotalItemSize.Value.ToString().Split("(")[0]
    }

    $MBSize = $Stats.TotalItemSize.Value
    $Usage = $MBSize.ToString().Split("(")[0]

    # % usage
    $quotaBytes = [long]($Mailbox.ProhibitSendQuota.ToString() -replace ".*\((.*?) bytes.*", '$1' -replace ",", "")
    $sizeBytes = [long]($MBSize.ToString() -replace ".*\((.*?) bytes.*", '$1' -replace ",", "")
    $percentUsed = if ($quotaBytes -gt 0) { [Math]::Round(($sizeBytes / $quotaBytes) * 100, 2) } else { 0 }
    $percentText = "$percentUsed%"

    $InPlaceHold = if ($Mailbox.InPlaceHolds.Count -gt 0) { "TRUE" } else { "FALSE" }
    $ForwardingAddress = if ($Mailbox.ForwardingAddress) { $Mailbox.ForwardingAddress } else { "-" }
    $ForwardingSMTP = if ($Mailbox.ForwardingSMTPAddress) { $Mailbox.ForwardingSMTPAddress } else { "-" }

    $ExportResult = [pscustomobject]@{
        UserPrincipalName        = $Mailbox.UserPrincipalName
        DisplayName              = $Mailbox.DisplayName
        PrimarySMTPAddress       = $Mailbox.PrimarySMTPAddress
        Alias                    = $Mailbox.Alias
        RecipientType            = $Mailbox.RecipientTypeDetails
        UsageLocation            = $Mailbox.UsageLocation
        Office                   = $Mailbox.Office
        CreatedDate              = $Mailbox.WhenMailboxCreated.ToString("dd.MM.yyyy")
        LastEmailSentDate        = $LastEmailSentDate
        MailboxUsage             = $Usage
        MailboxQuota             = $Mailbox.ProhibitSendQuota.ToString().Split("(")[0]
        PercentageUsed           = $percentText
        IssueWarningQuota        = $Mailbox.IssueWarningQuota.ToString().Split("(")[0]
        IsLicensed               = $Mailbox.SkuAssigned
        ADSynced                 = $Mailbox.IsDirSynced
        ArchiveStatus            = $Mailbox.ArchiveStatus
        ArchiveSize              = $ArchSize
        HiddenFromAddressList    = $Mailbox.HiddenFromAddressListsEnabled
        AuditEnabled             = $Mailbox.AuditEnabled
        ForwardingAddress        = $ForwardingAddress
        ForwardingSMTPAddress    = $ForwardingSMTP
        LitigationHold           = $Mailbox.LitigationHoldEnabled
        InPlaceHold              = $InPlaceHold
        RetentionHold            = $Mailbox.RetentionHoldEnabled
        AccountDisabled          = $Mailbox.AccountDisabled
    }

    $ExportResult | Export-Csv -Path $OutputCSV -NoTypeInformation -Append -Delimiter ";"
    Log-Event "Processed $($Mailbox.UserPrincipalName)"
}

Log-Event "Report generated: $OutputCSV"
Disconnect-ExchangeOnline -Confirm:$false
Stop-Transcript
