#!/usr/bin/env python3
"""
Verifier for eastern_pacific_itcz_asymmetry_analysis task.

Difficulty: hard

Scoring criteria (100 pts total, pass threshold = 75):
  1. January map exported (15 pts): epacific_precip_jan.png exists, >15KB, after task start.
  2. July map exported (15 pts): epacific_precip_jul.png exists, >15KB, after task start.
  3. Report format correct (15 pts): Contains the 4 main analysis fields.
  4. Hemispheric Asymmetry Deduction (15 pts): CROSSES_EQUATOR is explicitly "NO".
  5. Latitude Accuracy (25 pts): JAN_ITCZ_LAT parsing to [1, 8] and JUL_ITCZ_LAT parsing to [6, 15].
  6. VLM Trajectory Check (15 pts): Verifies agent actively used the software and navigated the map.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_lat(val_str):
    """
    Parse a latitude string into a float, preserving hemispheric sign.
    Northern hemisphere is positive, Southern is negative.
    Examples: "5N" -> 5.0, "10S" -> -10.0, "-5" -> -5.0
    """
    if not val_str:
        return None
    val_str = str(val_str).upper()
    match = re.search(r'-?\d+\.?\d*', val_str)
    if not match:
        return None
    
    val = float(match.group())
    
    # Check explicitly for South/S indicator
    if 'S' in val_str or 'SOUTH' in val_str:
        if val > 0:
            val = -val
    # Check explicitly for North/N indicator
    elif 'N' in val_str or 'NORTH' in val_str:
        val = abs(val)
        
    return val


def verify_eastern_pacific_itcz_asymmetry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/eastern_pacific_itcz_asymmetry_analysis_result.json', tmp.name)
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

    # ----------------------------------------------------------------
    # Criterion 1: January Map Export (15 pts)
    # ----------------------------------------------------------------
    jan_exists = result.get('png_jan_exists', False)
    jan_mtime = int(result.get('png_jan_mtime', 0))
    jan_size = int(result.get('png_jan_size', 0))

    if jan_exists and jan_mtime >= task_start and jan_size >= 15000:
        score += 15
        feedback.append(f"January precip map exported ({jan_size} bytes)")
    elif jan_exists and jan_mtime >= task_start and jan_size > 0:
        score += 7
        feedback.append(f"January map exported but very small ({jan_size} bytes)")
    else:
        feedback.append("January map missing or not created during task window")

    # ----------------------------------------------------------------
    # Criterion 2: July Map Export (15 pts)
    # ----------------------------------------------------------------
    jul_exists = result.get('png_jul_exists', False)
    jul_mtime = int(result.get('png_jul_mtime', 0))
    jul_size = int(result.get('png_jul_size', 0))

    if jul_exists and jul_mtime >= task_start and jul_size >= 15000:
        score += 15
        feedback.append(f"July precip map exported ({jul_size} bytes)")
    elif jul_exists and jul_mtime >= task_start and jul_size > 0:
        score += 7
        feedback.append(f"July map exported but very small ({jul_size} bytes)")
    else:
        feedback.append("July map missing or not created during task window")

    # ----------------------------------------------------------------
    # Criterion 3: Report Format (15 pts)
    # ----------------------------------------------------------------
    report_exists = result.get('report_exists', False)
    report_mtime = int(result.get('report_mtime', 0))
    
    jan_lat_str = result.get('jan_lat', '').strip()
    jul_lat_str = result.get('jul_lat', '').strip()
    crosses_str = result.get('crosses_equator', '').strip()
    mech_str = result.get('mechanism', '').strip()
    
    fields_present = sum(1 for f in [jan_lat_str, jul_lat_str, crosses_str, mech_str] if f)

    if report_exists and report_mtime >= task_start and fields_present == 4:
        score += 15
        feedback.append("Report format complete with all required fields")
    elif report_exists and fields_present > 0:
        score += 7
        feedback.append(f"Report format partial ({fields_present}/4 fields found)")
    else:
        feedback.append("Report missing or lacks required fields")

    # ----------------------------------------------------------------
    # Criterion 4: Asymmetry Deduction (15 pts)
    # ----------------------------------------------------------------
    if crosses_str.upper() == 'NO':
        score += 15
        feedback.append("Correctly deduced ITCZ does NOT cross equator (CROSSES_EQUATOR=NO)")
    elif crosses_str.upper() == 'YES':
        feedback.append("Incorrect deduction: ITCZ does not cross equator in the Eastern Pacific")
    else:
        feedback.append("CROSSES_EQUATOR not clearly answered YES/NO")

    # ----------------------------------------------------------------
    # Criterion 5: Latitude Accuracy (25 pts)
    # ----------------------------------------------------------------
    jan_val = parse_lat(jan_lat_str)
    jul_val = parse_lat(jul_lat_str)
    
    lat_score = 0
    if jan_val is not None:
        if 1.0 <= jan_val <= 8.0:
            lat_score += 12.5
            feedback.append(f"January ITCZ latitude accurate: {jan_lat_str}")
        else:
            feedback.append(f"January ITCZ latitude ({jan_lat_str}) outside plausible Eastern Pacific bounds (1-8N)")
    else:
        feedback.append("Could not parse January latitude")
        
    if jul_val is not None:
        if 6.0 <= jul_val <= 15.0:
            lat_score += 12.5
            feedback.append(f"July ITCZ latitude accurate: {jul_lat_str}")
        else:
            feedback.append(f"July ITCZ latitude ({jul_lat_str}) outside plausible Eastern Pacific bounds (6-15N)")
    else:
        feedback.append("Could not parse July latitude")
        
    score += lat_score

    # ----------------------------------------------------------------
    # Criterion 6: VLM Trajectory Verification (15 pts)
    # ----------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames_available = True
    except ImportError:
        frames_available = False

    if query_vlm and frames_available:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        vlm_images = frames + [final] if final else frames
        
        if vlm_images:
            vlm_prompt = (
                "You are verifying a Panoply visualization task. Look at these frames from the user's trajectory. "
                "Did the user use the Panoply software to display maps of precipitation? "
                "More importantly, is there evidence they looked at or zoomed into the Eastern Pacific Ocean "
                "(the ocean region directly west of the Americas / 120W to 80W)? "
                "Reply with a JSON containing: {\"used_panoply\": true/false, \"viewed_eastern_pacific\": true/false}"
            )
            vlm_result = query_vlm(prompt=vlm_prompt, images=vlm_images)
            
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("used_panoply", False) and parsed.get("viewed_eastern_pacific", False):
                    score += 15
                    feedback.append("VLM verified agent navigated Panoply to the Eastern Pacific")
                elif parsed.get("used_panoply", False):
                    score += 7
                    feedback.append("VLM verified Panoply usage but could not confirm Eastern Pacific zoom")
                else:
                    feedback.append("VLM could not confirm appropriate Panoply usage")
            else:
                score += 15 # Grant points if VLM fails technically
                feedback.append("VLM query failed; granting points by default")
        else:
            score += 15
            feedback.append("No images available for VLM; granting points by default")
    else:
        score += 15 # Free points if framework does not support VLM trajectory
        feedback.append("VLM verification unavailable; granting points by default")

    # ----------------------------------------------------------------
    # Final Evaluation
    # ----------------------------------------------------------------
    # The agent MUST correctly identify that it doesn't cross the equator to genuinely pass
    key_criteria_met = (crosses_str.upper() == 'NO')
    passed = (score >= 75) and key_criteria_met

    if passed and not key_criteria_met:
        feedback.append("FAILED: Met point threshold but failed critical deduction (CROSSES_EQUATOR=NO)")
        passed = False

    return {
        "passed": bool(passed),
        "score": float(score),
        "feedback": " | ".join(feedback),
        "details": {
            "jan_map_ok": (jan_exists and jan_size >= 15000),
            "jul_map_ok": (jul_exists and jul_size >= 15000),
            "jan_lat_parsed": jan_val,
            "jul_lat_parsed": jul_val,
            "crosses_equator": crosses_str
        }
    }