<#
.SYNOPSIS
    Checks shared mailbox permissions in Exchange Online.

.DESCRIPTION
    This script allows you to:
    1. Enter a shared mailbox email address and list users who have Full Access, Send As, or Send on Behalf permissions.
    2. Enter a user email address and find all shared mailboxes where the user has Full Access, Send As, or Send on Behalf permissions.

.PARAMETER Mode
    Defines the search mode: 
    - "Mailbox" to check permissions on a specific shared mailbox
    - "User" to check which mailboxes a user has access to

.PARAMETER Identity
    The email address of the mailbox or user, depending on the selected mode.

.EXAMPLE
    ./Exchange-Check-Mailbox-Permissions.ps1 -Mode "Mailbox" -Identity "shared@contoso.com"
    Lists all users who have Full Access, Send As, or Send on Behalf permissions to the shared mailbox.

.EXAMPLE
    ./Exchange-Check-Mailbox-Permissions.ps1 -Mode "User" -Identity "user@contoso.com"
    Lists all shared mailboxes where the user has Full Access, Send As, or Send on Behalf rights.

.REQUIREMENTS
    - Exchange Online PowerShell (Connect-ExchangeOnline)
    - Permissions to run Get-Mailbox, Get-MailboxPermission, Get-RecipientPermission

.LINK
    https://azure365addict.com/2025/08/28/checking-shared-mailbox-permissions-in-exchange-online-with-powershell/

#>

<#
.SYNOPSIS
Check shared mailbox permissions in Exchange Online.

.DESCRIPTION
Two modes:
- Mailbox: who has FullAccess / SendAs / SendOnBehalf on a shared mailbox.
- User:   which shared mailboxes a user has FullAccess / SendAs / SendOnBehalf.

.REQUIREMENTS
Connect-ExchangeOnline (EXO V3 recommended for Get-EXOMailbox speed).
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Mailbox","User")]
    [string]$Mode,

    [Parameter(Mandatory=$true)]
    [string]$Identity,   # mailbox SMTP in Mailbox mode, user SMTP in User mode

    [switch]$NoProgress  # set this to suppress progress bar
)

# Ensure progress is visible unless suppressed
if (-not $NoProgress) { $global:ProgressPreference = 'Continue' }

function Get-SharedMailboxes {
    Write-Host "Loading shared mailbox list (can take a bit depending on number)..." -ForegroundColor DarkGray
    try {
        if (Get-Command Get-EXOMailbox -ErrorAction SilentlyContinue) {
            # Faster REST cmdlet; include GrantSendOnBehalfTo so we don't re-query later
            return Get-EXOMailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited -Properties GrantSendOnBehalfTo
        } else {
            return Get-Mailbox -RecipientTypeDetails SharedMailbox -ResultSize Unlimited
        }
    } catch {
        throw "Failed fetching shared mailboxes: $($_.Exception.Message)"
    }
}

function Get-MailboxPermissionsForMailbox {
    param([string]$Mailbox)

    Write-Host "=== Checking permissions for shared mailbox: $Mailbox ===" -ForegroundColor Cyan
    $results = @()

    # Full Access
    $fa = Get-MailboxPermission -Identity $Mailbox -ErrorAction SilentlyContinue |
          Where-Object {($_.AccessRights -contains "FullAccess") -and ($_.IsInherited -eq $false)}
    foreach ($p in $fa) {
        $results += [PSCustomObject]@{
            User       = $p.User
            Permission = "FullAccess"
            Inherited  = $p.IsInherited
        }
    }

    # Send As
    $sa = Get-RecipientPermission -Identity $Mailbox -ErrorAction SilentlyContinue |
          Where-Object {($_.AccessRights -contains "SendAs")}
    foreach ($p in $sa) {
        $results += [PSCustomObject]@{
            User       = $p.Trustee
            Permission = "SendAs"
            Inherited  = $null
        }
    }

    # Send on Behalf
    $mbxObj = Get-Mailbox -Identity $Mailbox -ErrorAction SilentlyContinue
    $sob = $mbxObj.GrantSendOnBehalfTo
    foreach ($delegate in $sob) {
        $results += [PSCustomObject]@{
            User       = $delegate
            Permission = "SendOnBehalf"
            Inherited  = $null
        }
    }

    if ($results) {
        $results | Sort-Object Permission, User | Format-Table -AutoSize
    } else {
        Write-Host "No permissions found." -ForegroundColor DarkGray
    }
}

function Get-MailboxPermissionsForUser {
    param([string]$User)

    Write-Host "=== Checking shared mailboxes for user: $User ===" -ForegroundColor Cyan

    $results   = @()
    $allShared = Get-SharedMailboxes
    $count     = $allShared.Count
    if ($count -eq 0) { Write-Host "No shared mailboxes found." -ForegroundColor DarkGray; return }

    $i = 0
    foreach ($mbx in $allShared) {
        $i++
        if (-not $NoProgress) {
            Write-Progress -Activity "Scanning shared mailboxes..." `
                -Status ("Checking {0} of {1}: {2}" -f $i, $count, $mbx.PrimarySmtpAddress) `
                -PercentComplete ([int](($i / $count) * 100))
        }

        $smtp = $mbx.PrimarySmtpAddress

        # Full Access
        $permFA = Get-MailboxPermission -Identity $smtp -ErrorAction SilentlyContinue |
                  Where-Object {($_.AccessRights -contains "FullAccess") -and ($_.IsInherited -eq $false) -and ($_.User -like $User)}
        if ($permFA) {
            $results += [PSCustomObject]@{Mailbox=$smtp; Permission="FullAccess"}
        }

        # Send As
        $permSA = Get-RecipientPermission -Identity $smtp -ErrorAction SilentlyContinue |
                  Where-Object {($_.AccessRights -contains "SendAs") -and ($_.Trustee -like $User)}
        if ($permSA) {
            $results += [PSCustomObject]@{Mailbox=$smtp; Permission="SendAs"}
        }

        # Send on Behalf
        # Note: If we used Get-EXOMailbox earlier, GrantSendOnBehalfTo is already populated.
        $delegates = $mbx.GrantSendOnBehalfTo
        if ($delegates) {
            # Try to match by SMTP as well (resolve each delegate to recipient once)
            $match = $false
            foreach ($d in $delegates) {
                try {
                    $rec = Get-Recipient -Identity $d -ErrorAction Stop
                    if ($rec.PrimarySmtpAddress -and ($rec.PrimarySmtpAddress.ToString().ToLower() -eq $User.ToLower())) { $match = $true; break }
                    if ($rec.Name -and ($rec.Name.ToLower() -eq $User.ToLower())) { $match = $true; break }
                } catch {
                    # fallback: string compare
                    if ($d.ToString().ToLower() -eq $User.ToLower()) { $match = $true; break }
                }
            }
            if ($match) {
                $results += [PSCustomObject]@{Mailbox=$smtp; Permission="SendOnBehalf"}
            }
        }
    }

    if (-not $NoProgress) { Write-Progress -Activity "Scanning shared mailboxes..." -Completed }

    if ($results) {
        $results | Sort-Object Permission, Mailbox | Format-Table -AutoSize
        Write-Host "`nFound $($results.Count) permission entries for user $User." -ForegroundColor Green
    } else {
        Write-Host "User has no explicit FullAccess / SendAs / SendOnBehalf on shared mailboxes." -ForegroundColor DarkGray
    }
}

# MAIN
if ($Mode -eq "Mailbox") {
    Get-MailboxPermissionsForMailbox -Mailbox $Identity
} else {
    Get-MailboxPermissionsForUser -User $Identity
}

