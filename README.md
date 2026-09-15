# TPF-Check-Services

## Overview & Purpose

> **Warning: Lab Use Only**  
> This script is designed strictly for lab environments where SQL Server and CyberArk Trust Protection Foundation (TPF) reside on the same host. **Do not use this script in a production environment.**

### Why It's Needed
If you are running an unsupported configuration where you have the SQL server and TPF installed on the same server, sometimes during system reboots, **SQL Server** and **CyberArk (TPF) services** often fail to start in a timely manner or in the correct sequence. Dependent services can fail or crash if IIS and CyberArk try to initialize before SQL Server is fully ready to accept connections. This script handles startup timing and dependency ordering automatically.

### What the Script Does
* **Verifies & Starts SQL First**: Checks `MSSQLSERVER`; if stopped, starts it and waits **90 seconds** so database engines fully initialize.
* **Recovers CyberArk Services**: Checks `CyberArk Trust Protection Foundation` and `Cyberark Log Server`, starting any stopped services.
* **Gracefully Recycles IIS**: If a CyberArk service had to be started, pauses **90 seconds** for service stabilization, then runs `iisreset /noforce` to restore web connectivity.
* **Manages Logs Automatically**: Writes timestamped logs to `C:\Scripts`, purges log files older than 5 days, and logs system warnings to the Windows Event Log if services are missing.

## Install / Remove Instructions

### Prerequisites
- Run PowerShell as an Administrator.
- Place the script in a folder such as `C:\Scripts\TPF-Check-Services`.
- Ensure the script file is named `Check-Services.ps1`.

### Install the Scheduled Task
From an elevated PowerShell session:

```powershell
Set-Location "C:\Scripts"
git clone https://github.com/bradmcdowell/TPF-Check-Services.git
cd .\TPF-Check-Services
Get-ChildItem -Path .\ -Recurse | Unblock-File
.\Check-Services.ps1 -AddTaskScheduler
```

This creates a scheduled task named `TPF Check Services` that runs:
- At Windows startup after a 15-minute delay
- Daily at 05:49:25 AM
- As `NT AUTHORITY\SYSTEM` with highest privileges

### Remove the Scheduled Task
From an elevated PowerShell session:

```powershell
Set-Location "C:\Scripts\TPF-Check-Services"
.\Check-Services.ps1 -RemoveTaskScheduler
```

This unregisters the task and stops automatic monitoring.

### Run the Script Manually
If you want to execute it immediately without creating the task:

```powershell
Set-Location "C:\Scripts\TPF-Check-Services"
.\Check-Services.ps1
```

This performs the SQL and CyberArk service checks immediately and will reset IIS only if one of the CyberArk services had to be started.