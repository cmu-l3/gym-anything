Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install Visual Studio 2022 Community with C#/.NET Desktop workload.
# This script runs as the pre_start hook (SSH Session 0).
# Key: VS bootstrapper supports --wait so we don't need schtasks for the install.
# Key: curl.exe stderr kills $ErrorActionPreference="Stop" -- use --silent --show-error.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Visual Studio 2022 Community ==="

    # --- Step 1: Check if VS is already installed ---
    $devenvExe = "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\devenv.exe"
    if (Test-Path $devenvExe) {
        Write-Host "Visual Studio 2022 already installed at: $devenvExe"
        Write-Host "=== VS 2022 installation complete (already present) ==="
        return
    }

    # --- Step 2: Download the VS bootstrapper ---
    $workDir = "C:\VSSetup"
    New-Item -ItemType Directory -Force -Path $workDir | Out-Null

    $curlExe = "C:\Windows\System32\curl.exe"
    $bootstrapperUrl = "https://aka.ms/vs/17/release/vs_Community.exe"
    $bootstrapperPath = "$workDir\vs_Community.exe"

    Write-Host "Downloading VS 2022 Community bootstrapper..."
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $curlExe -L --silent --show-error --max-time 120 --connect-timeout 30 -o $bootstrapperPath $bootstrapperUrl 2>&1
    $curlExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP

    if ($curlExit -ne 0 -or -not (Test-Path $bootstrapperPath)) {
        throw "Bootstrapper download failed (exit code: $curlExit)"
    }

    $fileSize = (Get-Item $bootstrapperPath).Length
    Write-Host "Bootstrapper downloaded: $([math]::Round($fileSize / 1KB, 1)) KB"

    if ($fileSize -lt 100000) {
        throw "Bootstrapper file too small ($fileSize bytes) -- download may have failed"
    }

    # --- Step 3: Run the VS installer ---
    # --add: workload for .NET desktop development (C# console apps, WinForms, WPF)
    # --includeRecommended: includes .NET SDK, NuGet, IntelliSense, etc.
    # --passive: shows progress UI but no user interaction needed
    # --norestart: don't reboot after install
    # --wait: block until install completes
    Write-Host "Starting VS 2022 installation (this takes 15-30 minutes)..."
    Write-Host "  Workload: Microsoft.VisualStudio.Workload.ManagedDesktop"

    $installArgs = @(
        "--add", "Microsoft.VisualStudio.Workload.ManagedDesktop",
        "--includeRecommended",
        "--passive",
        "--norestart",
        "--wait"
    )

    $proc = Start-Process -FilePath $bootstrapperPath -ArgumentList $installArgs -Wait -PassThru
    $exitCode = $proc.ExitCode
    Write-Host "VS installer exited with code: $exitCode"

    # Exit codes: 0=success, 3010=reboot recommended (treat as success)
    if ($exitCode -ne 0 -and $exitCode -ne 3010) {
        Write-Host "WARNING: VS installer exited with code $exitCode"
        # Check for common install logs
        $vsLogDir = "$env:TEMP\dd_*.log"
        $logFiles = Get-ChildItem $env:TEMP -Filter "dd_*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3
        foreach ($lf in $logFiles) {
            Write-Host "--- Log: $($lf.Name) (last 20 lines) ---"
            Get-Content $lf.FullName -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $_" }
        }
    }

    # --- Step 4: Verify installation ---
    Write-Host "Verifying installation..."
    if (Test-Path $devenvExe) {
        $item = Get-Item $devenvExe
        Write-Host "Visual Studio 2022 installed successfully."
        Write-Host "  Path: $devenvExe"
        Write-Host "  Version: $($item.VersionInfo.ProductVersion)"
        Write-Host "  Size: $($item.Length) bytes"
    } else {
        Write-Host "ERROR: devenv.exe not found after installation at: $devenvExe"
        # Search more broadly
        $vsRoot = "C:\Program Files\Microsoft Visual Studio\2022"
        if (Test-Path $vsRoot) {
            $found = Get-ChildItem $vsRoot -Recurse -Filter "devenv.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($found) {
                Write-Host "Found devenv.exe at alternate path: $($found.FullName)"
            } else {
                Write-Host "No devenv.exe found under: $vsRoot"
                # List what was installed
                Get-ChildItem $vsRoot -Depth 2 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.FullName)" }
            }
        } else {
            Write-Host "VS root directory not found: $vsRoot"
        }
    }

    # --- Step 5: Verify .NET SDK ---
    Write-Host ""
    Write-Host "Checking .NET SDK..."
    $dotnetExe = "C:\Program Files\dotnet\dotnet.exe"
    if (Test-Path $dotnetExe) {
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $sdkOutput = & $dotnetExe --list-sdks 2>&1
        $ErrorActionPreference = $prevEAP
        Write-Host ".NET SDKs installed:"
        $sdkOutput | ForEach-Object { Write-Host "  $_" }
    } else {
        Write-Host "WARNING: dotnet.exe not found. .NET SDK may not be installed."
    }

    # Cleanup installer files
    Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "=== VS 2022 installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
