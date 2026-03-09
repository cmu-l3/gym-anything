#!/bin/bash
echo "=== Exporting Regional Settings Result ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Fallback screenshot logic
if [ ! -f /tmp/task_final.png ]; then
    powershell.exe -Command "
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save('C:\tmp\task_final.png')" 2>/dev/null || true
    
    if [ -f "/c/tmp/task_final.png" ]; then
        mv /c/tmp/task_final.png /tmp/task_final.png
    fi
fi

# Use PowerShell to extract Registry configuration for verification
cat > /tmp/verify_copper.ps1 << 'PS_EOF'
$regPath = "HKCU:\Software\NCH Software\Copper"
$result = @{
    registry_found = $false
    currency_symbol = ""
    date_format = ""
    tax_name = ""
    all_settings_dump = ""
}

if (Test-Path $regPath) {
    $result.registry_found = $true
    
    # Dump all properties recursively to a string for fuzzy matching
    # This helps if keys are named slightly differently in different versions
    $dump = Get-ChildItem -Path $regPath -Recurse | ForEach-Object {
        $key = $_
        Get-ItemProperty -Path $key.PSPath | Select-Object * | Out-String
    }
    $result.all_settings_dump = $dump

    # Try to find specific known keys (Best Effort)
    # These paths are educated guesses for NCH software structure
    try {
        $settings = Get-ItemProperty -Path "$regPath\Settings" -ErrorAction SilentlyContinue
        if ($settings) {
            $result.currency_symbol = $settings.CurrencySymbol
            $result.date_format = $settings.DateFormat
        }
    } catch {}

    try {
        # Tax names are often stored in a subkey or indexed list
        $taxes = Get-ChildItem -Path "$regPath\Tax" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
             Get-ItemProperty -Path $_.PSPath
        }
        # Also check main Tax key
        $mainTax = Get-ItemProperty -Path "$regPath\Tax" -ErrorAction SilentlyContinue
        
        # Combine all tax related strings to search for "VAT"
        $result.tax_name = "$($taxes | Out-String) $($mainTax | Out-String)"
    } catch {}
}

# Convert to JSON
$result | ConvertTo-Json -Depth 5
PS_EOF

# Run extraction and save to JSON
powershell.exe -ExecutionPolicy Bypass -File /tmp/verify_copper.ps1 > /tmp/registry_export.json

# Check if app is still running
APP_RUNNING="false"
if powershell.exe -Command "Get-Process copper -ErrorAction SilentlyContinue" >/dev/null; then
    APP_RUNNING="true"
fi

# Clean up JSON output (sometimes PowerShell adds headers/footers)
# We expect pure JSON from the script, but extracting it specifically is safer
grep -v "^WARNING" /tmp/registry_export.json > /tmp/registry_clean.json || true

# Combine into final result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_was_running": $APP_RUNNING,
    "registry_data": $(cat /tmp/registry_clean.json || echo "{}"),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="