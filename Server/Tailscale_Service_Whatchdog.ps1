#Requires -Version 5.1
<#.SYNOPSIS
    Monitors the Tailscale service and restarts it when it goes offline.
<#.DESCRIPTION
    This script monitors the Tailscale service and restarts it if it is not running.
<#.EXAMPLE
    .\Tailscale_Service_Whatchdog.ps1
    .\Tailscale_Service_Whatchdog.ps1 -Setup
    .\Tailscale_Service_Whatchdog.ps1 -Uninstall
    .\Tailscale_Service_Whatchdog.ps1 -Help
.NOTE
    Administrator rights are required to run this script.
    requires PowerShell 5.1 or higher.
    requires the Tailscale service to be installed.

.AUTHOR
    ManuTaycan

.DATE
    2024-06-10
#>

param(
    [switch]$Setup,
    [switch]$Uninstall,
    [Alias('h', '?')]
    [switch]$Help
)
##################################################
### --- Administrative Check
##################################################
if (-not (Get-IsAdmin)) {
    Write-Host (get-date) "This script requires administrative privileges. Please run it as an administrator."
    exit 1
}



##################################################
### --- Monitoring and Logging Settings
##################################################
$ScriptName = 'Tailscale_Service_Whatchdog.ps1'
$scriptPath = $MyInvocation.MyCommand.Path
$TaskName   = 'Tailscale_Service_Whatchdog'

start-transcript -path "$env:ProgramData\Tailscale_Service_Whatchdog.log" -append
write-host (get-date) "Starting $ScriptName..."



##################################################
### --- Whathdog Function
##################################################
function Get-Tailscale {
    try {
        Get-Service -Name "Tailscale" | Select-Object -Property Name, Status | ForEach-Object {
            if ($_.Status -ne 'Running') {
                Write-Host (get-date) "Tailscale service is not running. Attempting to start it..."
                try {
                    Start-Service -Name "Tailscale" -ErrorAction Stop
                    Write-Host (get-date) "Tailscale service started successfully."
                }
                catch {
                    Write-Host (get-date) "Failed to start Tailscale service. Error: $_"
                }
            }
            else {
                Write-Host "Tailscale service is running."
            }
        }
    }
    catch {
        write-host (get-date) "Failed to get Tailscale service status. Error: $_"
    }
    
}



##################################################
### --- Scheduled Task Management
##################################################
function Install-Task {
    $action = New-ScheduledTaskAction -Execute 'PowerShell.exe' -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours 2) -RepetitionDuration ([TimeSpan]::MaxValue)
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -RunLevel Highest -Force
    Write-Host (get-date) "Scheduled task '$TaskName' installed successfully."
}



##################################################
### --- Uninstall Scheduled Task
##################################################
function Uninstall-Task {
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host (get-date) "Scheduled task '$TaskName' uninstalled successfully."
    }
    catch {
        Write-Host (get-date) "Failed to uninstall scheduled task '$TaskName'. Error: $_"
    }
}


###################################################
### --- Help Function
###################################################
function Get-Help {
    Write-Host "Usage: .\$ScriptName [-Setup] [-Uninstall] [-Help]"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -Setup      : Installs the scheduled task to monitor the Tailscale service."
    Write-Host "  -Uninstall  : Uninstalls the scheduled task."
    Write-Host "  -Help       : Displays this help message."
    Write-Host ""
    Write-Host "This script monitors the Tailscale service and restarts it if it is not running. It requires administrative privileges to run."
    Write-Host "YOU NEED TO RUN THIS SCRIPT WITH THE -Setup OPTION ONCE TO INSTALL THE SCHEDULED TASK. AFTER THAT, IT WILL RUN AUTOMATICALLY EVERY 2 HOURS."
    Write-Host ""
    Write-Host "Log file is located at: $env:ProgramData\Tailscale_Service_Whatchdog.log"
    write-host ""
    Write-Host "EXAMPLES:"
    Write-Host "  .\$ScriptName -Setup      : Installs the scheduled task"
    Write-Host "  .\$ScriptName -Uninstall  : Uninstalls the scheduled task"
    Write-Host "  .\$ScriptName -Help       : Displays this help message"   
}



##################################################
### --- Main Script Logic
##################################################
if ($Help) {
    Get-Help
    exit 0
}

if ($Setup) {
    Install-Task
    Get-Tailscale
    exit 0
}

if ($Uninstall) {
    Uninstall-Task
    exit 0
}

Get-Tailscale

stop-transcript