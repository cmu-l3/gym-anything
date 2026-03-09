Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Install Microsoft Office (Excel only) using Office Deployment Tool.
# This script runs as the pre_start hook.

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing Microsoft Excel ==="

    # Check if Excel is already installed
    $excelPath = Get-ChildItem "C:\Program Files\Microsoft Office" -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue
    if ($excelPath) {
        Write-Host "Excel is already installed at: $($excelPath.FullName)"
        return
    }

    # Also check Program Files (x86)
    $excelPath86 = Get-ChildItem "C:\Program Files (x86)\Microsoft Office" -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue
    if ($excelPath86) {
        Write-Host "Excel is already installed at: $($excelPath86.FullName)"
        return
    }

# Create working directory
$workDir = "C:\ODTSetup"
New-Item -ItemType Directory -Force -Path $workDir | Out-Null

# Download Office Deployment Tool
Write-Host "Downloading Office Deployment Tool..."
$odtUrl = "https://officecdn.microsoft.com/pr/wsus/setup.exe"
$odtPath = "$workDir\setup.exe"
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $odtUrl -OutFile $odtPath -UseBasicParsing
Write-Host "ODT downloaded to: $odtPath"

# Create configuration XML - install ONLY Excel to minimize download size
$configXml = @"
<Configuration>
  <Add OfficeClientEdition="64" Channel="Current">
    <Product ID="O365ProPlusRetail">
      <Language ID="en-us" />
      <ExcludeApp ID="Access" />
      <ExcludeApp ID="Groove" />
      <ExcludeApp ID="Lync" />
      <ExcludeApp ID="OneDrive" />
      <ExcludeApp ID="OneNote" />
      <ExcludeApp ID="Outlook" />
      <ExcludeApp ID="PowerPoint" />
      <ExcludeApp ID="Publisher" />
      <ExcludeApp ID="Teams" />
      <ExcludeApp ID="Word" />
    </Product>
  </Add>
  <Display Level="None" AcceptEULA="TRUE" />
  <Property Name="AUTOACTIVATE" Value="0" />
  <Property Name="FORCEAPPSHUTDOWN" Value="TRUE" />
  <Updates Enabled="FALSE" />
</Configuration>
"@
$configPath = "$workDir\config.xml"
$configXml | Out-File -FilePath $configPath -Encoding UTF8
Write-Host "Configuration XML created at: $configPath"

# Run Office installation (silent)
Write-Host "Starting Office installation (Excel only)... This may take 10-20 minutes."
$process = Start-Process -FilePath $odtPath -ArgumentList "/configure `"$configPath`"" -Wait -PassThru -NoNewWindow
Write-Host "Installation process exited with code: $($process.ExitCode)"

# Verify installation
$excelInstalled = Get-ChildItem "C:\Program Files\Microsoft Office" -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue
if ($excelInstalled) {
    Write-Host "Excel installed successfully at: $($excelInstalled.FullName)"
} else {
    Write-Host "WARNING: Excel installation may have failed. Checking alternative locations..."
    # Check if it's in the ClickToRun location
    $c2rExcel = Get-ChildItem "C:\Program Files\Microsoft Office 15" -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue
    if (-not $c2rExcel) {
        $c2rExcel = Get-ChildItem "C:\Program Files\Microsoft Office" -Recurse -Filter "EXCEL.EXE" -ErrorAction SilentlyContinue
    }
    if ($c2rExcel) {
        Write-Host "Excel found at: $($c2rExcel.FullName)"
    } else {
        Write-Host "ERROR: Could not find Excel after installation."
        # List what is in Program Files\Microsoft Office for debugging
        if (Test-Path "C:\Program Files\Microsoft Office") {
            Write-Host "Contents of C:\Program Files\Microsoft Office:"
            Get-ChildItem "C:\Program Files\Microsoft Office" -Recurse | Select-Object FullName | Format-Table -AutoSize
        }
    }
}

# Cleanup ODT files
Remove-Item -Path $workDir -Recurse -Force -ErrorAction SilentlyContinue

    Write-Host "=== Excel installation complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
