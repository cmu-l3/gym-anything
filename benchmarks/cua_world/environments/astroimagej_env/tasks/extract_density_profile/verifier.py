#!/usr/bin/env python3
"""
Verifier for extract_density_profile task in AstroImageJ.

Verification logic:
1. Validates that `profile.txt` and `core_report.json` exist and were created during the task.
2. Parses `profile.txt` to extract the Y-values (intensity).
3. Evaluates if the max value in the profile indicates crossing the cluster core.
4. Validates that `core_report.json` accurately reflects the parsed data from `profile.txt`.
5. Uses VLM on the trajectory to visually verify that the Line tool and Plot window were used.
"""

import os
import json
import math
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_profile_text(filepath):
    """Parses ImageJ/AstroImageJ profile output format (usually tab or space separated)."""
    y_vals = []
    with open(filepath, 'r') as f:
        for line in f:
            line = line.replace(',', ' ').strip()
            if not line or line.startswith('#') or line.startswith('X') or line.startswith('Distance'):
                continue
            parts = line.split()
            if len(parts) >= 2:
                try:
                    # The intensity is typically the last column
                    y_vals.append(float(parts[-1]))
                except ValueError:
                    continue
    return y_vals

def verify_extract_density_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_core_intensity = metadata.get('min_core_intensity', 500.0)
    scoring = metadata.get('scoring', {})

    score = 0
    feedback_parts = []
    
    # 1. Load result metadata
    result_meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_meta_file.name)
        with open(result_meta_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(result_meta_file.name):
            os.unlink(result_meta_file.name)

    profile_exists = result.get('profile_exists', False)
    profile_created = result.get('profile_created_during_task', False)
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)

    if not (profile_exists and report_exists):
        feedback_parts.append("Missing required output files (profile.txt or core_report.json)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    elif not (profile_created and report_created):
        feedback_parts.append("Output files exist but were NOT created during this task session")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        score += scoring.get('artifacts_exist', 10)
        feedback_parts.append("Artifacts successfully created")

    # 2. Extract and evaluate the Profile text
    profile_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    y_vals = []
    try:
        copy_from_env("/tmp/agent_profile.txt", profile_file.name)
        y_vals = parse_profile_text(profile_file.name)
    except Exception as e:
        logger.error(f"Error parsing profile: {e}")
    finally:
        if os.path.exists(profile_file.name):
            os.unlink(profile_file.name)

    actual_max = 0.0
    actual_len = len(y_vals)

    if actual_len > 0:
        score += scoring.get('valid_profile', 20)
        actual_max = max(y_vals)
        feedback_parts.append(f"Profile parsed correctly ({actual_len} points)")
        
        # 3. Verify it crossed the core
        if actual_max >= min_core_intensity:
            score += scoring.get('crossed_core', 30)
            feedback_parts.append(f"Profile crossed bright core (max={actual_max:.1f} >= {min_core_intensity})")
        else:
            feedback_parts.append(f"Profile missed core (max={actual_max:.1f} < {min_core_intensity})")
    else:
        feedback_parts.append("Profile parsing failed or contained no valid numeric data")

    # 4. Extract and evaluate the Report JSON
    report_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_core_report.json", report_file.name)
        with open(report_file.name, 'r') as f:
            report_data = json.load(f)
            
        reported_max = float(report_data.get('max_intensity', -1))
        reported_len = int(report_data.get('profile_length', -1))
        
        # Check tolerance to avoid minor rounding mismatches
        max_matches = math.isclose(reported_max, actual_max, rel_tol=1e-3, abs_tol=0.1)
        len_matches = (reported_len == actual_len)
        
        if max_matches and len_matches and actual_len > 0:
            score += scoring.get('accurate_report', 20)
            feedback_parts.append("JSON report perfectly matches profile data")
        else:
            feedback_parts.append(f"JSON data mismatch (Expected: max={actual_max:.2f}, len={actual_len}. Got: max={reported_max}, len={reported_len})")

    except Exception as e:
        feedback_parts.append(f"Error validating JSON report: {e}")
    finally:
        if os.path.exists(report_file.name):
            os.unlink(report_file.name)

    # 5. VLM Visual Verification
    vlm_passed = False
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "Review these screenshots of an AstroImageJ workflow. Answer 'YES' if and only if ALL of the following are true: "
            "1. An astronomical FITS image is open. "
            "2. There is a straight line selection drawn across the brightest central part of the object. "
            "3. A 'Plot' or 'Profile' window is visible showing the 1D intensity graph. "
            "Otherwise, answer 'NO'."
        )
        
        vlm_response = query_vlm(images=frames + [final], prompt=prompt)
        if vlm_response and "YES" in vlm_response.upper():
            vlm_passed = True
            score += scoring.get('vlm_verification', 20)
            feedback_parts.append("VLM visual verification passed")
        else:
            feedback_parts.append("VLM visual verification failed (Line/Plot missing)")
    except Exception as e:
        logger.error(f"VLM verification error: {e}")
        feedback_parts.append("VLM verification skipped/failed due to error")

    # Passed threshold: At least 70 points out of 100 (Requires having a valid report that proves they crossed the core)
    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }