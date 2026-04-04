#!/usr/bin/env python3
"""
Verifier for CCD Image Calibration Pipeline task (Real Palomar LFC Data).

Scoring (100 points total):
  Criterion 1: Master bias created with correct statistics (20 pts)
  Criterion 2: Master dark created (bias-subtracted) (20 pts)
  Criterion 3: Master flat created (normalized) (20 pts)
  Criterion 4: Calibrated science frames exist (25 pts)
  Criterion 5: Calibration actually changed pixel values (15 pts)

Pass threshold: 70 points

Ground truth is loaded from /tmp/calibration_ground_truth.json (computed from real
Palomar LFC data at setup time) rather than relying on hardcoded metadata values.
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)


def verify_calibrate_science_frames(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    score = 0
    feedback = []

    # Copy result JSON from VM
    result = None
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

    # Copy ground truth JSON from VM
    gt = None
    try:
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/calibration_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth from VM: {e}")
        # Fallback: try ground truth embedded in result (export_result.sh puts it there)
        gt = result.get('ground_truth', {})
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    if not gt:
        return {"passed": False, "score": 0,
                "feedback": "Ground truth unavailable - setup may have failed"}

    # Extract ground truth values
    expected_bias_mean = gt.get('bias_mean')
    expected_dark_mean_bias_sub = gt.get('dark_mean_bias_subtracted')
    expected_dark_mean_raw = gt.get('dark_mean_raw')
    expected_flat_norm_mean = gt.get('flat_mean_normalized')
    expected_num_science = gt.get('num_science', 3)
    expected_science_mean_raw = gt.get('science_mean_raw')

    # Criterion 1: Master bias created with correct statistics (20 pts)
    try:
        if result.get('master_bias_found'):
            bias_mean = result.get('master_bias_mean')
            if bias_mean is not None and expected_bias_mean is not None:
                # Allow 10% tolerance on the bias mean (real data can vary)
                tolerance = max(abs(expected_bias_mean) * 0.10, 50)
                diff = abs(bias_mean - expected_bias_mean)
                if diff < tolerance:
                    score += 20
                    feedback.append(
                        f"Master bias correct (mean={bias_mean:.1f}, "
                        f"expected={expected_bias_mean:.1f})")
                elif diff < tolerance * 3:
                    score += 12
                    feedback.append(
                        f"Master bias approximate (mean={bias_mean:.1f}, "
                        f"expected={expected_bias_mean:.1f})")
                else:
                    score += 5
                    feedback.append(
                        f"Master bias exists but wrong mean "
                        f"({bias_mean:.1f} vs expected {expected_bias_mean:.1f})")
            else:
                score += 8
                feedback.append("Master bias found but stats unavailable for comparison")
        else:
            feedback.append("Master bias not found in reduced/")
    except Exception as e:
        feedback.append(f"Master bias check error: {e}")

    # Criterion 2: Master dark created and bias-subtracted (20 pts)
    try:
        if result.get('master_dark_found'):
            dark_mean = result.get('master_dark_mean')
            if dark_mean is not None:
                # Check if bias was subtracted:
                #   bias-subtracted dark mean should be close to dark_mean_bias_subtracted
                #   un-subtracted would be close to dark_mean_raw
                is_bias_sub = False
                if expected_dark_mean_bias_sub is not None and expected_bias_mean is not None:
                    dist_to_sub = abs(dark_mean - expected_dark_mean_bias_sub)
                    dist_to_raw = abs(dark_mean - expected_dark_mean_raw) if expected_dark_mean_raw else float('inf')
                    # If closer to bias-subtracted value than raw value, bias was subtracted
                    if dist_to_sub < dist_to_raw:
                        is_bias_sub = True

                if is_bias_sub:
                    score += 20
                    feedback.append(
                        f"Master dark correct, bias-subtracted "
                        f"(mean={dark_mean:.1f})")
                elif expected_bias_mean is not None and dark_mean < expected_bias_mean * 0.5:
                    # Mean is well below bias level - likely bias-subtracted
                    score += 20
                    feedback.append(
                        f"Master dark appears bias-subtracted "
                        f"(mean={dark_mean:.1f})")
                elif expected_dark_mean_raw is not None:
                    # Not bias-subtracted but dark exists
                    tolerance = max(abs(expected_dark_mean_raw) * 0.15, 50)
                    if abs(dark_mean - expected_dark_mean_raw) < tolerance:
                        score += 12
                        feedback.append(
                            f"Master dark exists but NOT bias-subtracted "
                            f"(mean={dark_mean:.1f})")
                    else:
                        score += 5
                        feedback.append(
                            f"Master dark exists with unusual mean "
                            f"({dark_mean:.1f})")
                else:
                    score += 8
                    feedback.append(
                        f"Master dark found (mean={dark_mean:.1f}), "
                        "no ground truth to compare")
            else:
                score += 8
                feedback.append("Master dark found but stats unavailable")
        else:
            feedback.append("Master dark not found in reduced/")
    except Exception as e:
        feedback.append(f"Master dark check error: {e}")

    # Criterion 3: Master flat created and normalized (20 pts)
    try:
        if result.get('master_flat_found'):
            flat_mean = result.get('master_flat_mean')
            if flat_mean is not None:
                # Normalized flat should have mean near 1.0
                if 0.8 <= flat_mean <= 1.2:
                    score += 20
                    feedback.append(
                        f"Master flat normalized correctly "
                        f"(mean={flat_mean:.4f})")
                elif flat_mean < 100:
                    # Partially processed (bias-subtracted but not normalized by median)
                    score += 12
                    feedback.append(
                        f"Master flat partially processed "
                        f"(mean={flat_mean:.1f})")
                else:
                    # Flat exists but is essentially raw
                    score += 5
                    feedback.append(
                        f"Master flat exists but not normalized "
                        f"(mean={flat_mean:.1f})")
            else:
                score += 8
                feedback.append("Master flat found but stats unavailable")
        else:
            feedback.append("Master flat not found in reduced/")
    except Exception as e:
        feedback.append(f"Master flat check error: {e}")

    # Criterion 4: Calibrated science frames exist (25 pts)
    try:
        cal_count = result.get('calibrated_frames_found', 0)
        if cal_count >= expected_num_science:
            score += 25
            feedback.append(
                f"All {cal_count} calibrated science frames created")
        elif cal_count >= 1:
            partial = int(25 * cal_count / expected_num_science)
            score += partial
            feedback.append(
                f"{cal_count}/{expected_num_science} calibrated frames (partial)")
        else:
            feedback.append("No calibrated science frames found")
    except Exception as e:
        feedback.append(f"Calibrated frames check error: {e}")

    # Criterion 5: Calibration actually changed pixel values (15 pts)
    try:
        raw_mean = result.get('raw_science_mean')
        cal_means = result.get('cal_science_means', [])

        # Use ground truth raw mean if not in result
        if raw_mean is None:
            raw_mean = expected_science_mean_raw

        if raw_mean is not None and cal_means:
            cal_mean = cal_means[0]
            # Calibrated science should differ from raw because bias is removed
            # and flat division changes values. Use a relative threshold.
            diff = abs(cal_mean - raw_mean)
            relative_diff = diff / max(abs(raw_mean), 1.0)

            if relative_diff > 0.05 or diff > 100:
                score += 15
                feedback.append(
                    f"Calibration applied: raw mean={raw_mean:.1f}, "
                    f"cal mean={cal_mean:.1f}")
            elif relative_diff > 0.01 or diff > 20:
                score += 8
                feedback.append(
                    f"Partial calibration: raw={raw_mean:.1f}, "
                    f"cal={cal_mean:.1f}")
            else:
                feedback.append(
                    f"Calibration may not have been applied "
                    f"(raw={raw_mean:.1f}, cal={cal_mean:.1f})")
        elif cal_means:
            score += 5
            feedback.append(
                "Calibrated frames exist but raw comparison unavailable")
        else:
            feedback.append(
                "Cannot verify calibration effect (no calibrated stats)")
    except Exception as e:
        feedback.append(f"Calibration verification error: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
    }
