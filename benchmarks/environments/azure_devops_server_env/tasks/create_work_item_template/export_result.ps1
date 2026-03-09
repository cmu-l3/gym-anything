# NOTE: This is a PowerShell script (export_result.ps1) for the Windows environment.

Write-Host "=== Exporting Create Work Item Template Result ==="

# Define variables
$collectionUrl = "http://localhost/DefaultCollection"
$project = "TailwindTraders"
$team = "TailwindTraders Team"
$user = "Docker"
$pass = "GymAnything123!"
$pair = "$($user):$($pass)"
$encodedCreds = [Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes($pair))
$headers = @{ Authorization = "Basic $encodedCreds" }
$outputFile = "C:\Users\Docker\task_results\template_result.json"

# Ensure output directory exists
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\task_results" | Out-Null

# 1. Query for the template
Write-Host "Querying templates..."
$templateData = @{
    template_found = $false
    template_name = $null
    work_item_type = $null
    fields = @{}
    created_after_start = $false
}

try {
    $templatesUrl = "$collectionUrl/$project/$team/_apis/wit/templates?workitemtypename=Bug&api-version=6.0"
    $response = Invoke-RestMethod -Uri $templatesUrl -Method Get -Headers $headers -ErrorAction Stop
    
    $targetName = "Frontend Bug Report"
    $match = $response.value | Where-Object { $_.name -eq $targetName }
    
    if ($match) {
        Write-Host "Template found!"
        $templateData.template_found = $true
        $templateData.template_name = $match.name
        $templateData.work_item_type = $match.workItemTypeName
        $templateData.fields = $match.fields
        
        # NOTE: The List Template API doesn't always return creation date.
        # We rely on the fact that we deleted it in setup.
        $templateData.created_after_start = $true 
    } else {
        Write-Host "Template '$targetName' not found."
        # List what was found for debugging
        $templateData.found_names = ($response.value | Select-Object -ExpandProperty name)
    }
} catch {
    Write-Host "Error querying API: $($_.Exception.Message)"
    $templateData.error = $_.Exception.Message
}

# 2. Capture Final Screenshot
Write-Host "Taking final screenshot..."
Add-Type -AssemblyName System.Windows.Forms
$screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Location, [System.Drawing.Point]::Empty, $screen.Size)
$bitmap.Save("C:\Users\Docker\task_final.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

# 3. Save Result JSON
$json = $templateData | ConvertTo-Json -Depth 5
$json | Out-File $outputFile -Encoding ascii

Write-Host "Result saved to $outputFile"
Write-Host $json
Write-Host "=== Export Complete ==="