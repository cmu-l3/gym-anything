#!/usr/bin/env python3
"""
Verifier for antarctic_resupply_storm_risk task.

Occupation: Maritime Meteorologist / Antarctic Logistics Coordinator
Difficulty: hard

Verification Strategy uses MULTIPLE INDEPENDENT SIGNALS:
1. July PNG exists, >20KB, created after start (15 pts)
2. January PNG exists, >20KB, created after start (15 pts)
3. Report has required fields (10 pts)
4. WINTER SLP physically plausible in hPa (15 pts)
5. SUMMER > WINTER physical consistency (15 pts)
6. STORM_RISK valid (10 pts)
7. VLM: Trajectory shows Panoply with South Polar map projection (20 pts)
"""

import json
import os
import tempfile
import re
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot


def verify_antarctic_resupply_storm_risk(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/antarctic_resupply_storm_risk_result.json', tmp.name)
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
    # Criterion 1: July (Winter) PNG exported (15 pts)
    # ----------------------------------------------------------------
    png_july_exists = result.get('png_july_exists', False)
    png_july_mtime = int(result.get('png_july_mtime', 0))
    png_july_size = int(result.get('png_july_size', 0))

    if png_july_exists and png_july_mtime >= task_start and png_july_size >= 20000:
        score += 15
        feedback.append(f"July PNG valid ({png_july_size} bytes)")
    elif png_july_exists and png_july_size > 0:
        score += 7
        feedback.append(f"July PNG exists but invalid mtime/size ({png_july_size} bytes)")
    else:
        feedback.append("July PNG missing")

    # ----------------------------------------------------------------
    # Criterion 2: January (Summer) PNG exported (15 pts)
    # ----------------------------------------------------------------
    png_jan_exists = result.get('png_jan_exists', False)
    png_jan_mtime = int(result.get('png_jan_mtime', 0))
    png_jan_size = int(result.get('png_jan_size', 0))

    if png_jan_exists and png_jan_mtime >= task_start and png_jan_size >= 20000:
        score += 15
        feedback.append(f"January PNG valid ({png_jan_size} bytes)")
    elif png_jan_exists and png_jan_size > 0:
        score += 7
        feedback.append(f"January PNG exists but invalid mtime/size ({png_jan_size} bytes)")
    else:
        feedback.append("January PNG missing")

    # ----------------------------------------------------------------
    # Criterion 3: Report fields (10 pts)
    # ----------------------------------------------------------------
    fields = result.get('fields', {})
    required_keys = ['WINTER_TROUGH_SLP_HPA', 'SUMMER_TROUGH_SLP_HPA', 'STORM_RISK_WINTER', 'STORM_RISK_SUMMER']
    missing_keys = [k for k in required_keys if k not in fields]
    
    if not missing_keys and len(fields) >= 5:
        score += 10
        feedback.append("Report format valid")
    else:
        feedback.append(f"Report missing keys: {missing_keys}")

    # ----------------------------------------------------------------
    # Criterion 4 & 5: Physical Consistency & Units (30 pts)
    # ----------------------------------------------------------------
    winter_slp_str = fields.get('WINTER_TROUGH_SLP_HPA', '')
    summer_slp_str = fields.get('SUMMER_TROUGH_SLP_HPA', '')
    
    def extract_float(s):
        matches = re.findall(r"[-+]?\d*\.\d+|\d+", s)
        return float(matches[0]) if matches else None

    winter_slp = extract_float(winter_slp_str)
    summer_slp = extract_float(summer_slp_str)

    if winter_slp is not None:
        if 960 <= winter_slp <= 1005:  # Valid converted range for Southern Ocean
            score += 15
            feedback.append(f"Winter SLP physically plausible: {winter_slp} hPa")
            
            # Sub-check: Consistency
            if summer_slp is not None and summer_slp > winter_slp:
                score += 15
                feedback.append(f"Physical consistency met: Summer SLP ({summer_slp}) > Winter SLP ({winter_slp})")
            elif summer_slp is not None:
                feedback.append(f"FAIL consistency: Summer SLP ({summer_slp}) not greater than Winter SLP ({winter_slp})")
        elif winter_slp > 90000:
            feedback.append(f"FAIL units: Agent likely reported Pascals instead of hPa ({winter_slp})")
        else:
            feedback.append(f"FAIL physical reality: Winter SLP out of bounds ({winter_slp} hPa)")
    else:
        feedback.append("WINTER_TROUGH_SLP_HPA missing or unparseable")

    # ----------------------------------------------------------------
    # Criterion 6: Storm Risk Classifications (10 pts)
    # ----------------------------------------------------------------
    risk_win = fields.get('STORM_RISK_WINTER', '').upper()
    risk_sum = fields.get('STORM_RISK_SUMMER', '').upper()
    
    if ('EXTREME' in risk_win or 'HIGH' in risk_win) and ('MODERATE' in risk_sum or 'LOW' in risk_sum):
        score += 10
        feedback.append("Risk classification logically follows seasonal SLP shift")
    else:
        feedback.append(f"Risk classification invalid. Win: {risk_win}, Sum: {risk_sum}")

    # ----------------------------------------------------------------
    # Criterion 7: VLM Verification of Trajectory (20 pts)
    # ----------------------------------------------------------------
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        final_img = get_final_screenshot(traj)
        if final_img:
            frames.append(final_img)
            
        vlm_prompt = (
            "You are verifying if a user successfully configured Panoply to view the Antarctic region. "
            "Look at these screenshots. Does ANY of them show a Panoply map plot using a "
            "'South Polar' or 'Antarctic' projection (where the circular continent of Antarctica is near the center)? "
            "Respond in JSON format: {\"used_south_polar\": true/false, \"reason\": \"...\"}"
        )
        
        vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('used_south_polar', False):
                score += 20
                feedback.append("VLM confirmed South Polar projection usage")
            else:
                feedback.append("VLM did NOT detect South Polar projection")
        else:
            feedback.append("VLM query failed or returned invalid format")
    else:
        feedback.append("VLM not available, skipping visual projection check")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }