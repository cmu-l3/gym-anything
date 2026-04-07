#!/usr/bin/env python3
"""
Verifier for camera_fov_coverage_optimization task.

Scoring (100 points max):
  - Criterion 1 (15 pts): All four required output files exist and were newly created.
  - Criterion 2 (20 pts): CSV contains >= 16 rows and required columns.
  - Criterion 3 (20 pts): Spatial variation shows a sweep of >= 4 unique Z and >= 4 unique pitch.
  - Criterion 4 (25 pts): Visibility values are within [0, 9] and show actual variation.
  - Criterion 5 (20 pts): JSON report exists and contains the required analytical fields.

Pass threshold: 75/100 points
Anti-gaming: If Python script lacks `sim.` API calls, the logic is considered invalid.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/camera_fov_coverage_result.json"

def verify_camera_fov_coverage(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run successfully."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []
    
    files = result.get("files", {})
    csv = files.get("csv", {})
    json_f = files.get("json", {})
    py = files.get("py", {})
    ttt = files.get("ttt", {})

    # Anti-gaming check: Did they write a script utilizing the CoppeliaSim API?
    if not py.get("has_api", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Anti-gaming failure: Python script is missing or does not contain ZMQ Remote API calls ('sim.')."
        }

    # 1. Output files exist and are fresh (15 pts)
    files_score = 0
    if csv.get("exists") and csv.get("new"): files_score += 4
    if json_f.get("exists") and json_f.get("new"): files_score += 4
    if py.get("exists") and py.get("new"): files_score += 4
    if ttt.get("exists") and ttt.get("new"): files_score += 3
    
    score += files_score
    if files_score == 15:
        feedback.append("All output files created successfully (+15)")
    else:
        feedback.append(f"Some files missing or predated the task start (+{files_score})")

    csv_a = result.get("csv_analysis", {})
    
    # 2. Sweep Volume (20 pts)
    if csv_a.get("has_cols", False):
        rows = csv_a.get("row_count", 0)
        if rows >= 16:
            score += 20
            feedback.append(f"Sweep volume sufficient: {rows} candidate poses (+20)")
        elif rows >= 4:
            score += 10
            feedback.append(f"Sweep volume partial: {rows} candidate poses (partial: 10/20)")
        else:
            feedback.append("Sweep volume insufficient (< 4 rows)")
    else:
        feedback.append("CSV lacks the required columns (z_m, pitch_deg, visible_count)")

    # 3. Spatial Variation (20 pts)
    if csv_a.get("has_cols", False):
        uz = csv_a.get("unique_z", 0)
        up = csv_a.get("unique_p", 0)
        if uz >= 4 and up >= 4:
            score += 20
            feedback.append(f"Spatial variation excellent: {uz} Z levels, {up} pitch angles (+20)")
        elif uz >= 2 and up >= 2:
            score += 10
            feedback.append(f"Spatial variation partial: {uz} Z levels, {up} pitch angles (+10)")
        else:
            feedback.append(f"Spatial variation poor: only {uz} Z levels, {up} pitch angles tested")

    # 4. Visibility Logic (25 pts)
    if csv_a.get("has_cols", False):
        valid = csv_a.get("valid_v", False)
        uv = csv_a.get("unique_v", 0)
        if valid and uv > 1:
            score += 25
            feedback.append("Visibility tracking valid: values within [0, 9] showing camera FOV variation (+25)")
        elif valid:
            score += 10
            feedback.append("Visibility tracking partial: valid bounds [0, 9] but all values were identical (+10)")
        else:
            feedback.append("Visibility tracking invalid: values fell outside expected range [0, 9] or could not parse integers")

    # 5. JSON Report (20 pts)
    json_a = result.get("json_analysis", {})
    if json_a.get("has_fields", False):
        total = json_a.get("total", 0)
        if total >= 16:
            score += 20
            feedback.append(f"JSON analysis report valid: correctly structured with {total} poses (+20)")
        elif total > 0:
            score += 10
            feedback.append(f"JSON analysis report partial: {total} poses (+10)")
        else:
            feedback.append("JSON analysis report has fields but invalid totals.")
    else:
        feedback.append("JSON analysis report missing or lacking required fields.")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }