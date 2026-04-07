#!/usr/bin/env python3
import os
import json
import tempfile
import csv
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_raw_profile_csv(traj, env_info, task_info):
    """
    Programmatic verification of CSV generation.
    Scoring:
    - 20 pts: File successfully generated during task timeframe.
    - 20 pts: "Profile Data" mode used (detected by Sample time/depth columns).
    - 20 pts: Telemetry populated (detected by a non-trivial row count > 10).
    - 40 pts: Scoped to "Selected dives" (detected by exclusive presence of Dive #3 ID).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    res_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    res_tmp.close()
    
    try:
        copy_from_env('/tmp/task_result.json', res_tmp.name)
        with open(res_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(res_tmp.name):
            os.unlink(res_tmp.name)
            
    file_exists = result.get('file_exists', False)
    created_during_task = result.get('created_during_task', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Verification: Was file created?
    if file_exists and created_during_task:
        score += 20
        feedback_parts.append("File created during task (+20)")
    elif file_exists:
        feedback_parts.append("File exists but was NOT created during task (Do-nothing penalty)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Output CSV file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
        
    # Copy exported CSV into the host to analyze it securely
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_tmp.close()
    
    has_profile_data = False
    restricted_to_dive_3 = False
    row_count = 0
    unique_dives = set()
    
    try:
        copy_from_env('/home/ga/Documents/dive3_profile.csv', csv_tmp.name)
        with open(csv_tmp.name, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames or []
            
            # 2. Verification: Profile data vs Summary data
            header_str = " ".join(headers).lower()
            if 'sample' in header_str and ('time' in header_str or 'depth' in header_str):
                has_profile_data = True
                
            dive_cols = [h for h in headers if 'dive' in h.lower() and ('#' in h or 'no' in h.lower() or 'num' in h.lower())]
            dive_col = dive_cols[0] if dive_cols else None
            if dive_col is None and 'Dive' in headers:
                dive_col = 'Dive'
                
            for row in reader:
                row_count += 1
                if dive_col and row.get(dive_col):
                    val = row[dive_col].strip()
                    if val:
                        unique_dives.add(val)
                        
            # 3. Verification: Correct scoping (Only Dive #3 exported)
            if unique_dives == {'3'} or unique_dives == {'3.0'}:
                restricted_to_dive_3 = True
            elif '3' in unique_dives and len(unique_dives) == 1:
                restricted_to_dive_3 = True
            elif len(unique_dives) == 0:
                # Fallback: If version changes structure, rely strictly on row count length characteristics
                # A 46 min dive is ~100-300 rows. Entire logbook (8 dives) > 1000 rows.
                if 10 < row_count < 500:
                    restricted_to_dive_3 = True
                
    except Exception as e:
        feedback_parts.append(f"Error parsing CSV structure: {e}")
    finally:
        if os.path.exists(csv_tmp.name):
            os.unlink(csv_tmp.name)
            
    # Apply criteria scores
    if has_profile_data:
        score += 20
        feedback_parts.append("Profile data column signatures verified (+20)")
    else:
        feedback_parts.append("Missing profile data column signatures")
        
    if row_count > 10:
        score += 20
        feedback_parts.append(f"Telemetry row count valid ({row_count} rows) (+20)")
    else:
        feedback_parts.append(f"Insufficient row count ({row_count} rows). Did agent export summary instead?")
        
    if restricted_to_dive_3:
        score += 40
        feedback_parts.append("Data appropriately scoped to selected Dive 3 (+40)")
    elif unique_dives:
        feedback_parts.append(f"Failed scope restriction. Export contained multiple dives: {unique_dives}")
    else:
        feedback_parts.append(f"Failed scope restriction. Row count ({row_count}) implies incorrect scope.")
        
    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }