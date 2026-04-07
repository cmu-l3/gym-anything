#!/usr/bin/env python3
"""
Verifier for northwest_passage_thaw_assessment task.

Scoring criteria (100 pts total, pass threshold = 75):
  1. July Polar Plot Exported (20 pts): arctic_temp_july.png exists, >= 20KB, created during task.
  2. August Polar Plot Exported (20 pts): arctic_temp_august.png exists, >= 20KB, created during task.
  3. Report Exists & Complete (10 pts): nwp_assessment.txt exists and has all fields.
  4. Projection Verified (15 pts): PROJECTION_USED contains 'polar' or 'stereographic' or 'orthographic'.
  5. Temperature Accuracy / Unit Conversion (20 pts): Both JULY_TEMP_C and AUGUST_TEMP_C must be between -2.0 and 15.0.
  6. VLM Trajectory Verification (15 pts): Screenshots show Panoply displaying a polar/circular map projection.
"""

import json
import os
import tempfile

def verify_northwest_passage_thaw_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/northwest_passage_thaw_assessment_result.json', tmp.name)
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

    # Criterion 1: July Plot (20 pts)
    july_exists = result.get('png_july_exists', False)
    july_size = result.get('png_july_size', 0)
    july_mtime = result.get('png_july_mtime', 0)

    if july_exists and july_size >= 15000 and july_mtime >= task_start:
        score += 20
        feedback.append("✅ July temperature map exported correctly.")
    elif july_exists:
        score += 10
        feedback.append(f"⚠️ July map present but issues detected (size: {july_size}B, mtime: {july_mtime}).")
    else:
        feedback.append("❌ July temperature map is missing.")

    # Criterion 2: August Plot (20 pts)
    aug_exists = result.get('png_august_exists', False)
    aug_size = result.get('png_august_size', 0)
    aug_mtime = result.get('png_august_mtime', 0)

    if aug_exists and aug_size >= 15000 and aug_mtime >= task_start:
        score += 20
        feedback.append("✅ August temperature map exported correctly.")
    elif aug_exists:
        score += 10
        feedback.append(f"⚠️ August map present but issues detected (size: {aug_size}B, mtime: {aug_mtime}).")
    else:
        feedback.append("❌ August temperature map is missing.")

    # Criterion 3: Report Completeness (10 pts)
    report_exists = result.get('report_exists', False)
    proj_used = result.get('projection_used', '').strip().lower()
    july_c_str = result.get('july_temp_c', '').strip()
    aug_c_str = result.get('august_temp_c', '').strip()
    
    if report_exists and proj_used and july_c_str and aug_c_str:
        score += 10
        feedback.append("✅ Assessment report contains all required fields.")
    elif report_exists:
        score += 5
        feedback.append("⚠️ Assessment report is missing some required fields.")
    else:
        feedback.append("❌ Assessment report is missing.")

    # Criterion 4: Projection Check (15 pts)
    if 'polar' in proj_used or 'stereographic' in proj_used or 'orthographic' in proj_used:
        score += 15
        feedback.append(f"✅ Correct map projection identified: '{result.get('projection_used', '')}'.")
    elif proj_used:
        feedback.append(f"❌ Incorrect map projection identified: '{result.get('projection_used', '')}'.")
    else:
        feedback.append("❌ Map projection not specified in report.")

    # Criterion 5: Temperature Conversion Check (20 pts)
    conversion_passed = False
    try:
        # Strip non-numeric chars if they added "C"
        july_val = float(''.join(c for c in july_c_str if c.isdigit() or c in '.-'))
        aug_val = float(''.join(c for c in aug_c_str if c.isdigit() or c in '.-'))
        
        if -2.0 <= july_val <= 15.0 and -2.0 <= aug_val <= 15.0:
            score += 20
            conversion_passed = True
            feedback.append(f"✅ Temperature conversion correct (July: {july_val}°C, August: {aug_val}°C).")
        elif july_val > 200 or aug_val > 200:
            feedback.append(f"❌ Temperatures reported in Kelvin ({july_val}, {aug_val}). Failed to convert to Celsius.")
        else:
            feedback.append(f"❌ Temperatures out of bounds for the Canadian Arctic summer ({july_val}°C, {aug_val}°C).")
    except ValueError:
        if report_exists:
            feedback.append(f"❌ Could not parse reported temperatures (July: '{july_c_str}', Aug: '{aug_c_str}').")

    # Criterion 6: VLM Verification (15 pts)
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            images = frames + [final_frame] if final_frame else frames
            
            prompt = (
                "You are evaluating a user performing a task in NASA Panoply. "
                "Did the user successfully change the map projection to a North Polar projection? "
                "Look for a map that appears circular and is viewed from directly above the North Pole, "
                "rather than the default flat, rectangular Equirectangular projection. "
                "Respond in JSON format with a single boolean field 'polar_projection_visible'."
            )
            vlm_response = query_vlm(images=images, prompt=prompt)
            
            if vlm_response and vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('polar_projection_visible', False):
                    score += 15
                    vlm_passed = True
                    feedback.append("✅ VLM confirmed polar map projection in trajectory.")
                else:
                    feedback.append("❌ VLM could not find a polar map projection in the trajectory.")
            else:
                feedback.append("⚠️ VLM evaluation failed or returned invalid response.")
        except Exception as e:
            feedback.append(f"⚠️ VLM trajectory evaluation encountered an error: {e}")
    else:
        feedback.append("⚠️ VLM not available for trajectory verification.")

    key_criteria_met = (july_exists or aug_exists) and conversion_passed
    passed = (score >= 75) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "july_exists": july_exists,
            "aug_exists": aug_exists,
            "conversion_passed": conversion_passed,
            "vlm_passed": vlm_passed
        }
    }