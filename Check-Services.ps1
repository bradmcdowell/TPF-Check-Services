[CmdletBinding()]
param (
    [switch]$AddTaskScheduler
)

# Directory and dynamic log file path
$ScriptFolder = "C:\Scripts\TPF-Check-Services"
$logDirectory = $ScriptFolder
$today = Get-Date -Format "yyyy-MM-dd"
$logFilePath = Join-Path -Path $logDirectory -ChildPath "TPP_Service_Monitor_$today.log"

# 1. Ensure the directory exists
if (-not (Test-Path -Path $logDirectory)) {
    New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
}

# 2. Purge log files older than 5 days
$retentionDays = 5
Get-ChildItem -Path $logDirectory -Filter "TPP_Service_Monitor_*.log" -File | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$retentionDays) } | 
    Remove-Item -Force

# Helper function to write to both screen and file
function Write-Log {
    param (
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $formattedLog = "[$timestamp] [$Level] $Message"

    # Print to screen
    switch ($Level) {
        "ERROR"   { Write-Host $formattedLog -ForegroundColor Red }
        "WARNING" { Write-Host $formattedLog -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $formattedLog -ForegroundColor Green }
        default   { Write-Host $formattedLog -ForegroundColor Cyan }
    }

    # Append to local log file
    Add-Content -Path $logFilePath -Value $formattedLog
}

# Helper function to register Scheduled Task
function Install-CheckServicesTask {
    $taskName = "TPF Check Services"
    
    # Dynamically build the script path based on $ScriptFolder and current script filename
    $scriptName = "Check-Services.ps1"
    $targetScriptPath = Join-Path -Path $ScriptFolder -ChildPath $scriptName

    # Ensure running with Administrator privileges
    $currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "Administrator privileges are required to register this Scheduled Task." "ERROR"
        return
    }

    # Task Action
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -File `"$targetScriptPath`""

    # Task Triggers: 15-minute delay after boot AND Daily at 05:49 AM
    $bootTrigger = New-ScheduledTaskTrigger -AtStartup
    $bootTrigger.Delay = 'PT15M'
    $dailyTrigger = New-ScheduledTaskTrigger -Daily -At "05:49:25 AM"

    # Task Principal: SYSTEM Account with Highest Privileges
    $principal = New-ScheduledTaskPrincipal -UserId "NT AUTHORITY\SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    # Task Settings (Removed invalid -AllowStartOnDemand parameter)
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 72) -Priority 7

    try {
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger @($bootTrigger, $dailyTrigger) -Principal $principal -Settings $settings -Force | Out-Null
        Write-Log "Scheduled Task '$taskName' successfully created pointing to: $targetScriptPath" "SUCCESS"
    } catch {
        Write-Log "Failed to register Scheduled Task. Error: $_" "ERROR"
    }
}

# --- Handle -AddTaskScheduler Switch ---
if ($AddTaskScheduler) {
    Write-Log "Registering Scheduled Task..." "INFO"
    Install-CheckServicesTask
    exit
}

# Define the services to monitor
$services = @("CyberArk Trust Protection Foundation", "Cyberark Log Server")

Write-Log "Starting service status check..." "INFO"

# Track if any CyberArk service was restarted
$needsIisReset = $false

# --- Pre-check: SQL Server ---
$sqlServiceName = "MSSQLSERVER"
$sqlService = Get-Service -Name $sqlServiceName -ErrorAction SilentlyContinue

if ($sqlService) {
    if ($sqlService.Status -ne 'Running') {
        try {
            Write-Log "Service '$sqlServiceName' is not running. Attempting to start..." "WARNING"
            Start-Service -InputObject $sqlService -ErrorAction Stop
            Write-Log "Service '$sqlServiceName' started successfully. Waiting 90 seconds for database initialization..." "SUCCESS"
            
            # Pause execution for 90 seconds to allow SQL services/databases to settle
            Start-Sleep -Seconds 90
        } catch {
            Write-Log "Failed to start service '$sqlServiceName'. Error: $_" "ERROR"
        }
    } else {
        Write-Log "Service '$sqlServiceName' is already running." "INFO"
    }
} else {
    Write-Log "Service '$sqlServiceName' could not be found on this system." "WARNING"
}

# --- Service Loop ---
foreach ($serviceName in $services) {
    # Get service status
    $service = Get-Service -DisplayName $serviceName -ErrorAction SilentlyContinue
    
    # Fallback to check by ServiceName if DisplayName isn't found
    if (-not $service) {
        $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    }

    if ($service) {
        if ($service.Status -ne 'Running') {
            try {
                Start-Service -InputObject $service -ErrorAction Stop
                $msg = "Service '$($service.DisplayName)' was not running and has been successfully restarted."
                Write-Log $msg "SUCCESS"
                
                # Flag that an IIS reset will be required
                $needsIisReset = $true
            } catch {
                $msg = "Failed to start service '$($service.DisplayName)'. Error: $_"
                Write-Log $msg "ERROR"
            }
        } else {
            Write-Log "Service '$($service.DisplayName)' is already running." "INFO"
        }
    } else {
        $msg = "Service '$serviceName' could not be found on this system."
        
        Write-Log $msg "WARNING"
        Write-EventLog -LogName Application -Source "CustomServiceMonitor" -EntryType Warning -EventId 1003 -Message $msg
    }
}

# --- Conditional IIS Reset ---
if ($needsIisReset) {
    Write-Log "One or more CyberArk services were started. Waiting 90 seconds before executing IIS reset..." "WARNING"
    
    # Wait 90 seconds before triggering IIS reset
    Start-Sleep -Seconds 90
    try {
        $iisResult = iisreset.exe /noforce 2>&1
        Write-Log "IIS reset completed successfully: $iisResult" "SUCCESS"
    } catch {
        Write-Log "Failed to perform IIS reset. Error: $_" "ERROR"
    }
} else {
    Write-Log "No CyberArk services were restarted. Skipping IIS reset." "INFO"
}

Write-Log "Service status check completed." "INFO"