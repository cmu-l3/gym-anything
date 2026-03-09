#!/usr/bin/env python3
import json
import os
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_import_custom_historical_data(traj, env_info, task_info):
    """
    Verify that TSLA history data was imported correctly into JStock.
    """
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_points = metadata.get('expected_data_points', [])
    
    score = 0
    feedback = []
    
    # 2. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 3. Verify Watchlist (20 points)
    if result.get('watchlist_has_tsla'):
        score += 20
        feedback.append("TSLA added to watchlist.")
    else:
        feedback.append("TSLA NOT found in watchlist.")

    # 4. Verify History File Existence (20 points)
    history_exists = result.get('history_file_exists')
    created_during = result.get('file_created_during_task')
    
    if history_exists:
        if created_during:
            score += 20
            feedback.append("History database file created during task.")
        else:
            score += 10
            feedback.append("History database file exists but timestamp is old (re-used?).")
    else:
        feedback.append("History database file NOT found.")
        # If file doesn't exist, we can't check data, so return here
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    # 5. Verify Data Content (60 points)
    # We need to copy the extracted CSV from the container
    container_csv_path = result.get('history_extracted_path')
    if not container_csv_path:
        feedback.append("Could not locate extracted history data.")
        return {"passed": False, "score": score, "feedback": " ".join(feedback)}

    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env(container_csv_path, temp_csv.name)
        
        # Parse CSV
        data_map = {} # Map Date -> Row
        with open(temp_csv.name, 'r', encoding='utf-8', errors='replace') as f:
            # JStock exported/stored CSV might have different headers or formatting.
            # We'll try to sniff. Usually JStock stores: Date,Open,High,Low,Close,Volume,...
            # Or it might follow the import format.
            # We will read all rows and try to parse dates.
            reader = csv.reader(f)
            for row in reader:
                if len(row) < 5: continue
                # Try to find date in first column
                date_str = row[0].strip()
                # Basic normalization 2024-01-02 or 20240102
                data_map[date_str] = row

        # Check Expected Points
        points_correct = 0
        total_points = len(expected_points)
        
        for pt in expected_points:
            exp_date = pt['date']
            exp_close = pt['close']
            
            # Try exact match or formats
            row = data_map.get(exp_date)
            # Try alternate date formats if exact match fails (e.g. 20240102 vs 2024-01-02)
            if not row:
                row = data_map.get(exp_date.replace('-', ''))
            
            if row:
                # Find Close column. Usually index 4 (0-based) if Date,Open,High,Low,Close
                # But let's be robust. If headers exist, we use them? 
                # Assuming standard OHLCV order.
                try:
                    # Parse close price from index 4
                    act_close = float(row[4])
                    if abs(act_close - exp_close) < pt.get('tolerance', 0.5):
                        points_correct += 1
                        feedback.append(f"Date {exp_date}: Price verified ({act_close}).")
                    else:
                        feedback.append(f"Date {exp_date}: Price mismatch (Expected ~{exp_close}, Got {act_close}).")
                except ValueError:
                    feedback.append(f"Date {exp_date}: Could not parse price.")
            else:
                feedback.append(f"Date {exp_date}: Record not found in database.")

        # Scaling score
        if total_points > 0:
            score += int(60 * (points_correct / total_points))

    except Exception as e:
        feedback.append(f"Error verifying data content: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }