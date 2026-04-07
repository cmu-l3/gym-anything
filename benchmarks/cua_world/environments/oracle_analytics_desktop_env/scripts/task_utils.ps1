# task_utils.ps1 - Shared helper functions for Oracle Analytics Desktop task setup scripts.
# Uses Win32 API for GUI automation (SetCursorPos + mouse_event).
# All coordinates are at 1280x720 resolution (QEMU virtio-vga).

# =====================================================================
# Win32 API Mouse Automation
# =====================================================================
# Oracle Analytics Desktop is a standard Windows app that responds to
# Win32 API mouse events from Session 0 via schtasks.

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

public class Win32Mouse {
    [DllImport("user32.dll")]
    public static extern bool SetCursorPos(int X, int Y);

    [DllImport("user32.dll")]
    public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, UIntPtr dwExtraInfo);

    [DllImport("user32.dll")]
    public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    public const uint MOUSEEVENTF_LEFTUP = 0x0004;
    public const uint MOUSEEVENTF_RIGHTDOWN = 0x0008;
    public const uint MOUSEEVENTF_RIGHTUP = 0x0010;
    public const int SW_RESTORE = 9;
    public const int SW_MAXIMIZE = 3;
}
"@

Add-Type -AssemblyName System.Windows.Forms

function Click-At {
    <#
    .SYNOPSIS
        Click at the specified screen coordinates (1280x720 resolution).
    #>
    param(
        [Parameter(Mandatory=$true)][int]$X,
        [Parameter(Mandatory=$true)][int]$Y
    )
    [Win32Mouse]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 100
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_LEFTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}

function DoubleClick-At {
    <#
    .SYNOPSIS
        Double-click at the specified screen coordinates.
    #>
    param(
        [Parameter(Mandatory=$true)][int]$X,
        [Parameter(Mandatory=$true)][int]$Y
    )
    Click-At -X $X -Y $Y
    Start-Sleep -Milliseconds 100
    Click-At -X $X -Y $Y
}

function RightClick-At {
    <#
    .SYNOPSIS
        Right-click at the specified screen coordinates.
    #>
    param(
        [Parameter(Mandatory=$true)][int]$X,
        [Parameter(Mandatory=$true)][int]$Y
    )
    [Win32Mouse]::SetCursorPos($X, $Y)
    Start-Sleep -Milliseconds 100
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_RIGHTDOWN, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 50
    [Win32Mouse]::mouse_event([Win32Mouse]::MOUSEEVENTF_RIGHTUP, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 200
}

function Send-Keys {
    <#
    .SYNOPSIS
        Send keystrokes using SendKeys.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Keys
    )
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 200
}

function Type-Text {
    <#
    .SYNOPSIS
        Type text character by character using SendKeys.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$Text
    )
    foreach ($char in $Text.ToCharArray()) {
        # Escape special SendKeys characters
        $escaped = $char.ToString()
        if ($escaped -match '[\+\^\%\~\(\)\{\}\[\]]') {
            $escaped = "{$escaped}"
        }
        [System.Windows.Forms.SendKeys]::SendWait($escaped)
        Start-Sleep -Milliseconds 50
    }
    Start-Sleep -Milliseconds 200
}

# =====================================================================
# Oracle Analytics Desktop Helpers
# =====================================================================

function Find-OADExe {
    <#
    .SYNOPSIS
        Find the Oracle Analytics Desktop executable.
    .OUTPUTS
        Full path to OAD executable, or throws if not found.
    #>

    # Check known install path first (confirmed: OUI installs dvdesktop.exe here)
    $knownPath = "C:\Program Files\Oracle Analytics Desktop\dvdesktop.exe"
    if (Test-Path $knownPath) {
        return $knownPath
    }

    # Check saved path from post_start
    $savedPath = "C:\Users\Docker\oad_exe_path.txt"
    if (Test-Path $savedPath) {
        $path = (Get-Content $savedPath -Raw).Trim()
        if (Test-Path $path) {
            return $path
        }
    }

    # Search standard installation directories
    $searchDirs = @(
        "C:\Program Files\Oracle Analytics Desktop",
        "C:\Program Files (x86)\Oracle Analytics Desktop",
        "C:\Users\Docker\AppData\Local\OracleAnalyticsDesktop"
    )

    foreach ($dir in $searchDirs) {
        if (Test-Path $dir) {
            $found = Get-ChildItem $dir -Recurse -Filter "*.exe" -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "OAD|dvdesktop|analyticsdesktop|Oracle.*Analytics" } |
                Select-Object -First 1
            if ($found) {
                return $found.FullName
            }
        }
    }

    # Check Start Menu shortcuts
    $shortcuts = Get-ChildItem "C:\ProgramData\Microsoft\Windows\Start Menu\Programs" -Recurse -Filter "*.lnk" -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "Oracle.*Analytics" }
    if ($shortcuts) {
        $shell = New-Object -ComObject WScript.Shell
        foreach ($sc in $shortcuts) {
            $target = $shell.CreateShortcut($sc.FullName).TargetPath
            if (Test-Path $target) {
                return $target
            }
        }
    }

    throw "Oracle Analytics Desktop executable not found"
}

function Launch-OADInteractive {
    <#
    .SYNOPSIS
        Launch Oracle Analytics Desktop in the interactive desktop session via schtasks.
    .PARAMETER OADExe
        Full path to OAD executable.
    .PARAMETER WaitSeconds
        Seconds to wait after launch for app to load.
    #>
    param(
        [Parameter(Mandatory=$true)][string]$OADExe,
        [int]$WaitSeconds = 20
    )

    $launchScript = "C:\Windows\Temp\launch_oad_task.cmd"
    $batchContent = "@echo off`r`nstart `"`" `"$OADExe`""
    [System.IO.File]::WriteAllText($launchScript, $batchContent)

    $taskName = "LaunchOAD_Task_GA"
    $schedTime = (Get-Date).AddMinutes(1).ToString("HH:mm")
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    schtasks /Create /TN $taskName /TR "cmd /c $launchScript" /SC ONCE /ST $schedTime /RL HIGHEST /IT /F 2>$null
    schtasks /Run /TN $taskName 2>$null
    $ErrorActionPreference = $prevEAP

    Write-Host "Waiting $WaitSeconds seconds for Oracle Analytics Desktop to load..."
    Start-Sleep -Seconds $WaitSeconds

    # Clean up
    $ErrorActionPreference = "Continue"
    schtasks /Delete /TN $taskName /F 2>$null
    $ErrorActionPreference = $prevEAP
}

function Focus-OADWindow {
    <#
    .SYNOPSIS
        Bring Oracle Analytics Desktop window to the foreground.
    #>
    $procs = Get-Process | Where-Object {
        ($_.MainWindowTitle -match "Oracle|Analytics") -or
        ($_.ProcessName -match "OAD|dvdesktop|analyticsdesktop")
    }

    foreach ($proc in $procs) {
        if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
            [Win32Mouse]::ShowWindow($proc.MainWindowHandle, [Win32Mouse]::SW_RESTORE)
            [Win32Mouse]::SetForegroundWindow($proc.MainWindowHandle)
            Start-Sleep -Milliseconds 500
            return $true
        }
    }
    return $false
}

function Get-OADProcess {
    <#
    .SYNOPSIS
        Get Oracle Analytics Desktop process(es).
    #>
    $procs = Get-Process | Where-Object {
        ($_.Path -and $_.Path -match "Oracle.*Analytics") -or
        ($_.ProcessName -match "OAD|dvdesktop|analyticsdesktop") -or
        ($_.MainWindowTitle -match "Oracle.*Analytics")
    }
    return $procs
}

function Kill-OADProcesses {
    <#
    .SYNOPSIS
        Kill all Oracle Analytics Desktop processes.
    #>
    # Kill dvdesktop directly (confirmed process name)
    Get-Process dvdesktop -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    # Also kill by path/title match
    $procs = Get-OADProcess
    foreach ($proc in $procs) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
    # Also kill any Java processes associated with OAD
    Get-Process java -ErrorAction SilentlyContinue | Where-Object {
        $_.Path -and $_.Path -match "Oracle.*Analytics"
    } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
}
