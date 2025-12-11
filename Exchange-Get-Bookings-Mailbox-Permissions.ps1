<#
.SYNOPSIS
    Generates a permissions report for all Bookings Scheduling Mailboxes in Exchange Online.

.DESCRIPTION
    This script scans all mailboxes of type 'SchedulingMailbox' and retrieves their mailbox 
    permissions (excluding system accounts such as NT AUTHORITY\SELF and SIDs). 
    For mailboxes with no explicit permissions, the script returns a row with empty User/Rights 
    fields so that orphaned Booking pages can be identified easily.

.EXAMPLE
    .\Exchange-Get-Bookings-Mailbox-Permissions.ps1

    Lists all Scheduling mailboxes along with assigned permissions.

.EXAMPLE
    .\Exchange-Get-Bookings-Mailbox-Permissions.ps1 | Export-Csv "BookingsMailboxes.csv" -NoTypeInformation

    Exports the results into a CSV file for further analysis.

.NOTES
    Requires ExchangeOnlineManagement module.

.LINK
    https://azure365addict.com/2025/12/11/why-your-microsoft-bookings-page-suddenly-has-no-owner-and-how-to-fix-it-with-powershell/
#>

$results = Get-Mailbox -RecipientTypeDetails SchedulingMailbox | ForEach-Object {
    $mbx = $_

    # Retrieve mailbox permissions while excluding system and inherited entries
    $perms = Get-MailboxPermission -Identity $mbx.PrimarySmtpAddress | Where-Object {
        $_.User -notlike "NT AUTHORITY\SELF" -and
        $_.User -notlike "S-1-5-21*" -and      # Exclude SID-style entries
        $_.AccessRights -ne "None"
    }

    if (-not $perms) {
        # Mailbox has no delegated permissions – likely orphaned
        [PSCustomObject]@{
            DisplayName        = $mbx.DisplayName
            PrimarySmtpAddress = $mbx.PrimarySmtpAddress
            WhenCreated        = $mbx.WhenCreated
            IsInactiveMailbox  = $mbx.IsInactiveMailbox
            User               = $null
            AccessRights       = $null
        }
    }
    else {
        # Output one row per delegated user/permission set
        $perms | ForEach-Object {
            [PSCustomObject]@{
                DisplayName        = $mbx.DisplayName
                PrimarySmtpAddress = $mbx.PrimarySmtpAddress
                WhenCreated        = $mbx.WhenCreated
                IsInactiveMailbox  = $mbx.IsInactiveMailbox
                User               = $_.User.ToString()
                AccessRights       = ($_.AccessRights -join ',')
            }
        }
    }
}

$results | Format-Table
# Optional: export to CSV

# $results | Export-Csv "Bookings-Scheduling-Mailboxes.csv" -NoTypeInformation -Encoding UTF8

