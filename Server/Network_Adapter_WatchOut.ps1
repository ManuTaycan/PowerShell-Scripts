#Requires -Version 5.1
<#
.SYNOPSIS
    Monitors a network adapter and runs "ipconfig /renew" when it goes offline.
.DESCRIPTION
    Checks the status of the specified adapter. If it is not "Up", the adapter is
    enabled if necessary and an ipconfig /renew is run for that adapter only.
    Optionally the script can be scheduled (every X hours) via Task Scheduler.

    Administrator rights are only required when the script has to change something
    (repair, -Install, -Remove). A plain status check works without elevation.
.PARAMETER AdapterName
    Name of the adapter to monitor (e.g. "Ethernet").
.PARAMETER Setup
    Interactive wizard: pick an adapter and optionally create a scheduled task.
.PARAMETER Install
    Creates the scheduled task (requires -AdapterName and -IntervalHours).
.PARAMETER IntervalHours
    Interval in hours for the scheduled task (1-168).
.PARAMETER Remove
    Deletes the scheduled task.
.PARAMETER Help
    Shows the help screen.
.EXAMPLE
    .\Network_Adapter_WatchOut.ps1 -AdapterName "Ethernet"
.EXAMPLE
    .\Network_Adapter_WatchOut.ps1 -Setup
.EXAMPLE
    .\Network_Adapter_WatchOut.ps1 -Install -AdapterName "Ethernet" -IntervalHours 1
#>

##############################################
###--- Parameter Definitions
##############################################
param(
    [string]$AdapterName,
    [switch]$Setup,
    [switch]$Install,
    [switch]$Remove,
    [ValidateRange(1, 168)]
    [int]$IntervalHours,
    [Alias('h', '?')]
    [switch]$Help
)

$ScriptName = 'Network_Adapter_WatchOut.ps1'
$TaskName   = 'Network_Adapter_WatchOut'
$LogDir     = Join-Path $env:ProgramData 'NetworkAdapterWatchOut'
$LogFile    = Join-Path $LogDir 'watchout.log'

###############################################
###--- Helper Functions
###############################################
function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('INFO', 'OK', 'WARN', 'ERROR')][string]$Level = 'INFO'
    )
    $line  = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    $color = switch ($Level) { 'OK' { 'Green' } 'WARN' { 'Yellow' } 'ERROR' { 'Red' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -ErrorAction Stop
    } catch { }
}

function Show-Help {
    $w = 72
    $line = '+' + ('-' * ($w - 2)) + '+'
    function Row([string]$text, [string]$color = 'White') {
        $pad = $w - 4 - $text.Length
        if ($pad -lt 0) { $pad = 0 }
        Write-Host '| ' -NoNewline -ForegroundColor DarkCyan
        Write-Host $text -NoNewline -ForegroundColor $color
        Write-Host (' ' * $pad + ' |') -ForegroundColor DarkCyan
    }

    Write-Host ''
    Write-Host $line -ForegroundColor DarkCyan
    Row 'NETWORK ADAPTER WATCHOUT' 'Cyan'
    Row 'Adapter monitoring with automatic "ipconfig /renew"' 'DarkGray'
    Write-Host $line -ForegroundColor DarkCyan
    Row ''
    Row 'DESCRIPTION' 'Yellow'
    Row '  Checks whether a network adapter is online. If it is not, the'
    Row '  adapter is enabled (if disabled) and its IP address is renewed.'
    Row ''
    Row 'USAGE' 'Yellow'
    Row "  .\$ScriptName [options]" 'Green'
    Row ''
    Row 'OPTIONS' 'Yellow'
    Row '  -AdapterName <name>     Adapter to monitor'
    Row '  -Setup                  Interactive setup wizard'
    Row '  -Install                Create the scheduled task'
    Row '  -IntervalHours <1-168>  Task interval in hours (with -Install)'
    Row '  -Remove                 Delete the scheduled task'
    Row '  -Help, -h, -?           Show this help'
    Row ''
    Row 'EXAMPLES' 'Yellow'
    Row "  .\$ScriptName -AdapterName 'Ethernet'" 'Green'
    Row '    One-time check of the adapter "Ethernet".' 'DarkGray'
    Row "  .\$ScriptName -Setup" 'Green'
    Row '    Guided setup including an optional schedule.' 'DarkGray'
    Row "  .\$ScriptName -Install -AdapterName 'Ethernet' -IntervalHours 1" 'Green'
    Row '    Checks "Ethernet" automatically every hour.' 'DarkGray'
    Row "  .\$ScriptName -Remove" 'Green'
    Row '    Removes the scheduled task again.' 'DarkGray'
    Row ''
    Row 'NOTES' 'Yellow'
    Row '  - A plain status check runs without administrator rights.'
    Row '  - Repair, -Install and -Remove require an elevated PowerShell.'
    Row "  - Log file: $LogFile"
    Row "  - Task name: $TaskName"
    Row ''
    Write-Host $line -ForegroundColor DarkCyan
    Write-Host ''
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-Admin {
    param([string]$Reason)
    if (-not (Test-IsAdmin)) {
        Write-Log "Administrator rights are required to $Reason. Please run PowerShell as administrator." 'ERROR'
        exit 1
    }
}

function Register-WatchOutTask {
    param([string]$Adapter, [int]$Hours)
    Assert-Admin 'create the scheduled task'
    $scriptPath = if ($PSCommandPath) { $PSCommandPath } else { Join-Path $PSScriptRoot $ScriptName }
    $arg = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`" -AdapterName `"$Adapter`""
    $action    = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $arg
    $trigger   = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Hours $Hours)
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null
    Write-Log "Scheduled task '$TaskName' created: adapter '$Adapter', every $Hours hour(s)." 'OK'
}

###############################################
###--- Help (always first)
###############################################
if ($Help) {
    Show-Help
    exit 0
}

###############################################
###--- Setup Wizard
###############################################
if ($Setup) {
    try {
        Write-Host ''
        Write-Host 'Available adapters:' -ForegroundColor Cyan
        Get-NetAdapter | Select-Object Name, InterfaceDescription, Status | Format-Table -AutoSize
        $AdapterName = Read-Host 'Name of the adapter to monitor'
        if (-not (Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue)) {
            Write-Log "Adapter '$AdapterName' was not found." 'ERROR'
            exit 2
        }
        Write-Log "Adapter '$AdapterName' selected." 'OK'

        $answer = Read-Host 'Run the script on a schedule? (Y/N)'
        if ($answer -match '^[yY]') {
            $hours = 0
            if (-not [int]::TryParse((Read-Host 'Interval in hours (1-168)'), [ref]$hours) -or $hours -lt 1 -or $hours -gt 168) {
                Write-Log 'Invalid interval.' 'ERROR'
                exit 2
            }
            Register-WatchOutTask -Adapter $AdapterName -Hours $hours
        } else {
            Write-Log "No schedule created. Run manually: .\$ScriptName -AdapterName <name>" 'INFO'
        }
        exit 0
    } catch {
        Write-Log "Setup failed: $_" 'ERROR'
        exit 1
    }
}

###############################################
###--- Create / Remove Scheduled Task (explicit request only)
###############################################
if ($Install) {
    if (-not $AdapterName -or -not $IntervalHours) {
        Write-Log '-Install requires -AdapterName and -IntervalHours.' 'ERROR'
        exit 2
    }
    if (-not (Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue)) {
        Write-Log "Adapter '$AdapterName' was not found." 'ERROR'
        exit 2
    }
    try { Register-WatchOutTask -Adapter $AdapterName -Hours $IntervalHours; exit 0 }
    catch { Write-Log "Could not create the scheduled task: $_" 'ERROR'; exit 1 }
}

if ($Remove) {
    Assert-Admin 'delete the scheduled task'
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Log "Scheduled task '$TaskName' deleted." 'OK'
        exit 0
    } catch {
        Write-Log "Could not delete the scheduled task: $_" 'ERROR'
        exit 1
    }
}

###############################################
###--- Main Logic: Check Adapter
###############################################
if (-not $AdapterName) {
    Show-Help
    Write-Log 'No -AdapterName specified.' 'ERROR'
    exit 2
}

$adapter = Get-NetAdapter -Name $AdapterName -ErrorAction SilentlyContinue
if (-not $adapter) {
    Write-Log "Adapter '$AdapterName' was not found." 'ERROR'
    exit 2
}

if ($adapter.Status -eq 'Up') {
    Write-Log "Adapter '$AdapterName' is online." 'OK'
    exit 0
}

Write-Log "Adapter '$AdapterName' has status '$($adapter.Status)'. Starting recovery." 'WARN'
Assert-Admin 'repair the adapter (ipconfig /renew)'

try {
    if ($adapter.Status -eq 'Disabled') {
        Write-Log 'Adapter is disabled, enabling it.' 'INFO'
        Enable-NetAdapter -Name $AdapterName -Confirm:$false -ErrorAction Stop
        Start-Sleep -Seconds 5
    }

    $out = & ipconfig /renew "$AdapterName" 2>&1
    Write-Log ('ipconfig /renew: ' + (($out | Where-Object { $_ }) -join ' | ')) 'INFO'

    Start-Sleep -Seconds 10
    $status = (Get-NetAdapter -Name $AdapterName).Status
    if ($status -eq 'Up') {
        Write-Log "Adapter '$AdapterName' is back online." 'OK'
        exit 0
    }
    Write-Log "Adapter '$AdapterName' is still '$status' (if 'Disconnected', check cable/switch/Wi-Fi)." 'ERROR'
    exit 3
} catch {
    Write-Log "Recovery failed: $_" 'ERROR'
    exit 1
}