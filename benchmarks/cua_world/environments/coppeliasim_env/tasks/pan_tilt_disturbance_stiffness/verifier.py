#!/usr/bin/env python3
"""
Verifier for pan_tilt_disturbance_stiffness task.

Scoring (100 points, 80 pass threshold):
1. File Creation & JSON format (20 pts): Files are created after task start, JSON contains required fields.
2. Data Density & Structure (20 pts): CSV has >= 4 trials, >= 50 samples per trial.
3. Physical Recovery (20 pts): Error drops significantly after force is removed (proves PID is active).
4. Physical Monotonicity (20 pts): Max deflection strictly increases with max applied force (proves physics engine causality).
5. VLM Visual Confirmation (20 pts): Trajectory frames show a 3D mechanism and simulation activity.
"""

import json
import csv
import tempfile
import os
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants
RESULT_META_PATH = "/tmp/pan_tilt_result.json"
CSV_REMOTE_PATH = "/home/ga/Documents/CoppeliaSim/exports/disturbance_timeseries.csv"
JSON_REMOTE_PATH = "/home/ga/Documents/CoppeliaSim/exports/stiffness_report.json"

VLM_PROMPT = """
Analyze these screenshots from a CoppeliaSim session where an agent was tasked with building a pan-tilt mechanism and testing its stiffness against wind disturbances.
Please verify if:
1. Is there evidence that a 3D mechanism (like a pan-tilt joint setup or robot arm) was built or loaded in the scene?
2. Is there evidence of Python scripting or ZMQ Remote API interaction (e.g., terminal output, code editor, or script logs)?
3. Does the scene show physics simulation activity or custom objects (not just the default empty grid)?

Respond in JSON format:
{
    "mechanism_visible": true/false,
    "scripting_or_api_visible": true/false,
    "physics_activity": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def find_column(headers, candidates):
    """Find a column in headers given a list of possible matching substrings."""
    lower_headers = [h.strip().lower() for h in headers]
    for c in candidates:
        for idx, h in enumerate(lower_headers):
            if c in h:
                return headers[idx]
    return None

def verify_pan_tilt_disturbance_stiffness(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback = []

    # ====================================================================
    # 1. Fetch File Metadata
    # ====================================================================
    meta_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    meta_tmp.close()
    
    try:
        copy_from_env(RESULT_META_PATH, meta_tmp.name)
        with open(meta_tmp.name, "r") as f:
            meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export metadata: {e}"}
    finally:
        os.unlink(meta_tmp.name)

    if not (meta.get("csv_exists") and meta.get("json_exists")):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Missing output files. Both disturbance_timeseries.csv and stiffness_report.json are required."
        }
    
    if not (meta.get("csv_is_new") and meta.get("json_is_new")):
        feedback.append("Warning: Output files predate task start (potential stale files).")

    # ====================================================================
    # 2. Analyze JSON Report
    # ====================================================================
    json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    json_tmp.close()
    json_valid = False
    
    try:
        copy_from_env(JSON_REMOTE_PATH, json_tmp.name)
        with open(json_tmp.name, "r") as f:
            report = json.load(f)
            
        req_keys = ["total_trials", "tested_forces_N", "peak_yaw_deflections_rad", "peak_pitch_deflections_rad", "controller_stiff_enough"]
        if all(k in report for k in req_keys):
            if report["total_trials"] >= 4 and len(report["tested_forces_N"]) >= 4:
                score += 20
                json_valid = True
                feedback.append("JSON Report Valid: contains required fields and >= 4 trials. (+20)")
            else:
                score += 10
                feedback.append(f"JSON Report Partial: fields exist but trials count is {report.get('total_trials')} (expected >= 4). (+10)")
        else:
            feedback.append("JSON Report Invalid: missing required keys.")
    except Exception as e:
        feedback.append(f"Failed to parse JSON report: {e}")
    finally:
        os.unlink(json_tmp.name)

    # ====================================================================
    # 3. Analyze CSV Timeseries Data
    # ====================================================================
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".csv")
    csv_tmp.close()
    
    try:
        copy_from_env(CSV_REMOTE_PATH, csv_tmp.name)
        
        trials_data = {}
        with open(csv_tmp.name, "r") as f:
            reader = csv.DictReader(f)
            headers = reader.fieldnames
            
            if headers:
                col_trial = find_column(headers, ["trial"])
                col_time = find_column(headers, ["time"])
                col_force = find_column(headers, ["force"])
                col_yaw = find_column(headers, ["yaw"])
                col_pitch = find_column(headers, ["pitch"])
                
                if col_force and (col_yaw or col_pitch):
                    for row in reader:
                        tid = row.get(col_trial, "1") if col_trial else "1"
                        try:
                            f_val = abs(float(row[col_force]))
                            y_val = abs(float(row[col_yaw])) if col_yaw else 0.0
                            p_val = abs(float(row[col_pitch])) if col_pitch else 0.0
                            
                            if tid not in trials_data:
                                trials_data[tid] = []
                            trials_data[tid].append({"f": f_val, "err": max(y_val, p_val)})
                        except ValueError:
                            continue
                else:
                    feedback.append("CSV lacks required force or error columns.")
    except Exception as e:
        feedback.append(f"Failed to parse CSV: {e}")
    finally:
        os.unlink(csv_tmp.name)

    # Evaluate Data Density
    if len(trials_data) >= 4 and all(len(d) >= 50 for d in trials_data.values()):
        score += 20
        feedback.append(f"CSV Density Valid: {len(trials_data)} trials with >= 50 samples each. (+20)")
    elif len(trials_data) > 0:
        score += 10
        feedback.append(f"CSV Density Partial: {len(trials_data)} trials found, varying lengths. (+10)")
    else:
        feedback.append("CSV Data Invalid: insufficient trials or sample density.")

    # Evaluate Physical Recovery & Monotonicity
    if trials_data:
        recovery_successes = 0
        trial_summaries = []
        
        for tid, data in trials_data.items():
            max_force = max(d["f"] for d in data)
            max_err = max(d["err"] for d in data)
            end_err = data[-1]["err"]
            
            # Did error recover significantly after the peak?
            if max_err > 0.001 and end_err < (0.5 * max_err):
                recovery_successes += 1
                
            trial_summaries.append({"max_f": max_force, "max_err": max_err})
            
        # Recovery criteria
        if recovery_successes >= len(trials_data) * 0.5:
            score += 20
            feedback.append("PID Recovery Valid: Joint errors drop after force removal. (+20)")
        elif recovery_successes > 0:
            score += 10
            feedback.append("PID Recovery Partial: Some trials show error decay. (+10)")
        else:
            feedback.append("PID Recovery Failed: Errors did not drop, controller may not be active.")
            
        # Monotonicity criteria (Higher force -> Higher max error)
        trial_summaries.sort(key=lambda x: x["max_f"])
        is_monotonic = True
        for i in range(1, len(trial_summaries)):
            # Allow tiny floating point tolerance
            if trial_summaries[i]["max_f"] > trial_summaries[i-1]["max_f"] + 0.1:
                if trial_summaries[i]["max_err"] < trial_summaries[i-1]["max_err"] * 0.95:
                    is_monotonic = False
                    
        if is_monotonic and len(trial_summaries) >= 3 and (trial_summaries[-1]["max_err"] > trial_summaries[0]["max_err"]):
            score += 20
            feedback.append("Physics Monotonicity Valid: Larger forces caused larger deflections. (+20)")
        else:
            feedback.append("Physics Monotonicity Failed: Deflections do not correlate correctly with applied forces.")

    # ====================================================================
    # 4. VLM Verification
    # ====================================================================
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        vlm_res = query_vlm(image=frames, prompt=VLM_PROMPT)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("mechanism_visible") and (parsed.get("scripting_or_api_visible") or parsed.get("physics_activity")):
                score += 20
                feedback.append("VLM visual verification passed: Mechanism and simulation activity detected. (+20)")
            else:
                score += 5
                feedback.append(f"VLM partial visual verification. Reasoning: {parsed.get('reasoning')}")
        else:
            feedback.append("VLM query failed, skipping visual verification points.")
    else:
        feedback.append("VLM query not available, skipping visual verification.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }