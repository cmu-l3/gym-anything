# Note: This is a PowerShell script saved with .ps1 extension
$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Results ==="

$ResultPath = "C:\Users\Docker\task_result.json"
$ProjectName = "TailwindTraders"
$CollectionUrl = "http://localhost/DefaultCollection"
$BaseUrl = "$CollectionUrl/$ProjectName/_apis"

# Data containers
$vgExists = $false
$varsCorrect = $false
$secretIsSecret = $false
$yamlUpdated = $false
$yamlContent = ""
$foundVars = @{}

# 1. Check Variable Group
try {
    $vgUrl = "$BaseUrl/distributedtask/variablegroups?groupName=PaymentService-Prod&api-version=6.0-preview.1"
    $vgs = Invoke-RestMethod -Uri $vgUrl -UseDefaultCredentials -Method Get
    
    if ($vgs.count -gt 0) {
        $vgExists = $true
        $group = $vgs.value[0]
        
        # Check Variables
        $vars = $group.variables
        
        # Check specific values
        if ($vars.Gateway_Url.value -eq "https://api.stripe.com/v1") { $foundVars["Gateway_Url"] = $true }
        if ($vars.Region_Code.value -eq "us-east-1") { $foundVars["Region_Code"] = $true }
        
        # Check Secret
        if ($vars.Live_Secret_Key.isSecret -eq $true) {
             $secretIsSecret = $true 
             # Note: We cannot check the value of a secret, only that it is set as secret
        }
        
        if ($foundVars.Count -eq 2) { $varsCorrect = $true }
    }
} catch {
    Write-Host "Error checking variable group: $_"
}

# 2. Check Pipeline YAML
try {
    $yamlUrl = "$BaseUrl/git/repositories/$ProjectName/items?path=/azure-pipelines.yml&versionDescriptor.version=main&includeContent=true&api-version=6.0"
    $yamlResponse = Invoke-RestMethod -Uri $yamlUrl -UseDefaultCredentials
    $yamlContent = $yamlResponse.content
    
    # Simple check for the string
    if ($yamlContent -match "group:\s*PaymentService-Prod") {
        $yamlUpdated = $true
    }
} catch {
    Write-Host "Error checking YAML: $_"
}

# 3. Capture Final Screenshot
$scriptBlock = {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    $bitmap.Save("C:\Users\Docker\task_final.png")
    $graphics.Dispose()
    $bitmap.Dispose()
}
try {
    Invoke-Command -ScriptBlock $scriptBlock
} catch {
    Write-Host "Screenshot failed: $_"
}

# 4. Export JSON
$result = @{
    vg_exists = $vgExists
    vars_correct = $varsCorrect
    secret_secure = $secretIsSecret
    yaml_updated = $yamlUpdated
    yaml_content_sample = $yamlContent # Sending content for python verifier to parse if needed
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $ResultPath -Encoding ascii

Write-Host "Export complete. Result saved to $ResultPath"
Get-Content $ResultPath