# Note: This is actually export_result.ps1
# <file name="export_result.ps1">
Write-Host "=== Exporting Result ==="

$ProjectDir = "C:\Users\Docker\Documents\Epi Info 7\Projects\LabImport"
$DbPath = "$ProjectDir\LabImport.db"
$PrjPath = "$ProjectDir\LabImport.prj"
$MdbPath = "$ProjectDir\LabImport.mdb"
$JsonPath = "C:\tmp\task_result.json"
$StartTime = Get-Content "C:\tmp\task_start_time.txt" -ErrorAction SilentlyContinue

# Python script to analyze the result
$AnalyzeScript = @"
import json
import sqlite3
import os
import time

result = {
    'project_exists': False,
    'db_type': 'none',
    'db_exists': False,
    'table_exists': False,
    'row_count': 0,
    'columns': [],
    'has_junk_columns': False,
    'data_sample_correct': False
}

project_dir = r'$ProjectDir'
db_path = r'$DbPath'
mdb_path = r'$MdbPath'

# Check Project Structure
if os.path.exists(project_dir):
    result['project_exists'] = True

# Check DB Type
if os.path.exists(db_path):
    result['db_type'] = 'sqlite'
    result['db_exists'] = True
elif os.path.exists(mdb_path):
    result['db_type'] = 'access'
    result['db_exists'] = True

# Inspect SQLite Data (Primary Goal)
if result['db_type'] == 'sqlite':
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        
        # Check for table
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='LabResults';")
        if cursor.fetchone():
            result['table_exists'] = True
            
            # Get columns
            cursor.execute("PRAGMA table_info(LabResults);")
            columns = [info[1] for info in cursor.fetchall()]
            result['columns'] = columns
            
            # Check for junk
            junk_markers = ['F1', 'St_Marys', 'Report_Date', 'Column1']
            for col in columns:
                for junk in junk_markers:
                    if junk.lower() in col.lower():
                        result['has_junk_columns'] = True
            
            # Get Row Count
            cursor.execute("SELECT COUNT(*) FROM LabResults;")
            result['row_count'] = cursor.fetchone()[0]
            
            # Check Data Fidelity (Sample a row)
            if 'CtValue' in columns:
                cursor.execute("SELECT CtValue FROM LabResults WHERE CtValue > 0 LIMIT 1;")
                row = cursor.fetchone()
                if row and isinstance(row[0], (float, int)):
                    result['data_sample_correct'] = True
                    
        conn.close()
    except Exception as e:
        result['error'] = str(e)

# Save result
with open(r'$JsonPath', 'w') as f:
    json.dump(result, f, indent=4)

print(json.dumps(result, indent=2))
"@

$PyScriptPath = "C:\tmp\analyze_result.py"
$AnalyzeScript | Out-File $PyScriptPath -Encoding UTF8

# Run Analysis
python $PyScriptPath

# Capture Final Screenshot
$ScreenScript = @"
import pyautogui
try:
    pyautogui.screenshot(r'C:\tmp\task_final.png')
except:
    pass
"@
$ScreenScript | Out-File "C:\tmp\screenshot_final.py" -Encoding UTF8
python "C:\tmp\screenshot_final.py"

Write-Host "=== Export Complete ==="