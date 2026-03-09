#!/usr/bin/env python3
"""
Verifier for export_historical_data task (NinjaTrader 8).

Verifies:
1. File existence and creation time.
2. CSV structure (headers, row count).
3. Data content (Date range, Spot check of prices).
"""

import json
import os
import tempfile
import csv
import logging
from datetime import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_historical_data(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    spot_checks = metadata.get('spot_checks', [])
    
    # Paths in the container (Windows)
    result_json_path = "C:/Users/Docker/Desktop/NinjaTraderTasks/task_result.json"
    csv_path = "C:/Users/Docker/Desktop/NinjaTraderTasks/aapl_daily_2023.csv"
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # 2. Basic File Checks
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output CSV file not found at target path."}
    
    score += 10 # File exists
    
    if result.get('file_created_during_task'):
        score += 10
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("File timestamp predates task start (stale?)")
        
    if result.get('output_size_bytes', 0) > 100:
        score += 5
        feedback_parts.append("File size > 100 bytes")
    else:
        feedback_parts.append("File too small")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Fetch and Parse CSV content
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(csv_path, temp_csv.name)
        
        # Determine delimiter (NinjaTrader might use ; or ,)
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            sample = f.read(1024)
            delimiter = ';' if ';' in sample else ','
            
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # NinjaTrader exports usually don't have standard headers, sometimes just data
            # Or they might have headers like Date;Open;High;Low;Close;Volume
            # We'll use csv.reader
            reader = csv.reader(f, delimiter=delimiter)
            rows = [r for r in reader if r] # Skip empty rows
            
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to read CSV content: {e}"}
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)
            
    # 4. Analyze Data
    data_rows = []
    header_found = False
    
    # Try to identify header
    if rows and any(c.lower().startswith('date') or c.lower().startswith('time') for c in rows[0]):
        header_found = True
        data_rows = rows[1:]
        score += 10
        feedback_parts.append("Header row detected")
    else:
        data_rows = rows
        feedback_parts.append("No header row detected (assuming raw data)")

    row_count = len(data_rows)
    # Expected approx 250 trading days
    if 240 <= row_count <= 260:
        score += 20
        feedback_parts.append(f"Row count correct ({row_count})")
    else:
        feedback_parts.append(f"Row count unexpected ({row_count}, expected 240-260)")
        
    # Check content (Date and Close)
    # NinjaTrader format often: 20230103;093000;... or 1/3/2023;...
    # We need to be robust
    
    valid_dates = 0
    price_matches = 0
    in_year_2023 = True
    
    parsed_data = {} # Map date_str -> close_price
    
    for row in data_rows:
        if len(row) < 5: continue
        
        date_str = row[0].strip()
        try:
            # Parse close price (usually index 4 or 5 depending on if Time is separate)
            # Standard NT export: Date;Time;Open;High;Low;Close;Volume -> Close is index 5
            # If Date and Time are merged or Time missing, check context
            
            # Simple heuristic: take the last-but-one column as Close if length is 7 (Vol is last)
            # Or scan for float-looking values
            
            # Standard Daily export: Date;Open;High;Low;Close;Volume (6 cols) or Date;Time;... (7 cols)
            if len(row) >= 6:
                close_val = float(row[-2]) # Assumes Volume is last
            else:
                continue

            # Parse date
            # Formats: 20230103 or 2023-01-03 or 1/3/2023
            d = None
            if len(date_str) == 8 and date_str.isdigit():
                d = datetime.strptime(date_str, "%Y%m%d")
            elif '-' in date_str:
                d = datetime.strptime(date_str, "%Y-%m-%d")
            elif '/' in date_str:
                d = datetime.strptime(date_str, "%m/%d/%Y") # US format assumption
                
            if d:
                if d.year != 2023:
                    in_year_2023 = False
                
                # Normalize date for lookup (YYYYMMDD)
                key = d.strftime("%Y%m%d")
                parsed_data[key] = close_val
                valid_dates += 1
                
        except ValueError:
            continue

    if valid_dates > 200:
        score += 15
        feedback_parts.append("Valid date data parsed")
    else:
        feedback_parts.append("Failed to parse dates/prices")
        
    if in_year_2023 and valid_dates > 0:
        score += 15
        feedback_parts.append("Date range correct (2023)")
    elif valid_dates > 0:
        feedback_parts.append("Data contains years other than 2023")
        
    # Spot checks
    matches = 0
    for check in spot_checks:
        d_key = check['date']
        expected = check['close']
        if d_key in parsed_data:
            actual = parsed_data[d_key]
            # 2% tolerance
            if abs(actual - expected) / expected < 0.02:
                matches += 1
    
    if matches >= 2:
        score += 15
        feedback_parts.append(f"Price spot check passed ({matches}/{len(spot_checks)})")
    elif matches > 0:
        score += 5
        feedback_parts.append(f"Price spot check partial ({matches}/{len(spot_checks)})")
    else:
        feedback_parts.append("Price spot check failed")
        if parsed_data:
            feedback_parts.append(f"(Ex: {list(parsed_data.items())[0]})")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }