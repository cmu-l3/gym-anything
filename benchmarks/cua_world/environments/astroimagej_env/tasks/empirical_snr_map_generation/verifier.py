#!/usr/bin/env python3
"""
Verifier for Empirical SNR Map Generation task.

Scoring Criteria (100 points total):
1. Files Created: FITS map and results text file exist and were created during task (10 pts)
2. Data Type: SNR map is saved as 32-bit float (10 pts)
3. Arithmetic Linearity: R^2 > 0.98 ensures Image Math was performed correctly globally (30 pts)
4. Background Validity: Implicit mu and sigma extracted from regression are reasonable (20 pts)
5. Report Consistency: The agent's reported mu/sigma match the ones implicitly applied (10 pts)
6. Area Measurement: Reported area > 3.0 matches actual measured area in the agent's map (20 pts)

Anti-Gaming features: 
- Global linear regression prevents synthetic spoofing of the FITS file.
- `created_during_task` prevents using cached files.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_empirical_snr_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result data: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if result.get("fits_error"):
        feedback_parts.append(f"FITS Processing Error: {result['fits_error']}")

    # ================================================================
    # CRITERION 1: File Creation (10 pts)
    # ================================================================
    files_ok = False
    if result.get("snr_map_exists") and result.get("snr_results_exists"):
        if result.get("snr_map_created_during_task") and result.get("snr_results_created_during_task"):
            score += 10
            files_ok = True
            feedback_parts.append("✅ Output files created during task")
        else:
            score += 5
            feedback_parts.append("⚠️ Files exist but timestamps suggest they weren't created during this task")
    else:
        feedback_parts.append("❌ Output files missing (need both FITS and TXT)")

    # ================================================================
    # CRITERION 2: Data Type (10 pts)
    # ================================================================
    dtype = result.get("dtype", "")
    if "float32" in dtype or "float64" in dtype:
        score += 10
        feedback_parts.append(f"✅ Correct data type: {dtype}")
    elif result.get("snr_map_exists"):
        feedback_parts.append(f"❌ Incorrect data type: {dtype} (expected 32-bit float)")

    # ================================================================
    # CRITERION 3: Arithmetic Linearity (30 pts)
    # ================================================================
    r_squared = result.get("r_squared", 0.0)
    is_linear = False
    if r_squared > 0.98:
        score += 30
        is_linear = True
        feedback_parts.append(f"✅ Image math linearity verified (R² = {r_squared:.4f})")
    elif r_squared > 0.0:
        score += int(30 * r_squared)
        feedback_parts.append(f"❌ Weak or incorrect linearity (R² = {r_squared:.4f}) - Image Math not performed correctly")
    elif result.get("snr_map_exists"):
        feedback_parts.append("❌ No linear relationship detected between original image and SNR map")

    # ================================================================
    # CRITERION 4: Background Validity (20 pts)
    # ================================================================
    extracted_mu = result.get("extracted_mu")
    extracted_sigma = result.get("extracted_sigma")
    true_mu = result.get("true_corner_mu", 0.0)
    true_sigma = result.get("true_corner_sigma", 0.0)

    if is_linear and extracted_mu is not None and extracted_sigma is not None:
        # A reasonable user-chosen blank sky region should be roughly close to the global corner stats
        # Allowing generous 50% variance because they could select an imperfect sky box.
        # But sigma MUST be strictly positive, and mu must be positive and relatively close.
        mu_ok = true_mu * 0.5 < extracted_mu < true_mu * 1.5 if true_mu > 0 else extracted_mu > 0
        sigma_ok = true_sigma * 0.3 < extracted_sigma < true_sigma * 3.0 if true_sigma > 0 else extracted_sigma > 0

        if mu_ok and sigma_ok:
            score += 20
            feedback_parts.append(f"✅ Applied background stats physically valid (mu ~ {extracted_mu:.1f}, sigma ~ {extracted_sigma:.2f})")
        else:
            score += 10  # Partial credit since they did the math, but maybe picked a bad region
            feedback_parts.append(f"⚠️ Applied background stats suspect (mu ~ {extracted_mu:.1f}, sigma ~ {extracted_sigma:.2f}) vs true corner (mu={true_mu:.1f}, sigma={true_sigma:.2f})")
    else:
        feedback_parts.append("❌ Could not extract valid background statistics from image math")

    # ================================================================
    # CRITERION 5: Report Consistency (10 pts)
    # ================================================================
    rep_mu = result.get("reported_mu")
    rep_sigma = result.get("reported_sigma")

    if rep_mu is not None and rep_sigma is not None and is_linear:
        # Do the reported numbers match the ones *actually applied* via Image Math?
        # Tolerating small rounding differences
        if abs(rep_mu - extracted_mu) < max(1.0, extracted_mu * 0.05) and \
           abs(rep_sigma - extracted_sigma) < max(0.1, extracted_sigma * 0.05):
            score += 10
            feedback_parts.append("✅ Reported mu/sigma match the implicitly applied math")
        else:
            feedback_parts.append(f"❌ Reported stats (mu={rep_mu}, sig={rep_sigma}) do not match the math applied to the image (mu={extracted_mu:.1f}, sig={extracted_sigma:.2f})")
    else:
        feedback_parts.append("❌ Missing reported mu/sigma in text file")

    # ================================================================
    # CRITERION 6: Area Measurement (20 pts)
    # ================================================================
    rep_area = result.get("reported_area")
    actual_area = result.get("actual_area_gt_3", 0)

    if rep_area is not None:
        if actual_area > 0:
            # Tolerating up to 5% discrepancy due to ImageJ boundary thresholding specifics vs numpy array logic
            error_margin = max(50, actual_area * 0.05)
            if abs(rep_area - actual_area) <= error_margin:
                score += 20
                feedback_parts.append(f"✅ Reported area ({rep_area}) matches actual map area > 3.0 ({actual_area})")
            else:
                score += 5
                feedback_parts.append(f"❌ Reported area ({rep_area}) differs significantly from actual map area ({actual_area})")
        else:
            feedback_parts.append("❌ Actual area > 3.0 is zero (threshold math failed)")
    else:
        feedback_parts.append("❌ Missing area measurement in report file")

    # Final Pass Condition
    # Must achieve at least 70% and explicitly pass the Arithmetic Linearity check (to prevent gaming)
    passed = (score >= 70) and is_linear and files_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }