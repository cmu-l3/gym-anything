#!/usr/bin/env python3
"""
Verifier for olympic_marathon_heat_relocation_assessment task.

Scoring criteria (100 pts total, pass threshold = 80):
  1. Regional Plot Exported (20 pts): japan_august_temp.png exists, >= 15KB.
  2. Report Structure (20 pts): marathon_relocation_audit.txt exists, has all keys.
  3. Tokyo Data Accuracy (20 pts): TOKYO_GRID_TEMP_C is correctly extracted from NCEP (23.0 to 29.0).
  4. Sapporo Data Accuracy (20 pts): SAPPORO_GRID_TEMP_C is correctly extracted from NCEP (18.0 to 24.0).
  5. Logic & Conclusion (10 pts): TEMP_DIFFERENCE_C is correct math, CONCLUSION is VALID.
  6. VLM Trajectory Verification (10 pts): Confirms Panoply workflow visually.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Prompt for the VLM to verify trajectory
VLM_PROMPT = """You are verifying an agent's trajectory in NASA Panoply.
Task: The agent must zoom into Japan on the map and extract specific temperature data for Tokyo and Sapporo.

Look at the trajectory frames and final screenshot:
1. Did the agent interact with NASA Panoply?
2. Did the agent view a map that is zoomed in on Japan (approx 25-50°N, 125-150°E) instead of a global view?
3. Did the agent look at numerical data (e.g., opening the 'Array' tab, or using the data probe tooltip)?

Answer with a JSON object:
{
    "panoply_used": true/false,
    "zoomed_to_japan": true/false,
    "viewed_numerical_data": true/false
}
"""

def extract_float(string_val):
    """Safely extract float from string (e.g., '26.5 °C' -> 26.5)"""
    match = re.search(r'-?\d+\.?\d*', string_val)
    if match:
        return float(match.group(0))
    return None

def verify_olympic_marathon_heat_relocation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Retrieve result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/olympic_marathon_heat_relocation_assessment_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    score = 0
    feedback = []
    task_start = int(result.get('task_start', 0))

    # Get valid bounds from metadata
    meta = task_info.get('metadata', {})
    tokyo_valid = meta.get('tokyo_valid_range_c', [23.0, 29.0])
    sapporo_valid = meta.get('sapporo_valid_range_c', [18.0, 24.0])

    # ----------------------------------------------------------------
    # Criterion 1: Plot exported (20 pts)
    # ----------------------------------------------------------------
    plot_exists = result.get('plot_exists', False)
    plot_mtime = int(result.get('plot_mtime', 0))
    plot_size = int(result.get('plot_size', 0))

    if plot_exists and plot_mtime >= task_start and plot_size >= 15000:
        score += 20
        feedback.append(f"Regional plot exported ({plot_size} bytes)")
    elif plot_exists and plot_mtime >= task_start and plot_size >= 5000:
        score += 10
        feedback.append(f"Plot present but suspiciously small ({plot_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Plot missing or not created during task (exists={plot_exists})")

    # ----------------------------------------------------------------
    # Criterion 2: Report Structure (20 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    tokyo_raw = result.get('tokyo_c', '').strip()
    sapporo_raw = result.get('sapporo_c', '').strip()
    diff_raw = result.get('diff_c', '').strip()
    conclusion_raw = result.get('conclusion', '').strip()
    
    has_all_keys = bool(tokyo_raw) and bool(sapporo_raw) and bool(diff_raw) and bool(conclusion_raw)
    
    if report_exists and report_mtime >= task_start and has_all_keys:
        score += 20
        feedback.append("Report structurally complete with all keys.")
    elif report_exists and report_mtime >= task_start:
        score += 10
        feedback.append("Report exists but missing some required keys.")
    else:
        feedback.append("Audit report missing or not created during task.")

    # ----------------------------------------------------------------
    # Criterion 3 & 4: Data Accuracy (20 + 20 pts)
    # ----------------------------------------------------------------
    tokyo_val = extract_float(tokyo_raw)
    sapporo_val = extract_float(sapporo_raw)

    # Tokyo Check
    if tokyo_val is not None:
        if tokyo_val > 100:
            feedback.append(f"Tokyo temp ({tokyo_val}) looks like Kelvin! You must convert to Celsius.")
        elif tokyo_valid[0] <= tokyo_val <= tokyo_valid[1]:
            score += 20
            feedback.append(f"Tokyo temperature accurate: {tokyo_val}°C")
        else:
            feedback.append(f"Tokyo temp ({tokyo_val}°C) is outside expected NCEP grid bounds {tokyo_valid}.")
    else:
        feedback.append("Could not parse Tokyo temperature as a number.")

    # Sapporo Check
    if sapporo_val is not None:
        if sapporo_val > 100:
            feedback.append(f"Sapporo temp ({sapporo_val}) looks like Kelvin! You must convert to Celsius.")
        elif sapporo_valid[0] <= sapporo_val <= sapporo_valid[1]:
            score += 20
            feedback.append(f"Sapporo temperature accurate: {sapporo_val}°C")
        else:
            feedback.append(f"Sapporo temp ({sapporo_val}°C) is outside expected NCEP grid bounds {sapporo_valid}.")
    else:
        feedback.append("Could not parse Sapporo temperature as a number.")

    # ----------------------------------------------------------------
    # Criterion 5: Logic & Conclusion (10 pts)
    # ----------------------------------------------------------------
    diff_val = extract_float(diff_raw)
    conclusion_valid = (conclusion_raw.upper() == "VALID")

    if tokyo_val is not None and sapporo_val is not None and diff_val is not None:
        expected_diff = round(tokyo_val - sapporo_val, 2)
        if abs(diff_val - expected_diff) < 0.2 and conclusion_valid:
            score += 10
            feedback.append("Difference math is correct and conclusion is VALID.")
        elif conclusion_valid:
            score += 5
            feedback.append(f"Conclusion VALID, but difference math incorrect (expected ~{expected_diff}, got {diff_val}).")
        else:
            feedback.append("Conclusion not reported as VALID.")
    else:
        feedback.append("Cannot evaluate math due to missing data.")

    # ----------------------------------------------------------------
    # Criterion 6: VLM Trajectory Verification (10 pts)
    # ----------------------------------------------------------------
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            
            images_to_check = frames
            if final_img:
                images_to_check.append(final_img)
                
            if images_to_check:
                vlm_res = query_vlm(images=images_to_check, prompt=VLM_PROMPT)
                if vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    panoply_used = parsed.get("panoply_used", False)
                    zoomed = parsed.get("zoomed_to_japan", False)
                    array_viewed = parsed.get("viewed_numerical_data", False)
                    
                    vlm_score = 0
                    if panoply_used: vlm_score += 4
                    if zoomed: vlm_score += 3
                    if array_viewed: vlm_score += 3
                    
                    score += vlm_score
                    feedback.append(f"VLM verification ({vlm_score}/10): panoply={panoply_used}, zoomed={zoomed}, array={array_viewed}")
                else:
                    feedback.append(f"VLM check failed: {vlm_res.get('error')}")
                    # Give benefit of doubt on API failure if file structure is solid
                    if plot_exists and has_all_keys:
                        score += 10
                        feedback.append("Awarded VLM points by default due to API failure but solid outputs.")
            else:
                feedback.append("No frames available for VLM verification.")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback.append("Error processing VLM checks.")
            
    # Key criteria: Must have plot, report, and good accuracy
    key_criteria_met = (plot_exists and report_exists and tokyo_val is not None and sapporo_val is not None)
    passed = (score >= 80) and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback),
        "details": {
            "tokyo_c": tokyo_val,
            "sapporo_c": sapporo_val,
            "diff_c": diff_val,
            "conclusion": conclusion_raw
        }
    }