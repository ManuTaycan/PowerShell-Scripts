<#
.NOTES
    File Name      : NoNetworkReboot-001.ps1
    Author         : ManuTaycan
    Date Created   : 2026.09.05
    Last Modified  : 2026.09.05
    Version        : 1.0.0
    Description    : This script is designed to perform a "ipconfig /renew" if a specified network adapter
                     is not connected to the network. If it fails to renew the IP address, it will initiate a system reboot.
                     It will loop until there i a network connection or the script is manually stopped.
                     The script will write logs and it will habe specific parameters to customize the behavior of the script.

.SYNOPSIS
    1. Parameters
        -AdapterName: The name of the network adapter to check for connectivity.
        -LogFilePath: The path where the log file will be created.
        
    2. Steps:
        - Check if the specified network adapter is connected to the network.
        - If yes, exit the script. If not, log the event and attempt to renew the IP address using "ipconfig /renew".
        - If the renewal fails, initiate a system reboot after logging the event.
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$AdapterName,

    [Parameter(Mandatory=$false)]
    [string]$LogFilePath
)

### --- Logging Function --- ###
$standardLogFilePath = "C:\Admin\Logs\NoNetworkReboot\NoNetworkReboot-001.log"

function Write-Log {
    param (
        [string]$Message,
        [string]$TargetFilePath = $LogFilePath
    )

    # Standardpfad verwenden, falls kein benutzerdefinierter Pfad angegeben wurde
    if ([string]::IsNullOrWhiteSpace($TargetFilePath)) {
        $TargetFilePath = $standardLogFilePath
    }

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp - $Message"

    # Ordnerstruktur erstellen, falls sie noch nicht existiert
    $logFolder = Split-Path -Path $TargetFilePath -Parent
    if (-not (Test-Path -Path $logFolder)) {
        New-Item -ItemType Directory -Path $logFolder -Force | Out-Null
    }

    # Logeintrag schreiben (Datei wird automatisch erstellt, falls sie nicht existiert)
    Add-Content -Path $TargetFilePath -Value $logMessage
}


### --- Check Network Adapter Connectivity --- ###
function Test-NetworkAdapterConnectivity {
    param (
        [string]$AdapterName
    )
    $adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
    if ($null -eq $adapter) {
        Write-Log "Network adapter '$AdapterName' not found."
        return $false
    }
    return $adapter.Status -eq 'Up'
}


### --- remediate no network connection --- ###
function Set-NoNetworkConnection {
    param (
        [string]$AdapterName
    )
    Write-Log "Attempting to renew IP address for adapter '$AdapterName'."
    ipconfig /renew | Out-Null
    Start-Sleep -Seconds 7  # Wait for a few seconds to allow the renewal process to complete

    if (Test-NetworkAdapterConnectivity -AdapterName $AdapterName) {
        Write-Log "IP address renewed successfully for adapter '$AdapterName'."
        return $true
    } else {
        Write-Log "Failed to renew IP address for adapter '$AdapterName'. Initiating system reboot."
        Start-Sleep -Seconds 2  # Optional: Wait for a few seconds before rebooting
        Restart-Computer -Force
        return $false
    }
}


### --- Main Script Logic --- ###
while ($true) {
    if (Test-NetworkAdapterConnectivity -AdapterName $AdapterName) {
        Write-Log "Network adapter '$AdapterName' is connected. Exiting script."
        break
    } else {
        Write-Log "Network adapter '$AdapterName' is not connected. Attempting to remediate."
        Set-NoNetworkConnection -AdapterName $AdapterName
    }
}