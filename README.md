# TPF-Check-Services

**Script Overview & Purpose**

### Why It's Needed
If you have the SQL server and TPF installed on the same server, sometimes during system reboots, **SQL Server** and **CyberArk (TPF) services** often fail to start in a timely manner or in the correct sequence. Dependent services can fail or crash if IIS and CyberArk try to initialize before SQL Server is fully ready to accept connections. This script handles startup timing and dependency ordering automatically.

### What the Script Does
* **Verifies & Starts SQL First**: Checks `MSSQLSERVER`; if stopped, starts it and waits **90 seconds** so database engines fully initialize.
* **Recovers CyberArk Services**: Checks `CyberArk Trust Protection Foundation` and `Cyberark Log Server`, starting any stopped services.
* **Gracefully Recycles IIS**: If a CyberArk service had to be started, pauses **90 seconds** for service stabilization, then runs `iisreset /noforce` to restore web connectivity.
* **Manages Logs Automatically**: Writes timestamped logs to `C:\Scripts`, purges log files older than 5 days, and logs system warnings to the Windows Event Log if services are missing.