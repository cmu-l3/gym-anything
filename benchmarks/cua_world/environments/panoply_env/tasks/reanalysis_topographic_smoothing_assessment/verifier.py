#!/usr/bin/env python3
"""
Verifier for reanalysis_topographic_smoothing_assessment task.

Occupation: Agricultural Risk Actuary / Climate Data Methodologist
Difficulty: very_hard

Scoring criteria (100 pts total, pass threshold = 80):
  1. Temperature Plot Exported (25 pts): colombia_temp_annual.png exists,
     was created after task start, size >= 15KB.
  2. Precipitation Plot Exported (25 pts): colombia_precip_annual.png exists,
     was created after task start, size >= 15KB.
  3. Memo Format Complete (15 pts): veto_memo.txt exists and contains all required keys.
  4. Anti-Hallucination Data Read (20 pts): DATASET_MEAN_TEMP_C must be > 23.0°C.
     (Real world is ~18°C, LLMs guessing will output ~18-20°C. The coarse NCEP dataset
     mathematically averages the Andes with lowlands, yielding ~25.5°C. The agent MUST
     report the artifactually high dataset value to prove tool usage).
  5. Domain Reasoning Check (15 pts): MODEL_SUITABILITY = REJECTED, and ERROR_MECHANISM
     contains relevant domain keywords (resolution, average, smooth, topography, etc.).
"""

import json
import os
import tempfile
import re

def verify_topographic_smoothing_assessment(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Fetch result JSON
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env('/tmp/reanalysis_topographic_smoothing_assessment_result.json', tmp.name)
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

    # Get metadata configuration
    metadata = task_info.get('metadata', {})
    anti_hallucination_threshold_c = metadata.get('anti_hallucination_threshold_c', 23.0)
    anti_hallucination_threshold_k = metadata.get('anti_hallucination_threshold_k', 296.0)
    expected_keywords = metadata.get('expected_keywords', ["resolution", "coarse", "smooth", "average", "elevation", "grid", "topography", "scale"])

    # ----------------------------------------------------------------
    # Criterion 1: Temperature Line Plot Exported (25 pts)
    # ----------------------------------------------------------------
    temp_plot_exists = result.get('temp_plot_exists', False)
    temp_plot_mtime = int(result.get('temp_plot_mtime', 0))
    temp_plot_size = int(result.get('temp_plot_size', 0))

    if temp_plot_exists and temp_plot_mtime >= task_start and temp_plot_size >= 15000:
        score += 25
        feedback.append(f"Temperature plot exported ({temp_plot_size} bytes)")
    elif temp_plot_exists and temp_plot_mtime >= task_start and temp_plot_size >= 5000:
        score += 12
        feedback.append(f"Temperature plot present but small ({temp_plot_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Temperature plot missing or not created during task "
                        f"(exists={temp_plot_exists}, size={temp_plot_size})")

    # ----------------------------------------------------------------
    # Criterion 2: Precipitation Line Plot Exported (25 pts)
    # ----------------------------------------------------------------
    precip_plot_exists = result.get('precip_plot_exists', False)
    precip_plot_mtime = int(result.get('precip_plot_mtime', 0))
    precip_plot_size = int(result.get('precip_plot_size', 0))

    if precip_plot_exists and precip_plot_mtime >= task_start and precip_plot_size >= 15000:
        score += 25
        feedback.append(f"Precipitation plot exported ({precip_plot_size} bytes)")
    elif precip_plot_exists and precip_plot_mtime >= task_start and precip_plot_size >= 5000:
        score += 12
        feedback.append(f"Precipitation plot present but small ({precip_plot_size} bytes, expected >=15KB)")
    else:
        feedback.append(f"Precipitation plot missing or not created during task "
                        f"(exists={precip_plot_exists}, size={precip_plot_size})")

    # ----------------------------------------------------------------
    # Criterion 3: Memo Format Complete (15 pts)
    # ----------------------------------------------------------------
    memo_exists = result.get('memo_exists', False)
    memo_mtime = int(result.get('memo_mtime', 0))
    
    val_temp = result.get('dataset_mean_temp_c', '').strip()
    val_suit = result.get('model_suitability', '').strip()
    val_err = result.get('error_mechanism', '').strip()
    val_lat = result.get('analysis_lat', '').strip()
    val_lon = result.get('analysis_lon', '').strip()

    has_all_fields = bool(val_temp) and bool(val_suit) and bool(val_err) and bool(val_lat) and bool(val_lon)

    if memo_exists and memo_mtime >= task_start and has_all_fields:
        score += 15
        feedback.append("Memo formatted correctly with all required fields.")
    elif memo_exists and memo_mtime >= task_start:
        score += 5
        feedback.append(f"Memo exists but is missing fields. Found: Temp='{val_temp}', Suit='{val_suit}', Err length={len(val_err)}")
    else:
        feedback.append(f"Memo missing or not created during task (exists={memo_exists})")

    # ----------------------------------------------------------------
    # Criterion 4: Anti-Hallucination Data Check (20 pts)
    # ----------------------------------------------------------------
    anti_hallucination_passed = False
    try:
        # Strip out any letters (e.g., 'C', 'K', 'deg')
        temp_clean = re.sub(r'[^\d.-]', '', val_temp)
        if temp_clean:
            temp_num = float(temp_clean)
            
            # The agent might have supplied Celsius (expect ~25-26) or Kelvin (expect ~298-299)
            if temp_num > anti_hallucination_threshold_c and temp_num < 45.0:
                anti_hallucination_passed = True
                score += 20
                feedback.append(f"Anti-hallucination check PASSED: reported temp {temp_num:.1f}°C reflects the dataset artifact.")
            elif temp_num > anti_hallucination_threshold_k and temp_num < 320.0:
                anti_hallucination_passed = True
                score += 20
                feedback.append(f"Anti-hallucination check PASSED: reported temp {temp_num:.1f}K reflects the dataset artifact.")
            else:
                feedback.append(f"Anti-hallucination check FAILED: reported temp {temp_num} reflects real-world prior, not the NCEP dataset value (which is >23C due to smoothing).")
        else:
            feedback.append("Anti-hallucination check FAILED: Could not parse temperature value.")
    except ValueError:
        feedback.append(f"Anti-hallucination check FAILED: Invalid temperature format '{val_temp}'")

    # ----------------------------------------------------------------
    # Criterion 5: Domain Reasoning Check (15 pts)
    # ----------------------------------------------------------------
    suitability_correct = val_suit.upper() == 'REJECTED'
    
    error_lower = val_err.lower()
    has_keywords = any(kw in error_lower for kw in expected_keywords)
    
    if suitability_correct and has_keywords:
        score += 15
        feedback.append("Domain reasoning PASSED: Model rejected and mechanism references spatial/topographic smoothing.")
    elif suitability_correct:
        score += 7
        feedback.append("Domain reasoning PARTIAL: Model rejected, but mechanism lacks expected geophysical keywords.")
    else:
        feedback.append(f"Domain reasoning FAILED: Suitability='{val_suit}', keywords found={has_keywords}")

    # Final pass logic
    passed = score >= 80 and anti_hallucination_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback),
        "details": {
            "anti_hallucination_passed": anti_hallucination_passed,
            "parsed_temp": val_temp
        }
    }