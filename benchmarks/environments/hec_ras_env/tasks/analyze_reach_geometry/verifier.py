#!/usr/bin/env python3
"""
Verifier for analyze_reach_geometry task.

Verification Strategy:
1. Check if output CSV exists and was created during task.
2. Check if output Python script exists.
3. Validate CSV structure (columns).
4. Validate Data Consistency:
   - Check if Slope column is mathematically consistent with Inverts and Lengths.
   - Formula: Slope = (Upstream_Invert - Downstream_Invert) / Reach_Length
   - This allows verification even if exact ground truth varies slightly,
     as it tests the agent's internal logic which is the core task.
5. Sanity Check:
   - Reach lengths > 0.
   - Slopes within reasonable range (e.g., -0.1 to 0.5).
   - River stations match expected format (numeric strings).
"""

import json
import os
import tempfile
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_reach_geometry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []
    
    # 1. File Existence Checks
    if result.get("csv_exists"):
        score += 10
        feedback.append("CSV file created.")
    else:
        feedback.append("CSV file NOT found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    if result.get("csv_created_during_task"):
        score += 10
        feedback.append("CSV created during task.")
    else:
        feedback.append("CSV file existed before task start (stale).")

    if result.get("script_exists"):
        score += 10
        feedback.append("Python script created.")
    else:
        feedback.append("Python script NOT found.")

    # 2. CSV Content Analysis
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/agent_reach_stats.csv", temp_csv.name)
        
        with open(temp_csv.name, 'r') as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames
            rows = list(reader)
            
        # Check Headers
        required_cols = task_info.get('metadata', {}).get('required_columns', [])
        missing_cols = [c for c in required_cols if c not in headers]
        
        if not missing_cols:
            score += 10
            feedback.append("All required columns present.")
        else:
            feedback.append(f"Missing columns: {missing_cols}")
            
        # Check Row Count (Muncie usually has ~50-60 XS, so ~50 segments)
        if len(rows) > 10:
            score += 10
            feedback.append(f"Row count looks reasonable ({len(rows)} segments).")
        else:
            feedback.append(f"Row count too low ({len(rows)}).")

        # Check Math Consistency
        consistent_slopes = 0
        valid_ranges = 0
        total_checked = 0
        
        for i, row in enumerate(rows):
            try:
                length = float(row.get('Reach_Length_ft', 0))
                up_inv = float(row.get('Upstream_Invert_ft', 0))
                dn_inv = float(row.get('Downstream_Invert_ft', 0))
                slope_rep = float(row.get('Slope_ft_ft', 0))
                
                total_checked += 1
                
                # Math Check
                if length > 0.001:
                    calc_slope = (up_inv - dn_inv) / length
                    if abs(calc_slope - slope_rep) < 1e-5:
                        consistent_slopes += 1
                        
                # Range Check
                # Slopes typically small (0.0001 to 0.05). Allow broad range for validity.
                if -0.1 < slope_rep < 0.5 and length > 0:
                    valid_ranges += 1
                    
            except ValueError:
                continue

        if total_checked > 0:
            consistency_rate = consistent_slopes / total_checked
            if consistency_rate > 0.9:
                score += 30
                feedback.append("Slope calculations are mathematically consistent.")
            else:
                feedback.append(f"Slope calculations inconsistent (matches: {consistent_slopes}/{total_checked}). Check formula.")
                
            if valid_ranges / total_checked > 0.9:
                score += 20
                feedback.append("Data values fall within plausible physical ranges.")
            else:
                feedback.append("Data values seem implausible (e.g., zero lengths or extreme slopes).")
                
    except Exception as e:
        feedback.append(f"Failed to parse CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }