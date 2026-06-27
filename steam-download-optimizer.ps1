# 1. Check for Administrator privileges
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Start-Process powershell -ArgumentList "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath -Verb RunAs
    Exit
}

# 2. Target Steam process
$ProcessName = "steam"
$SteamProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue

if (-not $SteamProcess) {
    Write-Host "[-] Steam is not running." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    Exit
}

Write-Host "[+] Setting Steam priority to: High..." -ForegroundColor Cyan
foreach ($proc in $SteamProcess) {
    $proc.PriorityClass = 'High'
}
Write-Host "[V] Priority changed. Analyzing Steam data traffic..." -ForegroundColor Green
Write-Host "--------------------------------------------------------"

# 3. Monitoring loop via process Input/Output (I/O)
$InactivityChecks = 0
$CheckInterval = 5 # Seconds to wait between each measurement
$InactivityThreshold = 3 # Number of checks before closing (3 x 5 = 15 seconds)
$ActivityThresholdBytes = 1MB # Steam must process at least 1 MB in 5 seconds to be considered active

while ($true) {
    # Starting measurement
    $SteamData1 = Get-CimInstance Win32_Process -Filter "Name = 'steam.exe'"
    $IoStart = 0
    foreach ($p in $SteamData1) {
        $IoStart += $p.ReadTransferCount + $p.WriteTransferCount + $p.OtherTransferCount
    }

    Start-Sleep -Seconds $CheckInterval

    # Ending measurement
    $SteamData2 = Get-CimInstance Win32_Process -Filter "Name = 'steam.exe'"
    $IoEnd = 0
    foreach ($p in $SteamData2) {
        $IoEnd += $p.ReadTransferCount + $p.WriteTransferCount + $p.OtherTransferCount
    }

    # Calculate the difference
    $IoDiff = $IoEnd - $IoStart
    $IoDiffMB = $IoDiff / 1MB
    $Speed = [math]::Round($IoDiffMB / $CheckInterval, 2)

    # Analyze the results
    if ($IoDiff -lt $ActivityThresholdBytes) {
        $InactivityChecks++
        Write-Host "-> Activity drop detected (~$Speed MB/s)... ($($InactivityChecks * $CheckInterval)/15 seconds)" -ForegroundColor Yellow
    } else {
        Write-Host "   Steam Activity: ~$Speed MB/s (Network + Disk)" -ForegroundColor DarkGray
        $InactivityChecks = 0
    }

    # If 3 consecutive checks without high activity
    if ($InactivityChecks -ge $InactivityThreshold) {
        Write-Host "[V] Download and decompression seem to be finished (or paused)!" -ForegroundColor Green
        break
    }
}

# 4. Restore normal priority
Write-Host "--------------------------------------------------------"
$SteamProcess = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
if ($SteamProcess) {
    Write-Host "[+] Restoring priority to Normal mode..." -ForegroundColor Cyan
    foreach ($proc in $SteamProcess) {
        $proc.PriorityClass = 'Normal'
    }
    Write-Host "[V] Steam is back to normal priority." -ForegroundColor Green
}

Write-Host "Auto-closing in 5 seconds..."
Start-Sleep -Seconds 5
