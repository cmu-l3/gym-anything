#!/usr/bin/env python3
"""
Verifier for analyze_battery_telemetry task.

SCORING CRITERIA:
1. Report File Exists (20 pts)
2. No False Positives (30 pts) - Reporting safe flights as critical is dangerous.
3. Recall / Coverage (30 pts) - Finding all critical flights.
4. Data Accuracy (20 pts) - Correct battery values extracted.

Total: 100 pts
Pass Threshold: 90 pts (Safety critical task)
"""

import json
import os
import csv
import logging
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_analyze_battery_telemetry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check if report exists
    if not result_data.get("report_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Report file 'critical_battery_report.csv' was not found in Documents."
        }

    # 3. Retrieve Agent Report and Ground Truth
    agent_csv_path = result_data.get("agent_report_path")
    gt_csv_path = result_data.get("ground_truth_path")
    
    temp_dir = tempfile.mkdtemp()
    local_agent_csv = os.path.join(temp_dir, "agent_report.csv")
    local_gt_csv = os.path.join(temp_dir, "ground_truth.csv")
    
    try:
        copy_from_env(agent_csv_path, local_agent_csv)
        copy_from_env(gt_csv_path, local_gt_csv)
        
        # Parse CSVs
        ground_truth = parse_csv(local_gt_csv)
        agent_data = parse_csv(local_agent_csv)
        
    except Exception as e:
        shutil.rmtree(temp_dir)
        return {
            "passed": False, 
            "score": 20, 
            "feedback": f"Failed to parse CSV files: {e}. Report existed but was malformed."
        }

    # 4. Scoring Logic
    score = 20 # Points for file existing
    feedback_parts = ["Report file found (+20 pts)."]
    
    # Check False Positives
    # Agent reported ID that is NOT in ground truth (meaning it was safe >= 15)
    false_positives = [id for id in agent_data if id not in ground_truth]
    if not false_positives:
        score += 30
        feedback_parts.append("No false positives (+30 pts).")
    else:
        feedback_parts.append(f"Found {len(false_positives)} false positives (safe flights reported as critical).")

    # Check Recall (Coverage)
    # Agent found IDs that ARE in ground truth
    true_positives = [id for id in agent_data if id in ground_truth]
    total_critical = len(ground_truth)
    
    if total_critical > 0:
        recall_pct = len(true_positives) / total_critical
        recall_pts = int(recall_pct * 30)
        score += recall_pts
        feedback_parts.append(f"Identified {len(true_positives)}/{total_critical} critical flights (+{recall_pts} pts).")
    else:
        # Edge case: no critical flights generated (unlikely with logic, but possible)
        score += 30
        feedback_parts.append("No critical flights existed in data (+30 pts).")

    # Check Data Accuracy
    # Values match ground truth
    matches = 0
    for id in true_positives:
        if agent_data[id] == ground_truth[id]:
            matches += 1
            
    if len(true_positives) > 0:
        accuracy_pct = matches / len(true_positives)
        accuracy_pts = int(accuracy_pct * 20)
        score += accuracy_pts
        feedback_parts.append(f"Data values correct for {matches}/{len(true_positives)} reported flights (+{accuracy_pts} pts).")
    elif total_critical == 0:
        score += 20
        feedback_parts.append("N/A Accuracy (+20 pts).")

    # Cleanup
    shutil.rmtree(temp_dir)

    # Final Verdict
    passed = score >= 90
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }

def parse_csv(filepath):
    """
    Parses CSV into a dict: {flight_id (str): battery_value (int)}
    Handles case-insensitivity in headers.
    """
    data = {}
    try:
        with open(filepath, 'r') as f:
            lines = [l.strip() for l in f.readlines() if l.strip()]
            if not lines:
                return {}
            
            # Simple parsing to avoid DictReader header issues if format varies slightly
            # Skip header if it contains non-digits
            start_idx = 0
            if not lines[0][0].isdigit():
                start_idx = 1
                
            for line in lines[start_idx:]:
                parts = line.split(',')
                if len(parts) >= 2:
                    try:
                        # cleanup quotes or whitespace
                        f_id = parts[0].strip().strip('"')
                        val = int(parts[1].strip().strip('"'))
                        data[f_id] = val
                    except ValueError:
                        continue
    except Exception:
        return {}
    return data