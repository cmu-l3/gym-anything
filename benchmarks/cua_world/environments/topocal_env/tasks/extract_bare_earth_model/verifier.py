#!/usr/bin/env python3
"""
Verifier for extract_bare_earth_model task.

Verification Strategy:
1. Export Validation (10 pts): Checks if CSV and TOP files were created/modified during task execution.
2. Data Cleaning (30 pts): Parses exported CSV. Verifies strict absence of roof points (Z > 1608.0).
3. Data Retention (25 pts): Ensures the agent didn't indiscriminately delete all points (expect ~800 ground points).
4. Project Integrity (15 pts): Confirms native .top file existence.
5. VLM Trajectory (20 pts): Visual verification of workflow (roof selection/deletion and TIN generation).
"""

import json
import os
import csv
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_bare_earth_model(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0
    max_score = 100

    # ---------------------------------------------------------
    # 1. Read exported JSON state
    # ---------------------------------------------------------
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/temp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Validate output files exist and were modified correctly
    if result.get('csv_exists') and result.get('csv_modified'):
        score += 5
        feedback.append("CSV exported successfully")
    else:
        feedback.append("CSV not exported or not modified")

    if result.get('top_exists') and result.get('top_modified'):
        score += 20  # +5 for export check, +15 for Project Integrity
        feedback.append("TopoCal project (.top) saved successfully")
    else:
        feedback.append("TopoCal project not saved")

    # ---------------------------------------------------------
    # 2 & 3. Point Data Analysis (Data Cleaning & Retention)
    # ---------------------------------------------------------
    max_z = float('-inf')
    ground_count = 0
    z_col_idx = -1

    if result.get('csv_exists'):
        temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
        try:
            copy_from_env("C:/Users/Docker/Documents/bare_earth_points.csv", temp_csv.name)
            
            with open(temp_csv.name, 'r') as f:
                reader = csv.reader(f)
                rows = list(reader)

                if rows:
                    # Robust column inference: find the column representing Z (1500 to 1700 range)
                    for i in range(len(rows[0])):
                        try:
                            val = float(rows[0][i])
                            if 1500 < val < 1700:
                                z_col_idx = i
                                break
                        except ValueError:
                            continue

                    if z_col_idx != -1:
                        for r in rows:
                            try:
                                z_val = float(r[z_col_idx])
                                max_z = max(max_z, z_val)
                                ground_count += 1
                            except (ValueError, IndexError):
                                continue
        except Exception as e:
            logger.error(f"Error parsing CSV: {e}")
        finally:
            if os.path.exists(temp_csv.name):
                os.unlink(temp_csv.name)

    # Evaluate Anomaly Removal (Z > 1608.0)
    if ground_count > 0:
        if max_z <= 1608.0:
            score += 30
            feedback.append(f"Roof anomalies removed (Max Z={max_z:.2f} <= 1608.0)")
        else:
            feedback.append(f"Roof anomalies STILL PRESENT (Max Z={max_z:.2f} > 1608.0)")
    else:
        feedback.append("No valid points found in CSV")

    # Evaluate Data Retention (~800 points expected)
    if ground_count >= 760:
        score += 25
        feedback.append(f"Ground data retained correctly ({ground_count} points)")
    elif ground_count >= 400:
        score += 10
        feedback.append(f"Partial ground data loss ({ground_count}/800 points)")
    elif ground_count > 0:
        feedback.append(f"Severe data loss ({ground_count} points remaining)")

    # ---------------------------------------------------------
    # 4. VLM Trajectory Verification
    # ---------------------------------------------------------
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """You are verifying a computer agent performing a land surveying task in TopoCal.
TASK: Remove building roof points and generate a triangulated terrain model (MDT/TIN).

Look closely at these trajectory screenshots and respond in JSON format:
1. "roof_deleted": Did the agent select and delete the high-elevation flat cluster of points (the roof)?
2. "tin_generated": Is a triangulated mesh (MDT/TIN) visible connecting the points?
3. "hole_present": Does the final mesh correctly show a flat gap/hole where the building points were removed?

{
    "roof_deleted": true/false,
    "tin_generated": true/false,
    "hole_present": true/false
}"""
        vlm_res = query_vlm(prompt=prompt, images=images)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("roof_deleted", False):
                score += 5
            if parsed.get("tin_generated", False):
                score += 10
                feedback.append("VLM confirmed TIN generation")
            if parsed.get("hole_present", False):
                score += 5
        else:
            logger.warning("VLM evaluation failed.")

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    # Must achieve at least 75 points and must have actually cleaned the high points
    passed = score >= 75 and (max_z != float('-inf') and max_z <= 1608.0)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }