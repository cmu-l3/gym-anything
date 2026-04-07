Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Setup script for Visual Studio 2022 environment.
# This script runs after Windows boots (post_start hook).
# It creates C# projects via dotnet CLI, sets registry keys, and does a warm-up launch.

$logPath = "C:\Users\Docker\env_setup_post_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Setting up Visual Studio 2022 environment ==="

    # --- Step 1: Suppress telemetry and auto-updates ---
    Write-Host "Configuring registry keys..."

    # Disable VS telemetry
    $sqmPath = "HKLM:\SOFTWARE\Microsoft\VSCommon\17.0\SQM"
    if (-not (Test-Path $sqmPath)) { New-Item -Path $sqmPath -Force | Out-Null }
    Set-ItemProperty -Path $sqmPath -Name "OptIn" -Value 0 -Type DWord -Force

    # Disable background downloads / updates
    $setupPath = "HKLM:\SOFTWARE\Microsoft\VisualStudio\Setup"
    if (-not (Test-Path $setupPath)) { New-Item -Path $setupPath -Force | Out-Null }
    Set-ItemProperty -Path $setupPath -Name "BackgroundDownloadDisabled" -Value 1 -Type DWord -Force

    # Disable .NET CLI telemetry
    [System.Environment]::SetEnvironmentVariable("DOTNET_CLI_TELEMETRY_OPTOUT", "1", "Machine")
    [System.Environment]::SetEnvironmentVariable("DOTNET_NOLOGO", "1", "Machine")

    # Set for current session too
    $env:DOTNET_CLI_TELEMETRY_OPTOUT = "1"
    $env:DOTNET_NOLOGO = "1"

    Write-Host "Registry and environment configured."

    # --- Step 2: Aggressively disable OneDrive ---
    Write-Host "Disabling OneDrive..."
    Get-Process OneDrive -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Process OneDriveSetup -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    $onedrivePath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
    Remove-ItemProperty -Path $onedrivePath -Name "OneDrive" -ErrorAction SilentlyContinue
    $onedrivePolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\OneDrive"
    if (-not (Test-Path $onedrivePolicyPath)) { New-Item -Path $onedrivePolicyPath -Force | Out-Null }
    Set-ItemProperty -Path $onedrivePolicyPath -Name "DisableFileSyncNGSC" -Value 1 -Type DWord -Force
    $oneDriveSetup = "$env:SystemRoot\SysWOW64\OneDriveSetup.exe"
    if (-not (Test-Path $oneDriveSetup)) { $oneDriveSetup = "$env:SystemRoot\System32\OneDriveSetup.exe" }
    if (Test-Path $oneDriveSetup) {
        $proc = Start-Process $oneDriveSetup -ArgumentList "/uninstall" -PassThru -ErrorAction SilentlyContinue
        if ($proc) {
            $finished = $proc.WaitForExit(30000)
            if ($finished) { Write-Host "OneDrive uninstalled." }
            else { Write-Host "OneDrive uninstall still running (continuing)." }
        }
    }
    $cloudPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cloudPath)) { New-Item -Path $cloudPath -Force | Out-Null }
    Set-ItemProperty -Path $cloudPath -Name "DisableWindowsConsumerFeatures" -Value 1 -Type DWord -Force

    # --- Step 3: Create C# projects via dotnet CLI ---
    Write-Host ""
    Write-Host "=== Creating C# projects ==="

    $dotnetExe = "C:\Program Files\dotnet\dotnet.exe"
    if (-not (Test-Path $dotnetExe)) {
        $dotnetCmd = Get-Command dotnet -ErrorAction SilentlyContinue
        if ($dotnetCmd) { $dotnetExe = $dotnetCmd.Source }
        else {
            Write-Host "WARNING: dotnet.exe not found. Will use fallback data files."
            $dotnetExe = $null
        }
    }

    $projectsRoot = "C:\Users\Docker\source\repos"
    New-Item -ItemType Directory -Force -Path $projectsRoot | Out-Null

    if ($dotnetExe) {
        # --- Create InventoryManager project ---
        $invDir = "$projectsRoot\InventoryManager"
        if (-not (Test-Path "$invDir\InventoryManager.csproj")) {
            Write-Host "Creating InventoryManager console app..."
            & $dotnetExe new console -n InventoryManager -o $invDir --force 2>&1 | Out-Null
            Write-Host "InventoryManager project created."
        }

        # Overwrite Program.cs with real inventory management code
        $programCs = @'
using System;
using System.Collections.Generic;
using System.Linq;

namespace InventoryManager
{
    public class InventoryItem
    {
        public string Name { get; set; }
        public int Quantity { get; set; }
        public decimal Price { get; set; }

        public InventoryItem(string name, int quantity, decimal price)
        {
            Name = name;
            Quantity = quantity;
            Price = price;
        }

        public decimal TotalValue => Quantity * Price;
    }

    class Program
    {
        static void Main(string[] args)
        {
            var inventory = new List<InventoryItem>
            {
                new InventoryItem("Laptop", 15, 999.99m),
                new InventoryItem("Wireless Mouse", 50, 29.99m),
                new InventoryItem("Mechanical Keyboard", 30, 79.99m),
                new InventoryItem("27-inch Monitor", 20, 349.99m),
                new InventoryItem("USB-C Headset", 40, 59.99m)
            };

            Console.WriteLine("╔══════════════════════════════════════════════════════════════╗");
            Console.WriteLine("║              INVENTORY MANAGEMENT REPORT                     ║");
            Console.WriteLine("╠══════════════════════════════════════════════════════════════╣");
            Console.WriteLine("║ {0,-22} {1,8} {2,10} {3,14} ║",
                "Product", "Qty", "Price", "Total Value");
            Console.WriteLine("╠══════════════════════════════════════════════════════════════╣");

            foreach (var item in inventory)
            {
                Console.WriteLine("║ {0,-22} {1,8} {2,10:C} {3,14:C} ║",
                    item.Name, item.Quantity, item.Price, item.TotalValue);
            }

            decimal grandTotal = inventory.Sum(i => i.TotalValue);
            Console.WriteLine("╠══════════════════════════════════════════════════════════════╣");
            Console.WriteLine("║ {0,-22} {1,8} {2,10} {3,14:C} ║",
                "GRAND TOTAL", inventory.Sum(i => i.Quantity), "", grandTotal);
            Console.WriteLine("╚══════════════════════════════════════════════════════════════╝");
        }
    }
}
'@
        [System.IO.File]::WriteAllText("$invDir\Program.cs", $programCs)
        Write-Host "InventoryManager Program.cs written."

        # Build the project to warm NuGet cache and verify it compiles
        Write-Host "Building InventoryManager to warm NuGet cache..."
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        & $dotnetExe build $invDir --nologo 2>&1 | ForEach-Object { Write-Host "  $_" }
        $ErrorActionPreference = $prevEAP
        Write-Host "InventoryManager build complete."

        # Clean the build output so the task starts fresh
        & $dotnetExe clean $invDir --nologo 2>&1 | Out-Null
        # Remove bin/obj so the agent must build
        Remove-Item "$invDir\bin" -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item "$invDir\obj" -Recurse -Force -ErrorAction SilentlyContinue

        # --- Create InventoryManager_broken project (for fix_build_error task) ---
        $brokenDir = "$projectsRoot\InventoryManager_broken"
        if (-not (Test-Path "$brokenDir\InventoryManager_broken.csproj")) {
            Write-Host "Creating InventoryManager_broken console app..."
            & $dotnetExe new console -n InventoryManager_broken -o $brokenDir --force 2>&1 | Out-Null
        }

        # Write broken Program.cs with 2 injected errors:
        # 1. InventoryItm typo (CS0246: type not found)
        # 2. Missing semicolon on grandTotal line (CS1002)
        $brokenProgramCs = @'
using System;
using System.Collections.Generic;
using System.Linq;

namespace InventoryManager_broken
{
    public class InventoryItem
    {
        public string Name { get; set; }
        public int Quantity { get; set; }
        public decimal Price { get; set; }

        public InventoryItem(string name, int quantity, decimal price)
        {
            Name = name;
            Quantity = quantity;
            Price = price;
        }

        public decimal TotalValue => Quantity * Price;
    }

    class Program
    {
        static void Main(string[] args)
        {
            var inventory = new List<InventoryItm>
            {
                new InventoryItem("Laptop", 15, 999.99m),
                new InventoryItem("Wireless Mouse", 50, 29.99m),
                new InventoryItem("Mechanical Keyboard", 30, 79.99m),
                new InventoryItem("27-inch Monitor", 20, 349.99m),
                new InventoryItem("USB-C Headset", 40, 59.99m)
            };

            Console.WriteLine("╔══════════════════════════════════════════════════════════════╗");
            Console.WriteLine("║              INVENTORY MANAGEMENT REPORT                     ║");
            Console.WriteLine("╠══════════════════════════════════════════════════════════════╣");
            Console.WriteLine("║ {0,-22} {1,8} {2,10} {3,14} ║",
                "Product", "Qty", "Price", "Total Value");
            Console.WriteLine("╠══════════════════════════════════════════════════════════════╣");

            foreach (var item in inventory)
            {
                Console.WriteLine("║ {0,-22} {1,8} {2,10:C} {3,14:C} ║",
                    item.Name, item.Quantity, item.Price, item.TotalValue);
            }

            decimal grandTotal = inventory.Sum(i => i.TotalValue)
            Console.WriteLine("╠══════════════════════════════════════════════════════════════╣");
            Console.WriteLine("║ {0,-22} {1,8} {2,10} {3,14:C} ║",
                "GRAND TOTAL", inventory.Sum(i => i.Quantity), "", grandTotal);
            Console.WriteLine("╚══════════════════════════════════════════════════════════════╝");
        }
    }
}
'@
        [System.IO.File]::WriteAllText("$brokenDir\Program.cs", $brokenProgramCs)
        Write-Host "InventoryManager_broken Program.cs written (with 2 injected errors)."
    } else {
        # Fallback: copy pre-built project files from data mount
        Write-Host "Using fallback project data from workspace..."
        if (Test-Path "C:\workspace\data\InventoryManager") {
            Copy-Item "C:\workspace\data\InventoryManager" -Destination $projectsRoot -Recurse -Force
            Write-Host "Fallback InventoryManager copied."
        }
        if (Test-Path "C:\workspace\data\InventoryManager_broken") {
            Copy-Item "C:\workspace\data\InventoryManager_broken" -Destination $projectsRoot -Recurse -Force
            Write-Host "Fallback InventoryManager_broken copied."
        }
    }

    # --- Step 4: Warm up Visual Studio ---
    Write-Host ""
    Write-Host "=== Warming up Visual Studio 2022 ==="

    $utils = "C:\workspace\scripts\task_utils.ps1"
    if (Test-Path $utils) {
        . $utils
    } else {
        Write-Host "WARNING: task_utils.ps1 not found. Skipping warm-up."
        Write-Host "=== VS 2022 environment setup complete ==="
        return
    }

    $devenvExe = $null
    try {
        $devenvExe = Find-VS2022Exe
        Write-Host "VS executable: $devenvExe"
    } catch {
        Write-Host "WARNING: Could not find devenv.exe. Skipping warm-up."
        Write-Host "Error: $($_.Exception.Message)"
    }

    if ($devenvExe) {
        # First launch: VS will show theme picker / sign-in / start window.
        # We launch it once to go through the first-run experience, then kill it.
        Write-Host "Launching VS for first-run warm-up..."
        Launch-VS2022Interactive -DevenvExe $devenvExe -WaitSeconds 30

        # Try to dismiss first-run dialogs
        Write-Host "Dismissing first-run dialogs..."
        try {
            Dismiss-VSDialogsBestEffort -Retries 3 -InitialWaitSeconds 3 -BetweenRetriesSeconds 2
            Write-Host "Dialog dismissal attempted."
        } catch {
            Write-Host "WARNING: Dialog dismissal failed: $($_.Exception.Message)"
        }

        # Kill VS and all child processes
        Kill-AllVS2022
        Write-Host "VS warm-up complete."
    }

    # --- Step 5: Clean up desktop in Session 1 (minimize terminals, close Start menu) ---
    $cleanupScript = "C:\Windows\Temp\cleanup_desktop.ps1"
    @'
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
[System.Windows.Forms.SendKeys]::SendWait("{ESC}")
Start-Sleep -Milliseconds 500
(New-Object -ComObject Shell.Application).MinimizeAll()
'@ | Set-Content $cleanupScript -Encoding UTF8
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN "CleanupDesktop_GA" /TR "powershell -ExecutionPolicy Bypass -File $cleanupScript" /SC ONCE /ST 00:00 /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN "CleanupDesktop_GA" 2>$null
    Start-Sleep -Seconds 5
    schtasks /Delete /TN "CleanupDesktop_GA" /F 2>$null
    Remove-Item $cleanupScript -Force -ErrorAction SilentlyContinue
    $ErrorActionPreference = $prevEAP2

    # Show what was created
    Write-Host ""
    Write-Host "Projects created in $projectsRoot :"
    Get-ChildItem $projectsRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  - $($_.Name)" }

    Write-Host "=== Visual Studio 2022 environment setup complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
