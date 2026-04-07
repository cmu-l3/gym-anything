# setup_task.ps1 (Powershell script disguised as .sh for the prompt format, but content is PS1)
# The prompt requested setup_task.sh but the environment uses PowerShell hooks. 
# I will provide the content as a PowerShell script since the hooks in task.json point to .ps1 files.

# START OF POWERSHELL SCRIPT
$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Nutrition Label Generator Task ==="

# 1. Define Paths
$DesktopPath = [Environment]::GetFolderPath("Desktop")
$TaskFolder = Join-Path $DesktopPath "ExcelTasks"
$ExcelFilePath = Join-Path $TaskFolder "nutrition_calculator.xlsx"
$StartTimePath = "C:\tmp\task_start_time.txt"
$InitialHashPath = "C:\tmp\initial_file_hash.txt"

# 2. Create Task Folder
if (-not (Test-Path $TaskFolder)) {
    New-Item -ItemType Directory -Path $TaskFolder -Force | Out-Null
}

# 3. Generate Data File using Python (available in env)
# We use Python to generate a clean XLSX with multiple sheets
$GenScript = "C:\tmp\gen_nutrition_data.py"
@'
import pandas as pd
import os

file_path = r"C:\Users\Docker\Desktop\ExcelTasks\nutrition_calculator.xlsx"

# 1. Ingredient DB Data
db_data = {
    "Ingredient": ["Butter, Salted", "Rolled Oats", "All Purpose Flour", "White Sugar", "Brown Sugar", "Eggs, Raw", "Dried Cranberries", "Walnuts", "Baking Soda", "Salt"],
    "Calories_100g": [717, 379, 364, 387, 380, 143, 308, 654, 0, 0],
    "Fat_100g": [81.0, 6.0, 1.0, 0.0, 0.0, 9.5, 1.4, 65.0, 0.0, 0.0],
    "Sodium_100g": [576, 2, 2, 1, 28, 142, 5, 2, 27300, 38700],
    "Carb_100g": [0.0, 68.7, 76.0, 100.0, 98.0, 0.7, 82.0, 14.0, 0.0, 0.0],
    "Fiber_100g": [0.0, 10.0, 2.7, 0.0, 0.0, 0.0, 5.7, 6.7, 0.0, 0.0],
    "Sugar_100g": [0.0, 1.0, 0.3, 100.0, 97.0, 0.4, 65.0, 2.6, 0.0, 0.0],
    "Protein_100g": [0.8, 13.5, 10.0, 0.0, 0.0, 12.6, 0.1, 15.0, 0.0, 0.0]
}
df_db = pd.DataFrame(db_data)

# 2. Recipe Data
recipe_data = {
    "Ingredient": ["Rolled Oats", "All Purpose Flour", "Butter, Salted", "Brown Sugar", "White Sugar", "Eggs, Raw", "Dried Cranberries", "Walnuts", "Baking Soda", "Salt"],
    "Weight_g": [500, 600, 450, 400, 200, 200, 300, 150, 15, 10]
}
df_recipe = pd.DataFrame(recipe_data)

# 3. Nutrition Facts Template (Empty)
labels = ["Calories", "Total Fat (g)", "Sodium (mg)", "Total Carbohydrate (g)", "Dietary Fiber (g)", "Sugars (g)", "Protein (g)"]
df_label = pd.DataFrame({"Nutrient": labels, "Value": [None]*7})

# Create Excel Writer
with pd.ExcelWriter(file_path, engine='openpyxl') as writer:
    df_recipe.to_excel(writer, sheet_name='Recipe', index=False, startrow=0)
    df_db.to_excel(writer, sheet_name='Ingredient_DB', index=False)
    df_label.to_excel(writer, sheet_name='Nutrition_Facts', index=False, startrow=2, startcol=1)
    
    # Access workbook to add context info
    wb = writer.book
    ws_recipe = wb['Recipe']
    
    # Add Context params to Recipe sheet
    ws_recipe['E1'] = "Parameters"
    ws_recipe['E2'] = "Bake Loss %"
    ws_recipe['F2'] = 0.12
    ws_recipe['E3'] = "Serving Size (g)"
    ws_recipe['F3'] = 30
    
    ws_recipe['A13'] = "TOTAL RAW WEIGHT"
    ws_recipe['A16'] = "BAKED BATCH WEIGHT"
    ws_recipe['B16'] = "" # To be calculated
    
    # Formatting Nutrition Facts Sheet
    ws_facts = wb['Nutrition_Facts']
    ws_facts['B1'] = "NUTRITION FACTS"
    ws_facts['B2'] = "Serving Size: 30g"

print(f"Created {file_path}")
'@ | Out-File -FilePath $GenScript -Encoding ASCII

# Execute Python script to generate Excel file
python $GenScript

# 4. Record State
$date = Get-Date -UFormat %s
$date | Out-File -FilePath $StartTimePath -NoNewline

if (Test-Path $ExcelFilePath) {
    $hash = Get-FileHash $ExcelFilePath -Algorithm MD5
    $hash.Hash | Out-File -FilePath $InitialHashPath -NoNewline
}

# 5. Launch Excel
Write-Host "Launching Excel..."
$excel = Start-Process "C:\Program Files\Microsoft Office\Office14\EXCEL.EXE" -ArgumentList """$ExcelFilePath""" -PassThru
Start-Sleep -Seconds 5

# 6. Maximize Window (using WScript because wmctrl isn't native to Windows/PowerShell env usually, assuming standard env tools)
# If wmctrl is available in the env via git bash/cygwin, we use that. 
# The prompt's env definition implies Windows environment via PowerShell hooks.
# We will use a visual basic script to ensure maximize if possible, or just rely on start.
# Note: Start-Process with WindowStyle Maximized sometimes works but Excel MDI handles it differently.
$wshell = New-Object -ComObject WScript.Shell
if ($wshell.AppActivate("Excel")) {
    Start-Sleep -Milliseconds 500
    # Alt+Space, X to maximize
    $wshell.SendKeys("% x")
}

Write-Host "=== Setup Complete ==="