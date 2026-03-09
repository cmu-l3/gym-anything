#!/usr/bin/env python3
"""
Verifier for Tumor Volume ABC/2 Estimation task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):
1. Three measurements exist (25 points) - 3 ruler/line markups created
2. Measurements in valid range (15 points) - all between 5-80mm
3. Orthogonal orientation (15 points) - A and B approximately perpendicular
4. Volume calculation correct (15 points) - reported volume matches ABC/2 formula
5. Volume estimate accurate (20 points) - within ±35% of ground truth
6. Screenshot with measurements (5 points) - screenshot exists with content
7. Report complete (5 points) - volume_estimate.txt has all required fields

Pass threshold: 60 points with "Three measurements exist" achieved
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_point(point_str):
    """Parse a point string like '1.23,4.56,7.89' into [x, y, z]."""
    if not point_str:
        return None
    try:
        parts = point_str.split(',')
        if len(parts) >= 3:
            return [float(parts[0]), float(parts[1]), float(parts[2])]
    except (ValueError, IndexError):
        pass
    return None


def calculate_direction(p1, p2):
    """Calculate normalized direction vector between two points."""
    if not p1 or not p2:
        return None
    diff = [p2[i] - p1[i] for i in range(3)]
    length = math.sqrt(sum(d*d for d in diff))
    if length < 0.001:
        return None
    return [d / length for d in diff]


def angle_between_vectors(v1, v2):
    """Calculate angle in degrees between two direction vectors."""
    if not v1 or not v2:
        return None
    dot = sum(v1[i] * v2[i] for i in range(3))
    # Clamp to [-1, 1] to avoid numerical issues with acos
    dot = max(-1.0, min(1.0, dot))
    angle_rad = math.acos(abs(dot))  # Use abs for perpendicular check
    return math.degrees(angle_rad)


def verify_estimate_tumor_volume_abc2(traj, env_info, task_info):
    """
    Verify ABC/2 tumor volume estimation task.
    
    Uses multi-criteria scoring with anatomical plausibility checks.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Get task metadata
    metadata = task_info.get('metadata', {})
    diameter_range = metadata.get('diameter_range_mm', {"min": 5, "max": 80})
    volume_tolerance_pct = metadata.get('volume_tolerance_percent', 35)
    orthogonal_tolerance = metadata.get('orthogonal_angle_tolerance_degrees', 20)
    
    weights = metadata.get('scoring_weights', {})
    w_three_meas = weights.get('three_measurements_exist', 25)
    w_valid_range = weights.get('measurements_valid_range', 15)
    w_orthogonal = weights.get('orthogonal_orientation', 15)
    w_calc_correct = weights.get('volume_calculation_correct', 15)
    w_vol_accurate = weights.get('volume_estimate_accurate', 20)
    w_screenshot = weights.get('screenshot_with_measurements', 5)
    w_report = weights.get('report_complete', 5)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/abc2_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export script may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}"
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ============================================================
    # CRITERION 1: Three measurements exist (25 points)
    # ============================================================
    meas_A_exists = result.get('measurement_A_exists', False)
    meas_B_exists = result.get('measurement_B_exists', False)
    meas_C_exists = result.get('measurement_C_exists', False)
    total_meas = result.get('total_measurements', 0)
    new_markups = result.get('new_markups_created', 0)
    
    meas_count = sum([meas_A_exists, meas_B_exists, meas_C_exists])
    
    details['measurement_A_exists'] = meas_A_exists
    details['measurement_B_exists'] = meas_B_exists
    details['measurement_C_exists'] = meas_C_exists
    details['total_measurements'] = total_meas
    
    if meas_count == 3:
        score += w_three_meas
        feedback_parts.append("All 3 measurements created")
    elif meas_count == 2:
        score += int(w_three_meas * 0.6)
        feedback_parts.append(f"Only {meas_count}/3 measurements created")
    elif meas_count == 1 or total_meas >= 1:
        score += int(w_three_meas * 0.3)
        feedback_parts.append(f"Only {max(meas_count, 1)}/3 measurements")
    else:
        feedback_parts.append("No measurements created")
        # Early return if no measurements at all
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 2: Measurements in valid range (15 points)
    # ============================================================
    def safe_float(val):
        try:
            return float(val) if val else None
        except (ValueError, TypeError):
            return None
    
    diam_A = safe_float(result.get('diameter_A_mm'))
    diam_B = safe_float(result.get('diameter_B_mm'))
    diam_C = safe_float(result.get('diameter_C_mm'))
    
    # Also check reported values if markup values missing
    if diam_A is None:
        diam_A = safe_float(result.get('reported_A_mm'))
    if diam_B is None:
        diam_B = safe_float(result.get('reported_B_mm'))
    if diam_C is None:
        diam_C = safe_float(result.get('reported_C_mm'))
    
    details['diameter_A_mm'] = diam_A
    details['diameter_B_mm'] = diam_B
    details['diameter_C_mm'] = diam_C
    
    min_d = diameter_range['min']
    max_d = diameter_range['max']
    
    valid_diams = 0
    diams_feedback = []
    
    for name, diam in [('A', diam_A), ('B', diam_B), ('C', diam_C)]:
        if diam is not None:
            if min_d <= diam <= max_d:
                valid_diams += 1
            else:
                diams_feedback.append(f"{name}={diam:.1f}mm out of range")
        else:
            diams_feedback.append(f"{name} missing")
    
    if valid_diams == 3:
        score += w_valid_range
        feedback_parts.append(f"Measurements valid (A={diam_A:.1f}, B={diam_B:.1f}, C={diam_C:.1f}mm)")
    elif valid_diams >= 2:
        score += int(w_valid_range * 0.6)
        feedback_parts.append(f"{valid_diams}/3 measurements in valid range")
    elif valid_diams >= 1:
        score += int(w_valid_range * 0.3)
        feedback_parts.append(f"Only {valid_diams}/3 valid")
    else:
        feedback_parts.append("No valid measurements")

    # ============================================================
    # CRITERION 3: Orthogonal orientation (15 points)
    # Check if A and B are approximately perpendicular
    # ============================================================
    p_A1 = parse_point(result.get('point_A1', ''))
    p_A2 = parse_point(result.get('point_A2', ''))
    p_B1 = parse_point(result.get('point_B1', ''))
    p_B2 = parse_point(result.get('point_B2', ''))
    
    dir_A = calculate_direction(p_A1, p_A2)
    dir_B = calculate_direction(p_B1, p_B2)
    
    angle_AB = angle_between_vectors(dir_A, dir_B)
    details['angle_AB_degrees'] = angle_AB
    
    if angle_AB is not None:
        # For perpendicular, angle should be close to 90°
        # Using absolute dot product, angle_between_vectors returns angle from 0-90
        deviation_from_90 = abs(90 - angle_AB) if angle_AB <= 90 else angle_AB - 90
        
        if deviation_from_90 <= orthogonal_tolerance:
            score += w_orthogonal
            feedback_parts.append(f"Measurements orthogonal ({angle_AB:.1f}°)")
        elif deviation_from_90 <= orthogonal_tolerance * 2:
            score += int(w_orthogonal * 0.5)
            feedback_parts.append(f"Measurements roughly orthogonal ({angle_AB:.1f}°)")
        else:
            feedback_parts.append(f"Measurements not perpendicular ({angle_AB:.1f}°)")
    else:
        # Give partial credit if we have measurements but can't calculate angle
        if diam_A is not None and diam_B is not None:
            score += int(w_orthogonal * 0.3)
            feedback_parts.append("Could not verify orthogonality")
        else:
            feedback_parts.append("Cannot check orthogonality - missing data")

    # ============================================================
    # CRITERION 4: Volume calculation correct (15 points)
    # ============================================================
    reported_volume = safe_float(result.get('reported_volume_ml'))
    details['reported_volume_ml'] = reported_volume
    
    # Calculate expected volume from measurements
    calculated_volume = None
    if diam_A is not None and diam_B is not None and diam_C is not None:
        # ABC/2 formula: V = (A * B * C) / 2 / 1000 (mm to mL)
        calculated_volume = (diam_A * diam_B * diam_C) / 2 / 1000
        details['calculated_volume_ml'] = round(calculated_volume, 2)
    
    if reported_volume is not None and calculated_volume is not None:
        # Check if reported volume matches calculated (within 5% tolerance)
        calc_tolerance = 0.05
        if calculated_volume > 0:
            diff_pct = abs(reported_volume - calculated_volume) / calculated_volume
            if diff_pct <= calc_tolerance:
                score += w_calc_correct
                feedback_parts.append(f"Volume calculation correct ({reported_volume:.2f} mL)")
            elif diff_pct <= calc_tolerance * 3:
                score += int(w_calc_correct * 0.5)
                feedback_parts.append(f"Volume calculation close ({reported_volume:.2f} vs {calculated_volume:.2f} mL)")
            else:
                feedback_parts.append(f"Volume calculation error ({reported_volume:.2f} vs {calculated_volume:.2f} mL)")
    elif calculated_volume is not None:
        # Give partial credit if we can calculate but no report
        score += int(w_calc_correct * 0.3)
        feedback_parts.append(f"ABC/2 volume would be {calculated_volume:.2f} mL")
    else:
        feedback_parts.append("Cannot verify volume calculation")

    # ============================================================
    # CRITERION 5: Volume estimate accurate (20 points)
    # Compare to ground truth segmentation volume
    # ============================================================
    gt_volume = safe_float(result.get('gt_volume_ml'))
    details['gt_volume_ml'] = gt_volume
    
    # Use reported or calculated volume for comparison
    estimated_volume = reported_volume if reported_volume else calculated_volume
    
    if estimated_volume is not None and gt_volume is not None and gt_volume > 0:
        pct_error = abs(estimated_volume - gt_volume) / gt_volume * 100
        details['volume_error_percent'] = round(pct_error, 1)
        
        if pct_error <= volume_tolerance_pct:
            score += w_vol_accurate
            feedback_parts.append(f"Volume estimate accurate ({pct_error:.1f}% error)")
        elif pct_error <= volume_tolerance_pct * 1.5:
            score += int(w_vol_accurate * 0.5)
            feedback_parts.append(f"Volume estimate roughly accurate ({pct_error:.1f}% error)")
        else:
            feedback_parts.append(f"Volume estimate inaccurate ({pct_error:.1f}% error)")
    else:
        feedback_parts.append("Cannot compare to ground truth")

    # ============================================================
    # CRITERION 6: Screenshot with measurements (5 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_kb', 0)
    
    if screenshot_exists and screenshot_size > 50:
        score += w_screenshot
        feedback_parts.append("Screenshot captured")
    elif screenshot_exists:
        score += int(w_screenshot * 0.5)
        feedback_parts.append("Screenshot exists (small)")
    else:
        feedback_parts.append("No screenshot")

    # ============================================================
    # CRITERION 7: Report complete (5 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    has_all_fields = all([
        result.get('reported_A_mm'),
        result.get('reported_B_mm'),
        result.get('reported_C_mm'),
        result.get('reported_volume_ml')
    ])
    
    if report_exists and has_all_fields:
        score += w_report
        feedback_parts.append("Report complete")
    elif report_exists:
        score += int(w_report * 0.5)
        feedback_parts.append("Report partial")
    else:
        feedback_parts.append("No report file")

    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Key criteria: at least some measurements exist
    key_criteria_met = meas_count >= 1 or total_meas >= 1
    passed = score >= 60 and key_criteria_met

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }