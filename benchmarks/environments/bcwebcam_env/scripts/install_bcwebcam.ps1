Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\env_setup_pre_start.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Installing bcWebCam Environment ==="

    # -------------------------------------------------------------------
    # 1. Create working directories
    # -------------------------------------------------------------------
    $tempDir = "C:\temp\bcwebcam_install"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Desktop\Barcodes" | Out-Null
    New-Item -ItemType Directory -Force -Path "C:\Users\Docker\AppData\Local\bcWebCam" | Out-Null

    # -------------------------------------------------------------------
    # 2. Install .NET Framework 4.8 (required by bcWebCam)
    #    Windows 11 ships with .NET 4.8 built-in, so this is a safety check.
    # -------------------------------------------------------------------
    Write-Host "--- Checking .NET Framework 4.8 ---"
    $ndpKey = "HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    if (Test-Path $ndpKey) {
        $release = (Get-ItemProperty $ndpKey).Release
        if ($release -ge 528040) {
            Write-Host ".NET Framework 4.8 or later is already installed (release=$release)"
        } else {
            Write-Host ".NET 4.8 not found (release=$release), attempting install..."
            $ndpUrl = "https://go.microsoft.com/fwlink/?linkid=2088631"
            $ndpPath = "$tempDir\ndp48-web.exe"
            Invoke-WebRequest -Uri $ndpUrl -OutFile $ndpPath -UseBasicParsing
            Start-Process $ndpPath -ArgumentList "/quiet /norestart" -Wait
            Write-Host ".NET Framework 4.8 installed"
        }
    } else {
        Write-Host ".NET 4 registry key not found, attempting full install..."
        $ndpUrl = "https://go.microsoft.com/fwlink/?linkid=2088631"
        $ndpPath = "$tempDir\ndp48-web.exe"
        Invoke-WebRequest -Uri $ndpUrl -OutFile $ndpPath -UseBasicParsing
        Start-Process $ndpPath -ArgumentList "/quiet /norestart" -Wait
    }

    # -------------------------------------------------------------------
    # 3. Download and install bcWebCam
    # -------------------------------------------------------------------
    Write-Host "--- Downloading bcWebCam ---"

    $bcWebCamZip = "$tempDir\bcwebcam_en.zip"
    $bcWebCamDir = "C:\Program Files\bcWebCam"

    # Try multiple download sources with fallbacks
    # Correct URL found by scraping the official download page
    $downloadUrls = @(
        "https://bcwebcam.de/wp-content/uploads/area-en/bcwebcam_en.zip",
        "https://bcwebcam.de/wp-content/uploads/sites/4/2022/03/bcwebcam_en.zip"
    )

    $downloaded = $false
    foreach ($url in $downloadUrls) {
        try {
            Write-Host "Trying: $url"
            Invoke-WebRequest -Uri $url -OutFile $bcWebCamZip -UseBasicParsing -TimeoutSec 120
            if ((Test-Path $bcWebCamZip) -and (Get-Item $bcWebCamZip).Length -gt 1MB) {
                Write-Host "Downloaded successfully from $url"
                $downloaded = $true
                break
            }
        } catch {
            Write-Host "Failed from $url : $($_.Exception.Message)"
        }
    }

    # Fallback: try filehorse via redirect
    if (-not $downloaded) {
        try {
            Write-Host "Trying FileHorse download..."
            $fhUrl = "https://www.filehorse.com/download-bcwebcam/download/"
            Invoke-WebRequest -Uri $fhUrl -OutFile $bcWebCamZip -UseBasicParsing -TimeoutSec 180
            if ((Test-Path $bcWebCamZip) -and (Get-Item $bcWebCamZip).Length -gt 1MB) {
                Write-Host "Downloaded successfully from FileHorse"
                $downloaded = $true
            }
        } catch {
            Write-Host "FileHorse download failed: $($_.Exception.Message)"
        }
    }

    # Fallback: check if installer was provided in mounted data
    if (-not $downloaded) {
        $mountedZip = "C:\workspace\data\bcwebcam_en.zip"
        $mountedExe = "C:\workspace\data\bcWebCam_setup.exe"
        if (Test-Path $mountedZip) {
            Write-Host "Using installer from mounted data directory"
            Copy-Item $mountedZip $bcWebCamZip -Force
            $downloaded = $true
        } elseif (Test-Path $mountedExe) {
            Write-Host "Using EXE installer from mounted data directory"
            Copy-Item $mountedExe "$tempDir\bcWebCam_setup.exe" -Force
            $downloaded = $true
        }
    }

    if (-not $downloaded) {
        throw "ERROR: Could not download bcWebCam from any source. Place bcwebcam_en.zip in data/ directory."
    }

    Write-Host "--- Installing bcWebCam ---"
    New-Item -ItemType Directory -Force -Path $bcWebCamDir | Out-Null

    # Handle ZIP archive — contains setup.exe and bcWebCamSetup.en.msi
    if (Test-Path $bcWebCamZip) {
        $extractDir = "$tempDir\bcwebcam_extracted"
        Expand-Archive -Path $bcWebCamZip -DestinationPath $extractDir -Force
        Write-Host "Extracted archive contents:"
        Get-ChildItem $extractDir -Recurse | ForEach-Object { Write-Host "  $($_.FullName)" }

        # Prefer MSI for silent install (msiexec /qn)
        $msiFile = Get-ChildItem $extractDir -Recurse -Filter "*.msi" | Select-Object -First 1
        if ($msiFile) {
            Write-Host "Found MSI installer: $($msiFile.FullName)"
            $installResult = Start-Process "msiexec" -ArgumentList "/i `"$($msiFile.FullName)`" /qn /norestart" -Wait -PassThru
            $exitCode = $installResult.ExitCode
            Write-Host "MSI install exit code: $exitCode"
            # Exit code 3010 = reboot recommended (NOT an error)
            if ($exitCode -ne 0 -and $exitCode -ne 3010) {
                Write-Host "WARNING: MSI install returned exit code $exitCode"
                # Fallback: try setup.exe
                $setupExe = Get-ChildItem $extractDir -Recurse -Filter "setup.exe" | Select-Object -First 1
                if ($setupExe) {
                    Write-Host "Falling back to setup.exe: $($setupExe.FullName)"
                    $installResult2 = Start-Process $setupExe.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru
                    Write-Host "setup.exe exit code: $($installResult2.ExitCode)"
                }
            }
        } else {
            # No MSI — try setup.exe
            $setupExe = Get-ChildItem $extractDir -Recurse -Filter "setup.exe" | Select-Object -First 1
            if ($setupExe) {
                Write-Host "Found setup.exe: $($setupExe.FullName)"
                $installResult = Start-Process $setupExe.FullName -ArgumentList "/VERYSILENT /SUPPRESSMSGBOXES /NORESTART" -Wait -PassThru
                Write-Host "setup.exe exit code: $($installResult.ExitCode)"
            } else {
                Write-Host "No installer found, copying files directly..."
                Get-ChildItem $extractDir -Recurse | Where-Object { -not $_.PSIsContainer } | ForEach-Object {
                    $relPath = $_.FullName.Substring($extractDir.Length)
                    $destPath = Join-Path $bcWebCamDir $relPath
                    $destDir = Split-Path $destPath -Parent
                    New-Item -ItemType Directory -Force -Path $destDir | Out-Null
                    Copy-Item $_.FullName $destPath -Force
                }
            }
        }

        # Also copy the .default config file if present
        $defaultCfg = Get-ChildItem $extractDir -Recurse -Filter "bcWebCam.default" | Select-Object -First 1
        if ($defaultCfg) {
            Copy-Item $defaultCfg.FullName "C:\Users\Docker\AppData\Local\bcWebCam\bcWebCam.default" -Force
            Write-Host "Copied bcWebCam.default config"
        }

        # Copy license file if present
        $licFile = Get-ChildItem $extractDir -Recurse -Filter "qsbc.lic" | Select-Object -First 1
        if ($licFile) {
            Copy-Item $licFile.FullName "C:\Users\Docker\AppData\Local\bcWebCam\qsbc.lic" -Force
            Write-Host "Copied qsbc.lic license file"
        }
    }

    # Verify installation — search common install locations
    Write-Host "--- Verifying bcWebCam installation ---"
    $bcExe = $null
    $searchDirs = @(
        "C:\Program Files\bcWebCam",
        "C:\Program Files (x86)\bcWebCam",
        "C:\Program Files\QualitySoft",
        "C:\Program Files (x86)\QualitySoft"
    )
    foreach ($dir in $searchDirs) {
        $found = Get-ChildItem $dir -Recurse -Filter "bcWebCam.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($found) { $bcExe = $found; break }
    }
    # Broader search if not found in expected locations
    if (-not $bcExe) {
        $bcExe = Get-ChildItem "C:\Program Files", "C:\Program Files (x86)" -Recurse -Filter "bcWebCam.exe" -ErrorAction SilentlyContinue | Select-Object -First 1
    }

    if ($bcExe) {
        Write-Host "bcWebCam found at: $($bcExe.FullName)"
        # Save path for later use
        Set-Content -Path "C:\Users\Docker\bcwebcam_path.txt" -Value $bcExe.FullName -Encoding UTF8
    } else {
        Write-Host "WARNING: bcWebCam.exe not found after installation."
        Write-Host "Listing installed programs..."
        Get-ChildItem "C:\Program Files" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  PF: $($_.Name)" }
        Get-ChildItem "C:\Program Files (x86)" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  PFx86: $($_.Name)" }
    }

    # -------------------------------------------------------------------
    # 4. Install Python 3 for barcode generation
    # -------------------------------------------------------------------
    Write-Host "--- Installing Python 3 ---"

    $pythonExe = $null
    # Check if Python is already installed
    $existingPython = Get-Command python -ErrorAction SilentlyContinue
    if ($existingPython) {
        $pythonExe = $existingPython.Source
        Write-Host "Python already installed: $pythonExe"
    } else {
        $pyUrl = "https://www.python.org/ftp/python/3.11.9/python-3.11.9-amd64.exe"
        $pyInstaller = "$tempDir\python-3.11.9-amd64.exe"
        Invoke-WebRequest -Uri $pyUrl -OutFile $pyInstaller -UseBasicParsing -TimeoutSec 300
        Start-Process $pyInstaller -ArgumentList "/quiet InstallAllUsers=1 PrependPath=1 Include_pip=1" -Wait
        # Refresh PATH
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
        $pythonExe = "C:\Program Files\Python311\python.exe"
        if (-not (Test-Path $pythonExe)) {
            $pythonExe = "C:\Python311\python.exe"
        }
        Write-Host "Python installed at: $pythonExe"
    }

    # Install barcode generation libraries
    # Temporarily relax ErrorActionPreference — pip writes warnings to stderr
    Write-Host "--- Installing Python barcode libraries ---"
    $prevEAP = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        & $pythonExe -m pip install --quiet python-barcode "qrcode[pil]" Pillow 2>&1 | ForEach-Object { Write-Host $_ }
        Write-Host "Python barcode libraries installed"
    } catch {
        Write-Host "WARNING: pip install failed: $($_.Exception.Message)"
    } finally {
        $ErrorActionPreference = $prevEAP
    }

    # -------------------------------------------------------------------
    # 5. Generate barcode images from real product data
    # -------------------------------------------------------------------
    Write-Host "--- Generating barcode images ---"

    $barcodeScript = @'
import csv
import os
import sys

try:
    import barcode
    from barcode.writer import ImageWriter
except ImportError:
    print("python-barcode not available, skipping EAN generation")
    barcode = None

try:
    import qrcode
except ImportError:
    print("qrcode not available, skipping QR generation")
    qrcode = None

output_dir = r"C:\Users\Docker\Desktop\Barcodes"
os.makedirs(output_dir, exist_ok=True)

# Generate EAN-13 barcodes from real product data
if barcode:
    csv_path = r"C:\workspace\data\barcodes\product_barcodes.csv"
    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                ean = row['ean13'].strip()
                name = row['product_name'].strip().replace(' ', '_')
                try:
                    ean13 = barcode.get('ean13', ean, writer=ImageWriter())
                    filename = ean13.save(os.path.join(output_dir, f"ean13_{ean}"))
                    print(f"Generated: {filename} ({name})")
                except Exception as e:
                    print(f"Error generating {ean}: {e}")
    else:
        print(f"Product barcodes CSV not found at {csv_path}")

# Generate QR codes from real data
if qrcode:
    csv_path = r"C:\workspace\data\barcodes\qr_codes.csv"
    if os.path.exists(csv_path):
        with open(csv_path, 'r') as f:
            reader = csv.DictReader(f)
            for i, row in enumerate(reader):
                data = row['data'].strip().replace('\\n', '\n')
                label = row['label'].strip().replace(' ', '_')
                try:
                    qr = qrcode.QRCode(version=1, box_size=10, border=5)
                    qr.add_data(data)
                    qr.make(fit=True)
                    img = qr.make_image(fill_color="black", back_color="white")
                    filepath = os.path.join(output_dir, f"qr_{label}.png")
                    img.save(filepath)
                    print(f"Generated: {filepath}")
                except Exception as e:
                    print(f"Error generating QR {label}: {e}")
    else:
        print(f"QR codes CSV not found at {csv_path}")

print(f"\nBarcode images saved to: {output_dir}")
print(f"Total files: {len(os.listdir(output_dir))}")
'@

    $scriptPath = "$tempDir\generate_barcodes.py"
    Set-Content -Path $scriptPath -Value $barcodeScript -Encoding UTF8

    try {
        & $pythonExe $scriptPath
        Write-Host "Barcode images generated successfully"
    } catch {
        Write-Host "WARNING: Barcode generation failed: $($_.Exception.Message)"
    }

    # -------------------------------------------------------------------
    # 7. Copy barcode data to desktop for easy access
    # -------------------------------------------------------------------
    Copy-Item "C:\workspace\data\barcodes\product_barcodes.csv" "C:\Users\Docker\Desktop\Barcodes\" -Force -ErrorAction SilentlyContinue
    Copy-Item "C:\workspace\data\barcodes\qr_codes.csv" "C:\Users\Docker\Desktop\Barcodes\" -Force -ErrorAction SilentlyContinue

    Write-Host "=== bcWebCam Environment Installation Complete ==="

} catch {
    Write-Host "FATAL ERROR: $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    throw
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
