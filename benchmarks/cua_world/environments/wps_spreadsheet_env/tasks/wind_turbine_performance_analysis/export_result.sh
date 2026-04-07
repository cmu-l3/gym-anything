#!/bin/bash
echo "=== Exporting task result ==="

# Record end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Parse the resulting Excel file to extract values and formulas
python3 << 'PYEOF'
import json
import os

result = {
    "file_exists": False,
    "mtime": 0,
    "task_start": 0,
    "sheets": [],
    "scada_formulas_sample": [],
    "agent_report": None,
    "ground_truth": None,
    "error": None
}

file_path = "/home/ga/Documents/wind_scada_2022.xlsx"

if os.path.exists("/tmp/task_start_time.txt"):
    with open("/tmp/task_start_time.txt", "r") as f:
        try:
            result["task_start"] = int(f.read().strip())
        except:
            pass

if os.path.exists(file_path):
    result["file_exists"] = True
    result["mtime"] = int(os.stat(file_path).st_mtime)

    try:
        import openpyxl
        
        # Load workbook with formulas
        wb_f = openpyxl.load_workbook(file_path, data_only=False)
        result["sheets"] = wb_f.sheetnames
        
        # Load workbook with cached values
        wb_v = openpyxl.load_workbook(file_path, data_only=True)

        true_counts = {"NORMAL": 0, "LOW_WIND": 0, "FAULT": 0, "UNDERPERFORMING": 0}
        true_sums = {"NORMAL": 0.0, "LOW_WIND": 0.0, "FAULT": 0.0, "UNDERPERFORMING": 0.0}

        if "SCADA" in wb_f.sheetnames:
            ws_f = wb_f["SCADA"]
            ws_v = wb_v["SCADA"]

            # Calculate Ground Truth from the actual values the agent was given
            for r in range(2, ws_v.max_row + 1):
                ws_ms = float(ws_v.cell(row=r, column=2).value or 0)
                active = float(ws_v.cell(row=r, column=3).value or 0)
                theo = float(ws_v.cell(row=r, column=4).value or 0)
                
                lost = (theo - active) / 6.0 if theo > active else 0.0
                
                if ws_ms < 3.5:
                    state = "LOW_WIND"
                elif active <= 0:
                    state = "FAULT"
                elif lost > 50:
                    state = "UNDERPERFORMING"
                else:
                    state = "NORMAL"
                    
                true_counts[state] += 1
                true_sums[state] += lost

            result["ground_truth"] = {
                "counts": true_counts,
                "sums": true_sums,
                "financial_loss": (true_sums["FAULT"] + true_sums["UNDERPERFORMING"]) * 0.075
            }

            # Sample some rows to check if formulas were used in E and F
            import random
            max_r = ws_f.max_row
            if max_r > 10:
                samples = random.sample(range(2, max_r), min(20, max_r - 2))
                for r in samples:
                    val_e = ws_f.cell(row=r, column=5).value
                    val_f = ws_f.cell(row=r, column=6).value
                    if isinstance(val_e, str) and val_e.startswith('='):
                        result["scada_formulas_sample"].append({"col": "E", "formula": val_e})
                    if isinstance(val_f, str) and val_f.startswith('='):
                        result["scada_formulas_sample"].append({"col": "F", "formula": val_f})

        # Extract agent's Monthly Report values
        if "Monthly_Report" in wb_v.sheetnames:
            ws_v_report = wb_v["Monthly_Report"]
            ws_f_report = wb_f["Monthly_Report"]
            
            agent_counts = {}
            agent_sums = {}
            agent_loss = None
            has_countif = False
            has_sumif = False
            
            for r in range(1, 25):
                for c in range(1, 4):
                    # Check for formulas
                    form = str(ws_f_report.cell(row=r, column=c).value).upper()
                    if "COUNTIF" in form: has_countif = True
                    if "SUMIF" in form: has_sumif = True
                    
                    # Extract values based on row labels
                    val = str(ws_v_report.cell(row=r, column=c).value).strip().upper()
                    if val in true_counts.keys():
                        try:
                            c_val = ws_v_report.cell(row=r, column=c+1).value
                            s_val = ws_v_report.cell(row=r, column=c+2).value
                            if c_val is not None: agent_counts[val] = float(c_val)
                            if s_val is not None: agent_sums[val] = float(s_val)
                        except:
                            pass
                    
                    if "FINANCIAL" in val and "LOSS" in val:
                        try:
                            # Search adjacent cells for the calculated loss
                            v1 = ws_v_report.cell(row=r, column=c+1).value
                            v2 = ws_v_report.cell(row=r, column=c+2).value
                            l_val = v1 if v1 is not None else v2
                            if l_val is not None: agent_loss = float(l_val)
                        except:
                            pass

            result["agent_report"] = {
                "counts": agent_counts,
                "sums": agent_sums,
                "financial_loss": agent_loss,
                "has_countif": has_countif,
                "has_sumif": has_sumif
            }

    except Exception as e:
        result["error"] = str(e)
else:
    result["error"] = "File not found"

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="