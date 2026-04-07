#!/usr/bin/env python3
"""Verifier for utility_meter_reading_log_and_anomaly_response task.

Scoring Criteria:
1. Readings Logged (30 pts): Active meters have new reading in Description.
2. Anomaly WOs Created (30 pts): High usage meters have a WO.
3. WO Quality (10 pts): High priority and correct asset link.
4. Normal Meters Skipped (10 pts): No WO for normal usage.
5. Inactive Skipped (20 pts): Inactive meter untouched.
"""

import json
import logging
import os
import tempfile

logger = logging.getLogger(__name__)

def verify_utility_meter_reading_log_and_anomaly_response(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as tmp:
            local_path = tmp.name
        copy_from_env("/tmp/meter_result.json", local_path)
        with open(local_path) as f:
            result = json.load(f)
        os.unlink(local_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export failed: {e}"}

    if result.get("error"):
        return {"passed": False, "score": 0, "feedback": f"Export error: {result['error']}"}

    asset_states = result.get("asset_states", {})
    created_wos = result.get("created_wos", [])

    score = 0
    feedback = []

    # Expected Data
    # UTIL-E-101: 45600 (Update Only)
    # UTIL-E-102: 14500 (Update + WO)
    # UTIL-W-201: 3300 (Update Only)
    # UTIL-W-202: 8600 (Update + WO)
    # UTIL-G-005: Inactive (Skip)

    # 1. Verify Readings (30 pts)
    # Check active meters
    reading_points = 0
    for code, expected_val in [("UTIL-E-101", "45600"), ("UTIL-E-102", "14500"), ("UTIL-W-201", "3300"), ("UTIL-W-202", "8600")]:
        state = asset_states.get(code, {})
        desc = state.get("description", "")
        # Look for pattern "2026-03-15: [Value]"
        expected_str = f"2026-03-15: {expected_val}"
        if expected_str in desc:
            reading_points += 7.5
            feedback.append(f"{code}: Reading logged correctly.")
        else:
            feedback.append(f"{code}: Missing reading '{expected_str}'.")
    
    score += round(reading_points)

    # 2. Verify Work Orders (Anomalies) (30 pts + 10 pts Quality)
    wo_points = 0
    quality_points = 0
    
    anomalies = ["UTIL-E-102", "UTIL-W-202"]
    
    for code in anomalies:
        # Find WO for this asset
        relevant_wos = [wo for wo in created_wos if wo.get("asset_code") == code]
        
        if relevant_wos:
            wo_points += 15
            feedback.append(f"{code}: Anomaly WO created.")
            
            # Check Quality
            wo = relevant_wos[0]
            prio = wo.get("priority", "")
            if any(p in prio for p in ["high", "critical", "urgent", "emergency"]):
                quality_points += 5
                feedback.append(f"{code}: WO priority correct ({prio}).")
            else:
                feedback.append(f"{code}: WO priority low/incorrect ({prio}).")
        else:
            feedback.append(f"{code}: Missing Anomaly WO.")
            
    score += wo_points
    score += quality_points

    # 3. Verify Normal Meters Skipped (10 pts)
    normal_meters = ["UTIL-E-101", "UTIL-W-201"]
    fp_penalty = 0
    for code in normal_meters:
        relevant_wos = [wo for wo in created_wos if wo.get("asset_code") == code]
        if relevant_wos:
            fp_penalty += 5
            feedback.append(f"{code}: False positive WO created (Penalty).")
    
    normal_score = max(0, 10 - fp_penalty)
    score += normal_score

    # 4. Verify Inactive Skipped (20 pts)
    inactive_code = "UTIL-G-005"
    inactive_state = asset_states.get(inactive_code, {})
    inactive_desc = inactive_state.get("description", "")
    
    inactive_updated = "2026-03-15" in inactive_desc
    inactive_wo = [wo for wo in created_wos if wo.get("asset_code") == inactive_code]
    
    if not inactive_updated and not inactive_wo:
        score += 20
        feedback.append("Inactive meter correctly skipped.")
    else:
        if inactive_updated:
            feedback.append("Inactive meter was updated.")
        if inactive_wo:
            feedback.append("Inactive meter has WO.")

    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " ".join(feedback)
    }