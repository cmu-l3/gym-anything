# Note: This is a PowerShell script saved with .ps1 extension.
# Real filename: export_result.ps1

Write-Host "=== Exporting Results ==="

# 1. Paths
$desktopPath = "C:\Users\Docker\Desktop"
$pbixPath = "$desktopPath\Shrinkage_Report.pbix"
$csvPath = "$desktopPath\worst_stores.csv"
$inputCsvPath = "$desktopPath\PowerBITasks\inventory_audit.csv"
$resultJsonPath = "$desktopPath\shrinkage_result.json"
$startTimePath = "C:\Users\Docker\AppData\Local\Temp\task_start_time.txt"

# 2. Get Timestamps
$taskStart = 0
if (Test-Path $startTimePath) {
    $taskStart = Get-Content $startTimePath
}
$taskEnd = [DateTimeOffset]::Now.ToUnixTimeSeconds()

# 3. Analyze PBIX (Unzip and search strings)
$pbixExists = Test-Path $pbixPath
$pbixSize = 0
$layoutSample = ""
$modelSample = ""

if ($pbixExists) {
    $pbixSize = (Get-Item $pbixPath).Length
    
    # Create temp dir for extraction
    $tempDir = "C:\Users\Docker\AppData\Local\Temp\pbix_extract_$(Get-Random)"
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    
    # Unzip (PBIX is a ZIP container)
    Expand-Archive -Path $pbixPath -DestinationPath $tempDir -Force
    
    # Read Layout file (JSON)
    $layoutPath = "$tempDir\Report\Layout"
    if (Test-Path $layoutPath) {
        # Read as UCS-2 LE BOM or UTF-8
        $layoutSample = Get-Content $layoutPath -Raw -Encoding Unicode -ErrorAction SilentlyContinue
        if (-not $layoutSample) {
             $layoutSample = Get-Content $layoutPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
        }
    }
    
    # Read DataModel file (Binary, but we check for strings)
    $modelPath = "$tempDir\DataModel"
    if (Test-Path $modelPath) {
        # Read first 1MB just to grep strings
        $bytes = Get-Content $modelPath -Encoding Byte -TotalCount 1000000
        $modelSample = [System.Text.Encoding]::ASCII.GetString($bytes)
    }
    
    # Cleanup
    Remove-Item -Path $tempDir -Recurse -Force
}

# 4. Analyze Exported CSV
$csvExists = Test-Path $csvPath
$csvContent = ""
if ($csvExists) {
    $csvContent = Get-Content $csvPath -Raw -TotalCount 20
}

# 5. Calculate Ground Truth (using Python)
$groundTruthScript = @"
import pandas as pd
import json

try:
    # Load input data
    df = pd.read_csv(r'$inputCsvPath')
    
    # Replicate logic: Variance = (Phys - Sys) * Cost
    df['Variance_Value'] = (df['Physical_Qty'] - df['System_Qty']) * df['Unit_Cost']
    
    # Replicate logic: Shrinkage = ABS(SUM(Negative Variance))
    # Filter for negative only
    negative_variances = df[df['Variance_Value'] < 0]
    total_shrinkage = abs(negative_variances['Variance_Value'].sum())
    
    # Group by Store
    store_shrinkage = negative_variances.groupby('Store_ID')['Variance_Value'].sum().abs().reset_index()
    store_shrinkage.columns = ['Store_ID', 'Shrinkage_Loss']
    store_shrinkage = store_shrinkage.sort_values('Shrinkage_Loss', ascending=False)
    
    top_store = store_shrinkage.iloc[0]['Store_ID']
    top_loss = store_shrinkage.iloc[0]['Shrinkage_Loss']
    
    result = {
        'total_shrinkage_truth': float(total_shrinkage),
        'top_store_truth': top_store,
        'top_loss_truth': float(top_loss)
    }
    print(json.dumps(result))
except Exception as e:
    print(json.dumps({'error': str(e)}))
"@

$groundTruthJson = python -c $groundTruthScript

# 6. Create Result JSON
$resultObject = @{
    task_start = $taskStart
    task_end = $taskEnd
    pbix_exists = $pbixExists
    pbix_size_bytes = $pbixSize
    csv_exists = $csvExists
    csv_sample = $csvContent
    layout_search = $layoutSample
    model_search = $modelSample
    ground_truth = $groundTruthJson
}

$resultObject | ConvertTo-Json -Depth 5 | Set-Content -Path $resultJsonPath
Write-Host "Result exported to $resultJsonPath"