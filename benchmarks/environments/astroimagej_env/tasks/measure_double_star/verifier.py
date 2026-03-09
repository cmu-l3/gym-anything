#!/usr/bin/env python3
"""
Verifier for Measure Double Star Parameters task (HST NGC 6652 real data).

Scoring (100 points total):
  Criterion 1: Results file created with measurements (15 pts)
  Criterion 2: Separation measurement within tolerance (25 pts)
  Criterion 3: Position angle within tolerance (25 pts)
  Criterion 4: Magnitude difference within tolerance (20 pts)
  Criterion 5: Evidence of photometric measurement (15 pts)

Pass threshold: 60 points

Ground truth is read from /tmp/double_star_ground_truth.json (written by
setup_task.sh from actual centroid measurements of the real HST data).
No hardcoded expected values are used.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_measure_double_star(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # ------------------------------------------------------------------
    # Copy the task result JSON produced by export_result.sh
    # ------------------------------------------------------------------
    result = {}
    try:
        temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Result file error: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    # ------------------------------------------------------------------
    # Copy the ground truth JSON produced by setup_task.sh
    # ------------------------------------------------------------------
    ground_truth = {}
    try:
        gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/double_star_ground_truth.json", gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read ground truth: {e}")
        # Fall back to metadata if ground truth file is missing
        metadata = task_info.get('metadata', {})
        ground_truth = {
            'separation_arcsec': metadata.get('separation_arcsec', 2.0),
            'position_angle_deg': metadata.get('position_angle_deg', 0.0),
            'magnitude_difference': metadata.get('magnitude_difference', 1.0),
            'separation_pixels': metadata.get('separation_pixels', 20.0),
        }
        feedback.append("WARNING: Using fallback ground truth from metadata")
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    expected_sep = ground_truth.get('separation_arcsec', 2.0)
    expected_pa = ground_truth.get('position_angle_deg', 0.0)
    expected_mag_diff = ground_truth.get('magnitude_difference', 1.0)
    expected_sep_pix = ground_truth.get('separation_pixels', 20.0)

    # ------------------------------------------------------------------
    # Criterion 1: Results file created (15 pts)
    # ------------------------------------------------------------------
    try:
        if result.get('results_file_found'):
            content_len = len(result.get('results_content', ''))
            if content_len > 50:
                score += 15
                feedback.append(f"Results file found ({content_len} chars)")
            else:
                score += 8
                feedback.append("Results file exists but minimal content")
        else:
            feedback.append("No results file found")
    except Exception as e:
        feedback.append(f"Results file check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 2: Separation measurement (25 pts)
    # ------------------------------------------------------------------
    try:
        reported_sep = result.get('reported_separation_arcsec')
        if reported_sep is not None:
            error_arcsec = abs(reported_sep - expected_sep)
            # Check if agent might have reported pixels instead of arcsec
            error_pix_as_arcsec = abs(reported_sep - expected_sep_pix)

            if error_arcsec <= 1.0:
                score += 25
                feedback.append(f"Separation correct: {reported_sep:.2f} arcsec (expected {expected_sep:.2f})")
            elif error_arcsec <= 2.0:
                score += 18
                feedback.append(f"Separation close: {reported_sep:.2f} arcsec (expected {expected_sep:.2f})")
            elif error_arcsec <= 3.0:
                score += 12
                feedback.append(f"Separation approximate: {reported_sep:.2f} arcsec (expected {expected_sep:.2f})")
            elif error_pix_as_arcsec <= 5.0:
                # Agent reported pixel separation, not arcsec
                score += 8
                feedback.append(f"Separation appears to be in pixels ({reported_sep:.1f}), not arcsec")
            else:
                score += 3
                feedback.append(f"Separation reported but inaccurate: {reported_sep:.2f} (expected {expected_sep:.2f})")
        else:
            feedback.append("Separation not reported")
    except Exception as e:
        feedback.append(f"Separation check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 3: Position angle (25 pts)
    # ------------------------------------------------------------------
    try:
        reported_pa = result.get('reported_position_angle_deg')
        if reported_pa is not None:
            # PA wraps at 360, so handle circular distance
            error = abs(reported_pa - expected_pa)
            error = min(error, 360 - error)

            if error <= 15:
                score += 25
                feedback.append(f"PA correct: {reported_pa:.1f} deg (expected {expected_pa:.1f})")
            elif error <= 30:
                score += 15
                feedback.append(f"PA approximate: {reported_pa:.1f} deg (expected {expected_pa:.1f})")
            elif error <= 45:
                score += 8
                feedback.append(f"PA roughly correct: {reported_pa:.1f} deg (expected {expected_pa:.1f})")
            else:
                score += 3
                feedback.append(f"PA reported but wrong: {reported_pa:.1f} deg (expected {expected_pa:.1f})")
        else:
            feedback.append("Position angle not reported")
    except Exception as e:
        feedback.append(f"PA check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 4: Magnitude difference (20 pts)
    # ------------------------------------------------------------------
    try:
        reported_mag = result.get('reported_magnitude_diff')
        if reported_mag is not None:
            error = abs(reported_mag - expected_mag_diff)

            if error <= 0.5:
                score += 20
                feedback.append(f"Mag difference correct: {reported_mag:.2f} (expected {expected_mag_diff:.2f})")
            elif error <= 1.0:
                score += 12
                feedback.append(f"Mag difference approximate: {reported_mag:.2f} (expected {expected_mag_diff:.2f})")
            elif error <= 2.0:
                score += 6
                feedback.append(f"Mag difference rough: {reported_mag:.2f} (expected {expected_mag_diff:.2f})")
            else:
                score += 3
                feedback.append(f"Mag difference reported but inaccurate: {reported_mag:.2f}")
        else:
            feedback.append("Magnitude difference not reported")
    except Exception as e:
        feedback.append(f"Mag diff check error: {e}")

    # ------------------------------------------------------------------
    # Criterion 5: Evidence of photometric measurement (15 pts)
    # ------------------------------------------------------------------
    try:
        if result.get('measurement_files_found'):
            score += 15
            feedback.append("Photometric measurement files found")
        elif result.get('any_output'):
            score += 5
            feedback.append("Some output files found")
        else:
            feedback.append("No measurement evidence found")
    except Exception as e:
        feedback.append(f"Measurement evidence check error: {e}")

    # ------------------------------------------------------------------
    # Final result
    # ------------------------------------------------------------------
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
