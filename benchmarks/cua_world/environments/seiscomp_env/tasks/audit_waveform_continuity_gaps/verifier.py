#!/usr/bin/env python3
"""
Verifier for audit_waveform_continuity_gaps task.

Uses `copy_from_env` to retrieve export metadata and the generated CSV report.
Evaluates the identified gaps against the ground truth metadata.
Includes a VLM trajectory check to ensure the agent didn't guess the file contents.
"""

import os
import csv
import json
import tempfile
import logging
import datetime

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_time(time_str):
    """Attempt to parse various time formats into a datetime object."""
    time_str = time_str.strip().replace("Z", "")
    formats = [
        "%Y-%m-%dT%H:%M:%S.%f",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%d %H:%M:%S.%f",
        "%Y-%m-%d %H:%M:%S",
    ]
    for fmt in formats:
        try:
            return datetime.datetime.strptime(time_str, fmt)
        except ValueError:
            continue
    return None

def verify_waveform_gaps(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available."}
    
    metadata = task_info.get('metadata', {})
    expected_gaps = metadata.get('gaps', [])
    time_tol = metadata.get('time_tolerance_sec', 3.0)
    dur_tol = metadata.get('duration_tolerance_sec', 1.5)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the task result JSON
    result_json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_tmp.name)
        with open(result_json_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result metadata: {e}"}
    finally:
        if os.path.exists(result_json_tmp.name):
            os.unlink(result_json_tmp.name)
            
    output_exists = result.get("output_exists", False)
    file_created = result.get("file_created_during_task", False)
    
    if not output_exists:
        return {"passed": False, "score": 0, "feedback": "Target gap_report.csv was not found."}
    
    if not file_created:
        feedback_parts.append("Warning: File timestamp suggests it was not created during the task.")
    else:
        score += 10
        feedback_parts.append("Report file created.")
        
    if result.get("has_headers"):
        score += 10
        feedback_parts.append("CSV headers are correct.")
        
    # 2. Retrieve the actual CSV file
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/tmp/gap_report.csv", csv_tmp.name)
        reported_gaps = []
        with open(csv_tmp.name, 'r') as f:
            reader = csv.DictReader(f)
            # Normalize column names in case of case mismatches
            if reader.fieldnames:
                reader.fieldnames = [str(col).strip().lower() for col in reader.fieldnames]
                for row in reader:
                    reported_gaps.append(row)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {e}"}
    finally:
        if os.path.exists(csv_tmp.name):
            os.unlink(csv_tmp.name)
            
    # 3. Analyze the gaps
    # Expected: TOLI (10s), GSI (45s)
    found_toli = False
    found_gsi = False
    false_positives = 0
    
    for row in reported_gaps:
        # Robustly try to find fields regardless of exact header casing matching
        net = row.get("network", row.get("\ufeffnetwork", "")).strip()
        sta = row.get("station", "").strip()
        
        start_str = row.get("gapstart", row.get("gap_start", "")).strip()
        dur_str = row.get("gapduration", row.get("gap_duration", "")).strip()
        
        try:
            dur_val = float(dur_str)
        except ValueError:
            false_positives += 1
            continue
            
        start_dt = parse_time(start_str)
        if not start_dt:
            false_positives += 1
            continue
            
        matched_expected = False
        for exp in expected_gaps:
            if exp["station"] == sta and exp["network"] == net:
                exp_dt = parse_time(exp["start_time"])
                
                dt_diff = abs((start_dt - exp_dt).total_seconds())
                dur_diff = abs(dur_val - exp["duration"])
                
                if dt_diff <= time_tol and dur_diff <= dur_tol:
                    matched_expected = True
                    if sta == "TOLI":
                        found_toli = True
                    elif sta == "GSI":
                        found_gsi = True
                    break
        
        if not matched_expected:
            false_positives += 1

    if found_toli:
        score += 30
        feedback_parts.append("Correctly identified Gap 1 (TOLI).")
    else:
        feedback_parts.append("Missed Gap 1 (TOLI).")
        
    if found_gsi:
        score += 30
        feedback_parts.append("Correctly identified Gap 2 (GSI).")
    else:
        feedback_parts.append("Missed Gap 2 (GSI).")

    if false_positives == 0 and len(reported_gaps) > 0:
        score += 20
        feedback_parts.append("No false positives reported.")
    else:
        feedback_parts.append(f"Found {false_positives} false positives or invalid rows.")

    # 4. VLM Check (Anti-Gaming)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_prompt = """
        Review these screenshots from a user's session analyzing seismic data gaps.
        Did the user genuinely use a terminal, write a script (like Python), or execute commands 
        to analyze data files?
        Respond in JSON with {"genuine_work_detected": true/false}
        """
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_res and vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if not parsed.get("genuine_work_detected", True):
                feedback_parts.append("VLM flagged suspicious activity (no genuine script/tool usage detected).")
                score = max(0, score - 30)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }