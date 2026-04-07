Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up ActivInspire environment ==="

    # ---- 1. Disable OneDrive (safety net) ----
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run" `
        -Name "OneDrive" -ErrorAction SilentlyContinue

    # ---- 2. Locate ActivInspire executable ----
    Write-Host "Locating ActivInspire executable..."
    $inspireExe = $null

    # Check saved path from install
    $savedPath = "C:\Users\Docker\activinspire_path.txt"
    if (Test-Path $savedPath) {
        $candidate = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $candidate) {
            $inspireExe = $candidate
        }
    }

    # Search known paths
    if (-not $inspireExe) {
        $searchPaths = @(
            "C:\Program Files (x86)\Activ Software\Inspire\Inspire.exe",
            "C:\Program Files\Activ Software\Inspire\Inspire.exe",
            "C:\Program Files\Promethean\ActivInspire\Inspire.exe",
            "C:\Program Files (x86)\Promethean\ActivInspire\Inspire.exe",
            "C:\Program Files\ActivInspire\Inspire.exe",
            "C:\Program Files (x86)\ActivInspire\Inspire.exe"
        )
        foreach ($p in $searchPaths) {
            if (Test-Path $p) {
                $inspireExe = $p
                break
            }
        }
    }

    # Broader search
    if (-not $inspireExe) {
        $found = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse `
            -Filter "Inspire.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) {
            $inspireExe = $found.FullName
        }
    }

    if ($inspireExe) {
        Write-Host "Found ActivInspire at: $inspireExe"
        # Save path for task_utils.ps1
        [System.IO.File]::WriteAllText("C:\Users\Docker\activinspire_path.txt", $inspireExe)
    } else {
        Write-Host "WARNING: ActivInspire executable not found"
    }

    # ---- 3. Create working directories ----
    Write-Host "Setting up working directories..."
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\Flipcharts" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Pictures\ActivInspire" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop" | Out-Null

    # ---- 4. Copy asset files from workspace ----
    if (Test-Path "C:\workspace\assets\flipcharts") {
        Write-Host "Copying flipchart assets from workspace..."
        Copy-Item "C:\workspace\assets\flipcharts\*" -Destination "C:\Users\Docker\Documents\Flipcharts" `
            -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path "C:\workspace\assets\images") {
        Write-Host "Copying image assets from workspace..."
        Copy-Item "C:\workspace\assets\images\*" -Destination "C:\Users\Docker\Pictures\ActivInspire" `
            -Recurse -Force -ErrorAction SilentlyContinue
    }

    # ---- 5. Configure ActivInspire settings via registry ----
    # Suppress first-run dialogs, registration prompts, update checks
    Write-Host "Configuring ActivInspire settings..."

    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"

        # Promethean/ActivInspire registry settings
        $aiRegPath = "HKCU:\Software\Promethean\ActivInspire"
        New-Item -Path $aiRegPath -Force 2>$null | Out-Null
        Set-ItemProperty -Path $aiRegPath -Name "ShowDashboardOnStartup" -Value 0 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $aiRegPath -Name "FirstRunComplete" -Value 1 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $aiRegPath -Name "LicenseAccepted" -Value 1 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $aiRegPath -Name "ShowTips" -Value 0 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $aiRegPath -Name "ShowWelcome" -Value 0 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $aiRegPath -Name "CheckForUpdates" -Value 0 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $aiRegPath -Name "DefaultPath" -Value "C:\Users\Docker\Documents\Flipcharts" -Type String -Force 2>$null

        # ActivSoftware general settings
        $asRegPath = "HKCU:\Software\Promethean\ActivSoftware"
        New-Item -Path $asRegPath -Force 2>$null | Out-Null
        Set-ItemProperty -Path $asRegPath -Name "FirstRun" -Value 0 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $asRegPath -Name "RegistrationComplete" -Value 1 -Type DWord -Force 2>$null
        Set-ItemProperty -Path $asRegPath -Name "ShowStartupDialog" -Value 0 -Type DWord -Force 2>$null

        # Promethean ClassFlow / update settings
        $cfRegPath = "HKCU:\Software\Promethean\ClassFlow"
        New-Item -Path $cfRegPath -Force 2>$null | Out-Null
        Set-ItemProperty -Path $cfRegPath -Name "ShowOnStartup" -Value 0 -Type DWord -Force 2>$null
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # Also create INI-style config files (ActivInspire may read from AppData)
    $configDir = "C:\Users\Docker\AppData\Local\Promethean\ActivInspire"
    New-Item -ItemType Directory -Force -Path $configDir | Out-Null

    $configContent = @"
[General]
ShowDashboardOnStartup=false
FirstRunComplete=true
LicenseAccepted=true
CheckForUpdates=false

[Interface]
ShowTips=false
ShowWelcome=false
Language=en-US

[Workspace]
DefaultPath=C:\Users\Docker\Documents\Flipcharts
AutosaveEnabled=true
AutosaveInterval=5
"@
    [System.IO.File]::WriteAllText((Join-Path $configDir "ActivInspire.conf"), $configContent)

    $regConfigDir = "C:\Users\Docker\AppData\Local\Promethean\ActivSoftware"
    New-Item -ItemType Directory -Force -Path $regConfigDir | Out-Null

    $regContent = @"
[Registration]
FirstRun=false
RegistrationComplete=true

[General]
Language=en-US
ShowStartupDialog=false
"@
    [System.IO.File]::WriteAllText((Join-Path $regConfigDir "ActivSoftware.conf"), $regContent)

    # ---- 6. Warm-up launch of ActivInspire ----
    # First launch triggers: License Agreement, Welcome/customization dialog,
    # and the ActivInspire Dashboard. This warm-up cycle clears all of them
    # using the PyAutoGUI TCP server (port 5555) which runs in the desktop session.
    if ($inspireExe) {
        Write-Host "Warming up ActivInspire (first-run cycle)..."

        # PyAutoGUI helper functions
        function Send-WarmupPyAutoGUI([string]$json) {
            $client = New-Object System.Net.Sockets.TcpClient
            $ar = $client.BeginConnect("127.0.0.1", 5555, $null, $null)
            $waited = $ar.AsyncWaitHandle.WaitOne(5000, $false)
            if (-not $waited -or -not $client.Connected) {
                $client.Close()
                return $null
            }
            $client.EndConnect($ar)
            $stream = $client.GetStream()
            $stream.ReadTimeout = 10000
            $stream.WriteTimeout = 5000
            $writer = New-Object System.IO.StreamWriter($stream)
            $writer.AutoFlush = $true
            $writer.WriteLine($json)
            $reader = New-Object System.IO.StreamReader($stream)
            $line = $reader.ReadLine()
            $client.Close()
            return $line
        }

        function WarmupClick([int]$x, [int]$y) {
            $json = "{`"action`":`"click`",`"x`":$x,`"y`":$y}"
            $resp = Send-WarmupPyAutoGUI $json
            Write-Host "  WarmupClick($x,$y) -> $resp"
            return $resp
        }

        $prevEAP = $ErrorActionPreference
        try {
            $ErrorActionPreference = "Continue"

            # Launch ActivInspire in Session 1 (must cd to install dir for DLL deps)
            $inspireDir = Split-Path $inspireExe -Parent
            $warmupBat = "C:\Windows\Temp\warmup_launch.bat"
            [System.IO.File]::WriteAllText($warmupBat, "@echo off`r`ncd /d `"$inspireDir`"`r`nstart `"`" `"$inspireExe`"")
            $taskName = "WarmupActivInspire_GA"
            schtasks /Create /TN $taskName /TR $warmupBat `
                /SC ONCE /SD 01/01/2099 /ST 00:00 /RL HIGHEST /IT /F 2>$null
            schtasks /Run /TN $taskName 2>$null
            Write-Host "Launched ActivInspire in interactive session"

            # Wait for ActivInspire process to appear
            $maxWait = 30
            for ($i = 0; $i -lt $maxWait; $i++) {
                $proc = Get-Process -Name "Inspire" -ErrorAction SilentlyContinue
                if ($proc) {
                    Write-Host "Inspire process found: PID=$($proc.Id)"
                    break
                }
                Start-Sleep -Seconds 1
            }
            Start-Sleep -Seconds 10

            # Dialog 1: Promethean License Agreement
            Write-Host "Dismissing License Agreement..."
            WarmupClick 472 492   # "I accept" checkbox
            Start-Sleep -Seconds 3
            WarmupClick 518 518   # "Run Personal Edition"
            Start-Sleep -Seconds 5

            # Dialog 2: Welcome to ActivInspire (customization)
            Write-Host "Dismissing Welcome dialog..."
            WarmupClick 756 418   # "Continue"
            Start-Sleep -Seconds 5

            # Dialog 3: ActivInspire Dashboard
            Write-Host "Dismissing Dashboard..."
            WarmupClick 843 490   # "Close"
            Start-Sleep -Seconds 3

            # Dialog 4: ActivInspire Update (Cancel at 808,368)
            Write-Host "Dismissing Update dialog..."
            WarmupClick 808 368   # "Cancel" update
            Start-Sleep -Seconds 3

            # Press Escape for any stray dialogs
            Send-WarmupPyAutoGUI '{"action":"press","key":"escape"}' | Out-Null
            Start-Sleep -Seconds 2
            Send-WarmupPyAutoGUI '{"action":"press","key":"escape"}' | Out-Null
            Start-Sleep -Seconds 3

            # Dismiss OneDrive notification (X at 1238,392)
            WarmupClick 1238 392
            Start-Sleep -Seconds 2

            Write-Host "Warmup dialog dismissal complete"

            # Kill warm-up instance
            Write-Host "Closing warm-up instance..."
            Get-Process -Name "Inspire" -ErrorAction SilentlyContinue |
                Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3

            # Cleanup
            schtasks /Delete /TN $taskName /F 2>$null
            Remove-Item "C:\Windows\Temp\warmup_launch.bat" -Force -ErrorAction SilentlyContinue
        } finally {
            $ErrorActionPreference = $prevEAP
        }
        Write-Host "ActivInspire warm-up complete."
    } else {
        Write-Host "WARNING: Skipping warm-up - ActivInspire executable not found"
    }

    # ---- 7. Minimize terminal windows ----
    Write-Host "Minimizing terminal windows..."
    Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win32Setup {
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@
    Get-Process cmd -ErrorAction SilentlyContinue | ForEach-Object {
        [Win32Setup]::ShowWindow($_.MainWindowHandle, 6) | Out-Null
    }

    Write-Host "=== ActivInspire environment setup complete ==="
    if ($inspireExe) {
        Write-Host "ActivInspire exe: $inspireExe"
    }
    Write-Host "Flipcharts dir: C:\Users\Docker\Documents\Flipcharts"
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
