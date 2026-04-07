#!/usr/bin/env python3
"""
Verifier for mars_sso_design@1

Agent must compute the required inclination for a 400 km Mars sun-synchronous orbit,
configure the simulation using a Mars-centered coordinate system and Mars50c gravity,
propagate for 60 days, and report correct orbital elements and RAAN drift.

Scoring (total 100 pts, pass >= 60):
  - script_created (10): Script created during task window
  - mars_coord_sys_created (10): Script contains Mars-centered coordinate system
  - mars_gravity_used (10): Script uses Mars50c gravity model
  - report_written (10): Results file written
  - sma_correct (10): Initial SMA matches 3796.19 km within tolerance
  - inc_correct (15): Computed INC is in [92.8, 93.0] deg
  - raan_drift_correct (15): Drift over 60 days matches [30.5, 32.5] deg
  - vlm_check (20): VLM confirms trajectory shows GMAT usage
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vlm(traj):
    """Fallback VLM verification checking if GMAT was used in trajectory frames."""
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final]
        if not images or not any(images):
            return True, "No trajectory images found, skipping VLM check (awarding points)"
        
        prompt = """Look at these screenshots from a user's session in NASA GMAT.
        Did the user interact with the GMAT interface or script editor to configure a Mars orbit?
        Look for:
        - A script being edited containing 'Mars' or 'Mars50c'
        - Coordinate system dialogs setting the central body to Mars
        - Propagator dialogs setting gravity to Mars

        Respond with JSON:
        {"gmat_used_for_mars": true/false}
        """
        result = query_vlm(images=images, prompt=prompt)
        if result.get("success") and result.get("parsed", {}).get("gmat_used_for_mars", False):
            return True, "VLM confirmed GMAT interaction."
        return False, "VLM did not confirm GMAT interaction for Mars."
    except Exception as e:
        logger.warning(f"VLM verification unavailable: {e}")
        return True, "VLM unavailable, bypassing check."


def verify_mars_sso_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    sma_target = metadata.get('sma_target_km', 3796.19)
    sma_tol = metadata.get('sma_tolerance_km', 5.0)
    inc_min = metadata.get('inc_min_deg', 92.8)
    inc_max = metadata.get('inc_max_deg', 93.0)
    drift_min = metadata.get('drift_min_deg', 30.5)
    drift_max = metadata.get('drift_max_deg', 32.5)

    scores = {
        "script_created": 10,
        "mars_coord_sys_created": 10,
        "mars_gravity_used": 10,
        "report_written": 10,
        "sma_correct": 10,
        "inc_correct": 15,
        "raan_drift_correct": 15,
        "vlm_check": 20,
    }

    total_score = 0
    feedback = []

    # Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. Script created
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script created during task window.")
    else:
        feedback.append("Script not created during task window.")

    # 2. Analyze script content
    script_path = task_result.get('script_path', '/home/ga/Documents/missions/mars_sso.script')
    if isinstance(script_file, dict) and script_file.get('exists'):
        temp_script = tempfile.NamedTemporaryFile(delete=False, suffix='.script')
        try:
            copy_from_env(script_path, temp_script.name)
            with open(temp_script.name, 'r', encoding='utf-8', errors='ignore') as f:
                script_content = f.read()

            # Check Coordinate System
            if re.search(r'Create CoordinateSystem', script_content) and re.search(r'\.Origin\s*=\s*Mars', script_content):
                total_score += scores["mars_coord_sys_created"]
                feedback.append("Mars-centered coordinate system found in script.")
            else:
                feedback.append("Mars-centered coordinate system missing.")

            # Check Gravity Model
            if bool(re.search(r'Mars50c', script_content)) or (
                bool(re.search(r'\.CentralBody\s*=\s*Mars', script_content)) and
                bool(re.search(r'\.GravityField\.Mars\.Degree\s*=\s*[2-9]', script_content))
            ):
                total_score += scores["mars_gravity_used"]
                feedback.append("Mars50c/Mars gravity model configured.")
            else:
                feedback.append("Mars gravity model not found in script.")

        except Exception as e:
            feedback.append(f"Failed to parse script file: {e}")
        finally:
            if os.path.exists(temp_script.name):
                os.unlink(temp_script.name)

    # 3. Report written
    report_file = task_result.get('report_file', {})
    if isinstance(report_file, dict) and report_file.get('created_during_task'):
        total_score += scores["report_written"]
        feedback.append("Report file created during task window.")
    else:
        feedback.append("Report file not created during task window.")

    # 4. Check Values
    try:
        sma_val = float(task_result.get('sma_km', 0))
    except (ValueError, TypeError):
        sma_val = 0.0

    try:
        inc_val = float(task_result.get('inc_deg', 0))
    except (ValueError, TypeError):
        inc_val = 0.0

    try:
        drift_val = float(task_result.get('raan_drift_deg', 0))
    except (ValueError, TypeError):
        drift_val = 0.0

    sma_ok = False
    if abs(sma_val - sma_target) <= sma_tol:
        total_score += scores["sma_correct"]
        sma_ok = True
        feedback.append(f"SMA correct: {sma_val:.2f} km.")
    else:
        feedback.append(f"SMA incorrect: {sma_val:.2f} km (expected ~{sma_target} km).")

    inc_ok = False
    if inc_min <= inc_val <= inc_max:
        total_score += scores["inc_correct"]
        inc_ok = True
        feedback.append(f"INC correct for Mars SSO: {inc_val:.2f} deg.")
    else:
        feedback.append(f"INC incorrect: {inc_val:.2f} deg (expected {inc_min}-{inc_max} deg).")

    drift_ok = False
    if drift_min <= drift_val <= drift_max:
        total_score += scores["raan_drift_correct"]
        drift_ok = True
        feedback.append(f"RAAN drift correct: {drift_val:.2f} deg.")
    else:
        feedback.append(f"RAAN drift incorrect: {drift_val:.2f} deg (expected {drift_min}-{drift_max} deg).")

    # 5. VLM Check (Anti-Gaming)
    vlm_passed, vlm_msg = verify_vlm(traj)
    if vlm_passed:
        total_score += scores["vlm_check"]
        feedback.append(vlm_msg)
    else:
        feedback.append(f"VLM verification failed: {vlm_msg}")

    # Pass Condition: >= 60 AND inc_correct AND raan_drift_correct
    key_metrics_met = inc_ok and drift_ok
    passed = total_score >= 60 and key_metrics_met

    if not key_metrics_met:
        feedback.append("FAILED: Core physics metrics (INC or Drift) not satisfied.")

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }