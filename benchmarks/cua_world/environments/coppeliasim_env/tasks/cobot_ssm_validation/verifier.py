#!/usr/bin/env python3
"""
Verifier for cobot_ssm_validation task.

Scoring (100 points Total):
  - File Existence & Timestamps (15 pts): Both files exist and are created after task start.
  - Valid Schema (15 pts): CSV has required columns, JSON has required fields.
  - Dynamic Approach Captured (25 pts): CSV distance drops from > 1.4m to < 0.5m.
  - Zone Thresholds Applied (25 pts): GREEN > 1.0m, YELLOW 0.5m-1.0m, RED < 0.5m.
  - Speed Modulation Correct (20 pts): GREEN speed > YELLOW speed > 0, RED speed == 0.

VLM Verification: Analyzes trajectory frames to detect scripting/simulator usage. 
Acts as an anti-gaming veto if absolute no scripting interaction is visible.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

RESULT_PATH = "/tmp/cobot_ssm_result.json"


def verify_cobot_ssm_validation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Safely load the compiled results from the container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp.close()
    try:
        copy_from_env(RESULT_PATH, tmp.name)
        with open(tmp.name, "r") as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found — export script did not run successfully."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result payload: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    feedback = []

    # Check 1: File Existence & Timestamps (15 pts)
    csv_ok = result.get("csv_exists") and result.get("csv_is_new")
    json_ok = result.get("json_exists") and result.get("json_is_new")
    
    if csv_ok and json_ok:
        score += 15
        feedback.append("Both output files created successfully during task (+15)")
    elif result.get("csv_exists") or result.get("json_exists"):
        feedback.append("Output files exist but are missing or stale (predate task start).")
    else:
        feedback.append("No output files found. Do-nothing attempt.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # Parse components for deep checks
    csv_analysis = result.get("csv_analysis", {})
    json_fields = result.get("json_fields", {})
    
    has_rows = csv_analysis.get("has_rows", False)
    has_cols = csv_analysis.get("has_cols", False)
    has_jfields = json_fields.get("has_fields", False)

    # Check 2: Valid Schema (15 pts)
    if has_cols and has_jfields:
        score += 15
        feedback.append("CSV columns and JSON fields schema match requirements (+15)")
    else:
        if not has_cols: feedback.append("CSV missing required columns.")
        if not has_jfields: feedback.append("JSON missing required fields.")

    # Only process data logic if rows exist
    if has_rows:
        start_dist = csv_analysis.get("start_distance", 0.0)
        end_dist = csv_analysis.get("end_distance", 0.0)
        
        # Check 3: Dynamic Approach Captured (25 pts)
        if start_dist >= 1.4 and end_dist <= 0.5:
            score += 25
            feedback.append(f"Dynamic approach captured correctly: starts {start_dist:.2f}m, ends {end_dist:.2f}m (+25)")
        elif start_dist > 1.0 and end_dist < 0.8:
            score += 10
            feedback.append(f"Partial approach captured: starts {start_dist:.2f}m, ends {end_dist:.2f}m (+10/25)")
        else:
            feedback.append(f"Approach bounds invalid: starts {start_dist:.2f}m, ends {end_dist:.2f}m.")

        # Check 4: Zone Thresholds Applied (25 pts)
        zone_correct = csv_analysis.get("zone_logic_correct", False)
        has_g = csv_analysis.get("has_green", False)
        has_y = csv_analysis.get("has_yellow", False)
        has_r = csv_analysis.get("has_red", False)
        
        if zone_correct and has_g and has_y and has_r:
            score += 25
            feedback.append("All safety zones mapped correctly to distance thresholds (+25)")
        elif has_g and has_r:
            score += 10
            feedback.append("Safety zones triggered but thresholds imprecise or missing YELLOW (+10/25)")
        else:
            feedback.append("Zone assignment logic to distances is incorrect.")

        # Check 5: Speed Modulation Correct (20 pts)
        mean_g = csv_analysis.get("mean_green_speed", 0.0)
        mean_y = csv_analysis.get("mean_yellow_speed", 0.0)
        max_r = csv_analysis.get("max_red_speed", 0.0)
        succ_stop = json_fields.get("successful_stop", False)

        if mean_g > mean_y and mean_y > 0.0 and max_r <= 0.001 and succ_stop:
            score += 20
            feedback.append(f"Speed correctly modulated (Green: {mean_g:.2f} > Yellow: {mean_y:.2f} > Red: {max_r:.2f}) (+20)")
        elif mean_g > 0.0 and max_r <= 0.001:
            score += 10
            feedback.append(f"Partial speed modulation (Green: {mean_g:.2f}, Red: {max_r:.2f}) (+10/20)")
        else:
            feedback.append(f"Speed logic invalid (Green: {mean_g:.2f}, Yellow: {mean_y:.2f}, Red: {max_r:.2f}).")
    else:
        feedback.append("Telemetry CSV has no data rows.")

    # -------------------------------------------------------------
    # VLM Trajectory Anti-Gaming Check
    # -------------------------------------------------------------
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """Look at these screenshots from a robotics simulation workstation.
                Did the user write a Python script (e.g. in a code editor, terminal, or IDE) and run it with the CoppeliaSim environment?
                Respond in JSON: {"scripting_visible": true/false}"""
                
                vlm_res = query_vlm(prompt=prompt, images=images)
                if vlm_res and vlm_res.get('parsed'):
                    scripting_visible = vlm_res['parsed'].get('scripting_visible', True)
                    if not scripting_visible:
                        feedback.append("VLM WARNING: No visible scripting or simulator interaction in trajectory. Score capped.")
                        score = min(score, 45) # Hard cap if VLM says agent did nothing
        except Exception as e:
            logger.warning(f"VLM trajectory check failed: {e}")

    passed = score >= 75
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }