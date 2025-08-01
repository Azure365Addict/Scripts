<#
.SYNOPSIS
    Finds mailbox folders matching a specified name and reports folder statistics.

.DESCRIPTION
    Connects to Exchange Online, searches a given mailbox for folders containing a specific keyword 
    (e.g., "Deleted" or "Marketing") in their path, and displays folder details along with a total item count.

.PARAMETER Mailbox
    The SMTP address of the target mailbox (e.g., user@contoso.com)

.PARAMETER FolderName
    A string to match against the folder path (e.g., "Deleted", "Marketing", etc.)

.EXAMPLE
    ./Exchange-Find-Mailbox-Folder.ps1 -Mailbox "user@contoso.com" -FolderName "Deleted"

.NOTES
    Requirements:
    - ExchangeOnlineManagement module
    
    For full details, see:

    https://azure365addict.com/2025/08/01/investigating-missing-mailbox-folders-in-exchange-online-with-powershell/
#>

param (
    [Parameter(Mandatory = $true)]
    [string]$Mailbox,

    [Parameter(Mandatory = $true)]
    [string]$FolderName
)

# Connect to Exchange Online
try {
    Connect-ExchangeOnline -ErrorAction Stop
} catch {
    Write-Error "Failed to connect to Exchange Online. $_"
    return
}

# Get matching folders
$folders = Get-MailboxFolderStatistics -Identity $Mailbox |
    Where-Object { $_.FolderPath -like "*$FolderName*" }

# Display folder stats
if ($folders.Count -eq 0) {
    Write-Host "No folders found matching '$FolderName' in mailbox $Mailbox." -ForegroundColor Yellow
} else {
    Write-Host "`nMatching folders in mailbox $Mailbox :`n" -ForegroundColor Cyan
    $folders | Select FolderPath, ItemsInFolder, FolderType | Format-Table -AutoSize

    # Total item count
    $total = ($folders | Measure-Object -Property ItemsInFolder -Sum).Sum
    Write-Host "`nTotal items in matching folders: $total`n" -ForegroundColor Green
}

# Disconnect session
Disconnect-ExchangeOnline -Confirm:$false
