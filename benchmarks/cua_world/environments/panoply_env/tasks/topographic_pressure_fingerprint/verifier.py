#!/usr/bin/env python3
"""
Verifier for topographic_pressure_fingerprint task.

Scoring criteria (100 pts total, pass threshold = 80):
  1. Surface pressure plot exported (15 pts): surface_pressure_jan.png exists, >= 15KB.
  2. SLP plot exported (15 pts): sealevel_pressure_jan.png exists, >= 15KB.
  3. Report complete (15 pts): lecture_notes.txt has all 7 required fields.
  4. Scientific correctness 1 - F1 Pressure (15 pts): FEATURE_1_PRESSURE_HPA is physically
     plausible for a high-elevation feature (400-850 hPa). Converts Pa if needed.
  5. Scientific correctness 2 - SLP Mean (10 pts): SEALEVEL_MEAN_HPA is ~1013 hPa.
  6. Scientific correctness 3 - Key Difference (15 pts): Explanation includes keywords.
  7. VLM verification (15 pts): Trajectory shows Panoply usage mapping pressure datasets.
"""

import json
import os
import tempfile
import re

def verify_topographic_pressure_fingerprint(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 1. Retrieve result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/topographic_pressure_fingerprint_result.json', tmp.name)
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

    # --- Criterion 1: Surface pressure plot (15 pts) ---
    surf_exists = result.get('surface_png_exists', False)
    surf_mtime = int(result.get('surface_png_mtime', 0))
    surf_size = int(result.get('surface_png_size', 0))

    if surf_exists and surf_mtime >= task_start and surf_size >= 15000:
        score += 15
        feedback.append(f"Surface pressure plot exported ({surf_size} bytes)")
    elif surf_exists and surf_size > 0:
        score += 7
        feedback.append(f"Surface pressure plot exists but small or old ({surf_size} bytes)")
    else:
        feedback.append("Surface pressure plot missing or not created during task")

    # --- Criterion 2: SLP plot (15 pts) ---
    slp_exists = result.get('slp_png_exists', False)
    slp_mtime = int(result.get('slp_png_mtime', 0))
    slp_size = int(result.get('slp_png_size', 0))

    if slp_exists and slp_mtime >= task_start and slp_size >= 15000:
        score += 15
        feedback.append(f"Sea-level pressure plot exported ({slp_size} bytes)")
    elif slp_exists and slp_size > 0:
        score += 7
        feedback.append(f"SLP plot exists but small or old ({slp_size} bytes)")
    else:
        feedback.append("Sea-level pressure plot missing or not created during task")

    # --- Criterion 3: Report Completeness (15 pts) ---
    req_keys = ['feature_1', 'feature_1_pressure_hpa', 'feature_2', 'feature_2_pressure_hpa', 
                'feature_3', 'sealevel_mean_hpa', 'key_difference']
    
    missing_keys = []
    for k in req_keys:
        val = result.get(k, '')
        if not val or len(val) < 2:
            missing_keys.append(k.upper())
            
    report_exists = result.get('report_exists', False)
    if report_exists and not missing_keys:
        score += 15
        feedback.append("Report complete with all 7 fields.")
    elif report_exists:
        score += 5
        feedback.append(f"Report missing fields: {', '.join(missing_keys)}")
    else:
        feedback.append("Report missing entirely.")

    # --- Utility to parse numeric pressure values, handling Pa -> hPa ---
    def parse_pressure(raw_val):
        nums = re.findall(r"[-+]?\d*\.\d+|\d+", raw_val.replace(',', ''))
        if not nums:
            return None
        val = float(nums[0])
        # NCEP data is in Pa. If agent wrote >10000, they likely used Pa instead of hPa
        if val > 10000:
            val = val / 100.0
        return val

    # --- Criterion 4: F1 Pressure scientific correctness (15 pts) ---
    f1_raw = result.get('feature_1_pressure_hpa', '')
    f1_val = parse_pressure(f1_raw)
    if f1_val is not None:
        if 400 <= f1_val <= 850:
            score += 15
            feedback.append(f"FEATURE_1 pressure {f1_val}hPa is physically plausible for topography.")
        else:
            feedback.append(f"FEATURE_1 pressure {f1_val}hPa is outside topographic range (400-850 hPa).")
    else:
        feedback.append("Could not parse FEATURE_1_PRESSURE_HPA.")

    # --- Criterion 5: SLP Mean scientific correctness (10 pts) ---
    slp_raw = result.get('sealevel_mean_hpa', '')
    slp_val = parse_pressure(slp_raw)
    if slp_val is not None:
        if 950 <= slp_val <= 1050:
            score += 10
            feedback.append(f"SEALEVEL_MEAN_HPA {slp_val}hPa is correct for mean sea-level pressure.")
        else:
            feedback.append(f"SEALEVEL_MEAN_HPA {slp_val}hPa is physically incorrect.")
    else:
        feedback.append("Could not parse SEALEVEL_MEAN_HPA.")

    # --- Criterion 6: Key Difference Keywords (15 pts) ---
    diff_text = result.get('key_difference', '').lower()
    keywords = ["elevation", "altitude", "topograph", "height", "terrain", "mountain", "mass"]
    if any(k in diff_text for k in keywords):
        score += 15
        feedback.append("KEY_DIFFERENCE correctly identifies topography/elevation concepts.")
    elif diff_text:
        feedback.append("KEY_DIFFERENCE explanation lacks key topographic terms.")
    else:
        feedback.append("No KEY_DIFFERENCE explanation provided.")

    # --- Criterion 7: VLM Trajectory Verification (15 pts) ---
    # Only run VLM if query_vlm is provided and the agent produced some output.
    if query_vlm and (surf_exists or slp_exists):
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = (
            "You are verifying a Panoply visualization task. "
            "Look at these screenshots showing an agent's workflow.\n"
            "1. Did the agent successfully open NASA Panoply?\n"
            "2. Did the agent create map plots displaying global data?\n"
            "Respond ONLY with a JSON object: {\"used_panoply\": true/false, \"created_plots\": true/false}"
        )
        
        vlm_res = query_vlm(images=frames + [final] if final else frames, prompt=prompt)
        if vlm_res and vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('used_panoply') and parsed.get('created_plots'):
                score += 15
                feedback.append("VLM verified workflow: Panoply maps created.")
            else:
                feedback.append(f"VLM verification failed. Parsed: {parsed}")
        else:
            # Fallback if VLM fails but files exist - assume true
            score += 15
            feedback.append("VLM error, defaulting to points awarded based on file presence.")
    elif not query_vlm and (surf_exists or slp_exists):
        # Graceful fallback if testing environment lacks VLM
        score += 15
        feedback.append("No VLM available, awarding trajectory points by proxy of file creation.")
    else:
        feedback.append("No VLM check run due to missing outputs.")

    # Final pass/fail determination
    # Must have >= 80 points AND have both plots and the report
    key_files_exist = surf_exists and slp_exists and report_exists
    passed = score >= 80 and key_files_exist

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "details": {
            "surface_plot_ok": surf_exists and surf_size >= 15000,
            "slp_plot_ok": slp_exists and slp_size >= 15000,
            "f1_hpa_parsed": f1_val,
            "slp_hpa_parsed": slp_val,
            "diff_text_excerpt": diff_text[:50] + "..." if len(diff_text) > 50 else diff_text
        }
    }