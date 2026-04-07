#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
powershell.exe -Command "
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
\$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
\$gfx = [System.Drawing.Graphics]::FromImage(\$bmp)
\$gfx.CopyFromScreen(0, 0, 0, 0, \$bmp.Size)
\$bmp.Save('C:\tmp\task_final.png', [System.Drawing.Imaging.ImageFormat]::Png)
\$gfx.Dispose()
\$bmp.Dispose()
"

# Create a robust PowerShell script to extract config state (avoids quote escaping hell)
powershell.exe -Command "
\$code = @'
\$result = @{ ini_content = \"\"; registry_content = \"\" }
\$iniPath = \"\$env:APPDATA\bcWebCam\bcWebCam.ini\"
if (Test-Path \$iniPath) { 
    \$result.ini_content = Get-Content \$iniPath -Raw 
}
\$regPath1 = \"HKCU:\Software\bcWebCam\"
if (Test-Path \$regPath1) { 
    \$result.registry_content += (Get-ItemProperty \$regPath1 -ErrorAction SilentlyContinue | Out-String) 
}
\$regPath2 = \"HKCU:\Software\AIT\bcWebCam\"
if (Test-Path \$regPath2) { 
    \$result.registry_content += \"`n\" + (Get-ItemProperty \$regPath2 -ErrorAction SilentlyContinue | Out-String) 
}
\$result | ConvertTo-Json -Depth 3 | Out-File -FilePath C:\tmp\task_result_data.json -Encoding ascii
'@
Set-Content -Path C:\tmp\extract.ps1 -Value \$code
"

# Run extraction
powershell.exe -ExecutionPolicy Bypass -File C:\\tmp\\extract.ps1

# Read extracted JSON (Check multiple possible mount paths)
PS_JSON=$(cat /c/tmp/task_result_data.json 2>/dev/null || cat /mnt/c/tmp/task_result_data.json 2>/dev/null || cat /tmp/task_result_data.json 2>/dev/null || echo "{}")

# Merge into final output JSON
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_data": $PS_JSON,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="