#!/bin/bash
echo "=== Exporting flight_delay_liability result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_PATH="/home/ga/Documents/flight_data.xlsx"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Run Python script to extract data, formulas, and compute ground truth
python3 << 'PYEOF'
import json
import os
import pandas as pd
from openpyxl import load_workbook

file_path = "/home/ga/Documents/flight_data.xlsx"
result = {
    "file_exists": False,
    "file_modified": False,
    "has_summary_sheet": False,
    "summary_values": {},
    "summary_formulas": {},
    "formatting": {},
    "ground_truth": {},
    "sample_evaluations": [],
    "error": None
}

if os.path.exists(file_path):
    result["file_exists"] = True
    
    # Check if modified
    start_time = int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0
    mtime = int(os.path.getmtime(file_path))
    result["file_modified"] = mtime > start_time

    try:
        # Load workbook in value mode and formula mode
        wb_val = load_workbook(file_path, data_only=True)
        wb_form = load_workbook(file_path, data_only=False)

        ws_val = wb_val["Flights"]
        ws_form = wb_form["Flights"]

        # 1. Compute Ground Truth using Pandas
        data = ws_val.values
        cols = next(data)
        df = pd.DataFrame(data, columns=cols)
        
        # Ensure correct column parsing
        df['CANCELLED'] = pd.to_numeric(df['CANCELLED'], errors='coerce').fillna(0)
        df['ARRIVAL_DELAY'] = pd.to_numeric(df['ARRIVAL_DELAY'], errors='coerce')
        df['DISTANCE'] = pd.to_numeric(df['DISTANCE'], errors='coerce').fillna(0)

        def calc_status(row):
            if row['CANCELLED'] == 1: return 'Cancelled'
            if pd.notna(row['ARRIVAL_DELAY']) and row['ARRIVAL_DELAY'] >= 120: return 'Severely Delayed'
            return 'Normal'

        def calc_payout(row):
            if row['Status'] == 'Cancelled': return 600
            if row['Status'] == 'Severely Delayed' and row['DISTANCE'] < 1000: return 250
            if row['Status'] == 'Severely Delayed' and row['DISTANCE'] >= 1000: return 500
            return 0

        df['GT_Status'] = df.apply(calc_status, axis=1)
        df['GT_Payout'] = df.apply(calc_payout, axis=1)

        gt_summary = df.groupby('AIRLINE').agg(
            Total_Flights=('FLIGHT_NUMBER', 'count'),
            Severely_Delayed=('GT_Status', lambda x: (x == 'Severely Delayed').sum()),
            Total_Payout=('GT_Payout', 'sum')
        ).reset_index()
        gt_summary['Avg_Payout'] = gt_summary['Total_Payout'] / gt_summary['Total_Flights']

        # Store Ground Truth for target airlines
        target_airlines = ['AA', 'DL', 'UA', 'WN', 'B6']
        for _, r in gt_summary.iterrows():
            if r['AIRLINE'] in target_airlines:
                result["ground_truth"][r['AIRLINE']] = {
                    "Total_Flights": int(r['Total_Flights']),
                    "Severely_Delayed": int(r['Severely_Delayed']),
                    "Total_Payout": float(r['Total_Payout']),
                    "Avg_Payout": float(r['Avg_Payout'])
                }

        # 2. Extract Agent's sample rows (first 50)
        for r in range(2, 52):
            result["sample_evaluations"].append({
                "row": r,
                "Agent_Status": ws_val.cell(r, 10).value,
                "Agent_Payout": ws_val.cell(r, 11).value,
                "GT_Status": df.loc[r-2, 'GT_Status'],
                "GT_Payout": df.loc[r-2, 'GT_Payout'],
                "Status_Formula": str(ws_form.cell(r, 10).value),
                "Payout_Formula": str(ws_form.cell(r, 11).value)
            })

        # 3. Extract Agent's Summary Sheet
        summary_sheet_name = None
        for name in wb_val.sheetnames:
            if name.strip().lower() == "liability summary":
                summary_sheet_name = name
                break
                
        if summary_sheet_name:
            result["has_summary_sheet"] = True
            ws_sum_val = wb_val[summary_sheet_name]
            ws_sum_form = wb_form[summary_sheet_name]

            # Find data bounds dynamically based on airlines
            for r in range(1, 20):
                for c in range(1, 4):
                    cell_val = str(ws_sum_val.cell(r, c).value).strip() if ws_sum_val.cell(r, c).value else ""
                    if cell_val in target_airlines:
                        # We found a row for a target airline
                        result["summary_values"][cell_val] = {
                            "Total_Flights": ws_sum_val.cell(r, c+1).value,
                            "Severely_Delayed": ws_sum_val.cell(r, c+2).value,
                            "Total_Payout": ws_sum_val.cell(r, c+3).value,
                            "Avg_Payout": ws_sum_val.cell(r, c+4).value,
                        }
                        result["summary_formulas"][cell_val] = {
                            "Total_Flights": str(ws_sum_form.cell(r, c+1).value),
                            "Severely_Delayed": str(ws_sum_form.cell(r, c+2).value),
                            "Total_Payout": str(ws_sum_form.cell(r, c+3).value),
                            "Avg_Payout": str(ws_sum_form.cell(r, c+4).value),
                        }
                        # Capture format of the Payout cell
                        fmt = ws_sum_form.cell(r, c+3).number_format
                        result["formatting"][cell_val] = fmt
        else:
            result["has_summary_sheet"] = False

    except Exception as e:
        result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Data export complete. Results saved to /tmp/task_result.json"
echo "=== Export complete ==="