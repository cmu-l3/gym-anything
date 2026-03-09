# NOTE: The environment is Windows, so this is actually a PowerShell script.
# The filename in task.json points to .ps1, but I am providing the content here.
# Since the prompt asks for setup_task.sh, I will provide the content compatible with the
# environment's shell (PowerShell) but wrapped in the requested block format.
# Wait, the prompt examples use .sh for Linux and .ps1 for Windows in the JSON hooks.
# I will output setup_task.ps1 content inside the block.

Write-Host "=== Setting up Create Work Item Template Task ==="

# Define variables
$collectionUrl = "http://localhost/DefaultCollection"
$project = "TailwindTraders"
$team = "TailwindTraders Team"
$user = "Docker"
$pass = "GymAnything123!"
$pair = "$($user):$($pass)"
$encodedCreds = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $encodedCreds" }

# 1. Clean up: Delete the template if it already exists (to prevent pre-completed state)
Write-Host "Checking for existing templates..."
try {
    $templatesUrl = "$collectionUrl/$project/$team/_apis/wit/templates?workitemtypename=Bug&api-version=6.0"
    $response = Invoke-RestMethod -Uri $templatesUrl -Method Get -Headers $headers -ErrorAction Stop
    
    $targetName = "Frontend Bug Report"
    $existing = $response.value | Where-Object { $_.name -eq $targetName }
    
    if ($existing) {
        Write-Host "Found existing template '$targetName' (ID: $($existing.id)). Deleting..."
        $deleteUrl = "$collectionUrl/$project/$team/_apis/wit/templates/$($existing.id)?api-version=6.0"
        Invoke-RestMethod -Uri $deleteUrl -Method Delete -Headers $headers
        Write-Host "Template deleted."
    } else {
        Write-Host "No existing template found. Clean start."
    }
} catch {
    Write-Host "Warning: Failed to cleanup templates. API might be inaccessible or project not ready."
    Write-Host $_.Exception.Message
}

# 2. Record Start Time
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File "C:\Users\Docker\task_start_time.txt" -Encoding ascii

# 3. Ensure Browser is Open to the Project
Write-Host "Launching Microsoft Edge..."
Stop-Process -Name "msedge" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$targetUrl = "$collectionUrl/$project/_boards/board/t/$team/Backlog items"
Start-Process "msedge" $targetUrl
Start-Sleep -Seconds 5

# 4. Maximize Window (using a simple powershell trick or assumes agent handles it)
# In this environment, we rely on the agent or subsequent interactions, 
# but we can try to ensure it's foreground.
$wsh = New-Object -ComObject WScript.Shell
$wsh.AppActivate("Microsoft Edge")

# 5. Take Initial Screenshot
Write-Host "Taking initial screenshot..."
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
$bitmap.Save("C:\Users\Docker\task_initial.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

Write-Host "=== Task Setup Complete ==="