#!/usr/bin/env python3
"""
Verifier for emergency_stop_braking_analysis task.

Robust multi-signal verification analyzing dynamic robot telemetry.
Scoring (100 points):
  - 20 pts: CSV and JSON exist and were created after task start (Anti-gaming).
  - 20 pts: CSV has correct columns and >= 5 test records.
  - 30 pts: Physical Plausibility Check. Tests whether the agent correctly implemented 
            a finite 50 N.m torque check instead of snapping the velocity to 0. 
            This verifies that stopping distances correlate positively with initial speeds.
  - 30 pts: JSON validity and cross-reference check against CSV maximums.

Pass threshold: 70
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/braking_analysis_result.json"

def verify_braking_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Criterion 1: Files Exist & Are New (20 pts)
    if result.get("csv_exists") and result.get("csv_is_new"):
        score += 20
        feedback.append("CSV file was generated after task start (+20).")
    elif result.get("csv_exists"):
        feedback.append("CSV file existed before task start (stale).")
    else:
        feedback.append("braking_analysis.csv not found.")

    # Criterion 2: CSV Structure & Volume (20 pts)
    csv_analysis = result.get("csv_analysis", {})
    row_count = int(csv_analysis.get("row_count", 0))
    has_cols = csv_analysis.get("has_cols", False)
    tests = csv_analysis.get("tests", [])
    
    if has_cols and row_count >= 5:
        score += 20
        feedback.append(f"CSV has required columns and {row_count} rows (+20).")
    elif has_cols and row_count > 0:
        score += 10
        feedback.append(f"CSV has required columns but only {row_count}/5 rows (partial: 10/20).")
    elif not has_cols:
        feedback.append("CSV is missing required headers.")

    # Criterion 3: Physics Plausibility & Correlation (30 pts)
    if has_cols and len(tests) >= 2:
        valid_physics = False
        
        # We explicitly requested exactly 50 N.m torque to ensure realistic brake distances
        torques_ok = all(abs(t["tq"] - 50.0) < 1.0 for t in tests)
        
        # Sort tests by speed
        sorted_tests = sorted(tests, key=lambda x: x["v"])
        lowest_v = sorted_tests[0]
        highest_v = sorted_tests[-1]
        
        # Real physics logic: distances/times must be >0 for high speeds, and higher speeds take longer to brake
        positive_check = all(t["t"] > 0.005 and t["d"] > 0.0001 for t in tests if t["v"] > 0.1)
        correlation_check = (highest_v["d"] > lowest_v["d"]) and (highest_v["t"] > lowest_v["t"])
        
        if torques_ok and positive_check and correlation_check:
            valid_physics = True
            score += 30
            feedback.append("Dynamic physics plausibility verified: positive correlation between velocity and braking distance under 50 N·m torque (+30).")
        elif torques_ok:
            score += 15
            feedback.append("Correct braking torque applied, but physics correlation checks failed. Possible synthetic data generation (partial: 15/30).")
        else:
            feedback.append(f"Physics check failed: Applied torque does not equal 50 N·m, or physics constraints not met.")
    else:
        feedback.append("Insufficient data in CSV to verify dynamic physics.")

    # Criterion 4: JSON report validity (30 pts)
    json_fields = result.get("json_fields", {})
    json_has_fields = json_fields.get("has_fields", False)
    json_total = int(json_fields.get("total_tests", 0))
    json_max_d = float(json_fields.get("max_braking_distance_rad", 0.0))
    
    csv_max_d = max([t["d"] for t in tests]) if tests else 0.0

    if result.get("json_exists") and result.get("json_is_new") and json_has_fields and json_total >= 5:
        # Cross reference the JSON max distance with the actual CSV max distance
        if abs(json_max_d - csv_max_d) < 0.05:
            score += 30
            feedback.append("JSON report valid and cross-references successfully with CSV data (+30).")
        else:
            score += 15
            feedback.append(f"JSON valid, but `max_braking_distance_rad` ({json_max_d:.2f}) does not match CSV ({csv_max_d:.2f}) (partial: 15/30).")
    elif result.get("json_exists") and result.get("json_is_new") and json_has_fields:
        score += 10
        feedback.append(f"JSON valid but only reports {json_total} tests (partial: 10/30).")
    else:
        feedback.append("JSON report is missing, stale, or lacks required fields.")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
    }