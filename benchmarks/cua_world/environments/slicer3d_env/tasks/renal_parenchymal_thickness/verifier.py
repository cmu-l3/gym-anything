#!/usr/bin/env python3
"""
Verifier for Renal Parenchymal Thickness Assessment task.

VERIFICATION METRICS:
1. Measurement accuracy - compare agent measurements to ground truth
2. Classification correctness - based on average thickness
3. Bilateral comparison - symmetry assessment
4. Report completeness - all required fields present

Scoring (100 points total):
- Right kidney measurements: 20 points (within 5mm tolerance)
- Left kidney measurements: 20 points (within 5mm tolerance)
- Average calculation: 10 points (mathematically correct)
- Classification accuracy: 20 points (both kidneys correct)
- Bilateral comparison: 10 points (difference and symmetry)
- Markup file created: 10 points
- Report completeness: 10 points

Pass threshold: 60 points with at least one kidney measured accurately
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert to Python native types for JSON serialization."""
    if hasattr(val, 'item'):
        return val.item()
    return val


def parse_float(val):
    """Safely parse a float from string or return None."""
    if val is None or val == "":
        return None
    try:
        return float(val)
    except (ValueError, TypeError):
        return None


def get_expected_classification(avg_mm):
    """Determine expected classification based on average thickness."""
    if avg_mm is None:
        return None
    if avg_mm >= 15:
        return "Normal"
    elif avg_mm >= 10:
        return "Mildly reduced"
    else:
        return "Significantly reduced"


def verify_renal_parenchymal_thickness(traj, env_info, task_info):
    """
    Verify renal parenchymal thickness measurement task completion.
    
    Uses copy_from_env to read exported results from container.
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
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    measurement_tolerance = thresholds.get('measurement_tolerance_mm', 5.0)
    average_tolerance = thresholds.get('average_tolerance_mm', 3.0)
    asymmetry_threshold = thresholds.get('bilateral_asymmetry_threshold_mm', 5.0)
    
    w_right_meas = weights.get('right_kidney_measurements', 20)
    w_left_meas = weights.get('left_kidney_measurements', 20)
    w_average = weights.get('average_calculation', 10)
    w_classification = weights.get('classification_accuracy', 20)
    w_bilateral = weights.get('bilateral_comparison', 10)
    w_markup = weights.get('markup_created', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/renal_task_result.json", temp_result.name)
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
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/renal_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # CRITERION 1: Markup file created (10 points)
    # ============================================================
    markup_valid = result.get('markup_valid', False)
    markup_exists = result.get('markup_exists', False)
    measurement_count = result.get('measurement_count', 0)
    
    if markup_valid:
        score += w_markup
        feedback_parts.append(f"✓ Markup file created with {measurement_count} measurements (+{w_markup})")
    elif markup_exists:
        score += w_markup * 0.5
        feedback_parts.append(f"△ Markup file exists but may predate task (+{w_markup * 0.5:.0f})")
    else:
        feedback_parts.append("✗ No markup file created")
    
    details['markup_created'] = markup_valid
    details['measurement_count'] = measurement_count
    
    # ============================================================
    # CRITERION 2: Report completeness (10 points)
    # ============================================================
    report_valid = result.get('report_valid', False)
    report_complete = result.get('report_complete', False)
    
    if report_valid and report_complete:
        score += w_report
        feedback_parts.append(f"✓ Report complete with all fields (+{w_report})")
    elif report_valid:
        score += w_report * 0.7
        feedback_parts.append(f"△ Report created but incomplete (+{w_report * 0.7:.0f})")
    elif result.get('report_exists', False):
        score += w_report * 0.3
        feedback_parts.append(f"△ Report exists but may predate task (+{w_report * 0.3:.0f})")
    else:
        feedback_parts.append("✗ No report file created")
    
    details['report_complete'] = report_complete
    
    # Get agent's values
    agent_values = result.get('agent_values', {})
    
    # ============================================================
    # CRITERION 3: Right kidney measurements (20 points)
    # ============================================================
    right_score, right_feedback, right_details = verify_kidney_measurements(
        agent_values.get('right_kidney', {}),
        gt_data.get('right_kidney', {}),
        'Right kidney',
        measurement_tolerance,
        w_right_meas
    )
    score += right_score
    feedback_parts.append(right_feedback)
    details['right_kidney'] = right_details
    
    # ============================================================
    # CRITERION 4: Left kidney measurements (20 points)
    # ============================================================
    left_score, left_feedback, left_details = verify_kidney_measurements(
        agent_values.get('left_kidney', {}),
        gt_data.get('left_kidney', {}),
        'Left kidney',
        measurement_tolerance,
        w_left_meas
    )
    score += left_score
    feedback_parts.append(left_feedback)
    details['left_kidney'] = left_details
    
    # ============================================================
    # CRITERION 5: Average calculation (10 points)
    # ============================================================
    avg_score = 0
    avg_feedback_parts = []
    
    for kidney_name, kidney_key in [('Right', 'right_kidney'), ('Left', 'left_kidney')]:
        agent_kidney = agent_values.get(kidney_key, {})
        ant = parse_float(agent_kidney.get('anterior_mm'))
        post = parse_float(agent_kidney.get('posterior_mm'))
        lat = parse_float(agent_kidney.get('lateral_mm'))
        reported_avg = parse_float(agent_kidney.get('average_mm'))
        
        if all(v is not None for v in [ant, post, lat, reported_avg]):
            calculated_avg = (ant + post + lat) / 3
            avg_error = abs(calculated_avg - reported_avg)
            if avg_error < 0.5:
                avg_score += w_average / 2
                avg_feedback_parts.append(f"{kidney_name}: avg correct")
            else:
                avg_feedback_parts.append(f"{kidney_name}: avg error {avg_error:.1f}mm")
        else:
            avg_feedback_parts.append(f"{kidney_name}: incomplete data")
    
    score += avg_score
    if avg_score >= w_average * 0.8:
        feedback_parts.append(f"✓ Average calculations correct (+{avg_score:.0f})")
    elif avg_score > 0:
        feedback_parts.append(f"△ Average calculations: {', '.join(avg_feedback_parts)} (+{avg_score:.0f})")
    else:
        feedback_parts.append(f"✗ Average calculations incorrect")
    
    details['average_calculation_score'] = avg_score
    
    # ============================================================
    # CRITERION 6: Classification accuracy (20 points)
    # ============================================================
    class_score = 0
    class_feedback_parts = []
    
    for kidney_name, kidney_key in [('Right', 'right_kidney'), ('Left', 'left_kidney')]:
        agent_kidney = agent_values.get(kidney_key, {})
        agent_avg = parse_float(agent_kidney.get('average_mm'))
        agent_class = agent_kidney.get('classification', '').strip()
        
        if agent_avg is not None:
            expected_class = get_expected_classification(agent_avg)
            if expected_class and agent_class.lower() == expected_class.lower():
                class_score += w_classification / 2
                class_feedback_parts.append(f"{kidney_name}: {agent_class} ✓")
            elif expected_class:
                class_feedback_parts.append(f"{kidney_name}: {agent_class} (expected {expected_class})")
            else:
                class_feedback_parts.append(f"{kidney_name}: no classification")
        else:
            class_feedback_parts.append(f"{kidney_name}: no average to classify")
    
    score += class_score
    if class_score >= w_classification * 0.8:
        feedback_parts.append(f"✓ Classifications correct (+{class_score:.0f})")
    elif class_score > 0:
        feedback_parts.append(f"△ Classifications: {', '.join(class_feedback_parts)} (+{class_score:.0f})")
    else:
        feedback_parts.append("✗ Classifications incorrect")
    
    details['classification_score'] = class_score
    
    # ============================================================
    # CRITERION 7: Bilateral comparison (10 points)
    # ============================================================
    bilateral_score = 0
    
    right_avg = parse_float(agent_values.get('right_kidney', {}).get('average_mm'))
    left_avg = parse_float(agent_values.get('left_kidney', {}).get('average_mm'))
    agent_diff = parse_float(agent_values.get('bilateral_difference_mm'))
    agent_symmetry = agent_values.get('symmetry_assessment', '').strip()
    
    if right_avg is not None and left_avg is not None:
        expected_diff = abs(right_avg - left_avg)
        expected_symmetry = "Symmetric" if expected_diff <= asymmetry_threshold else "Asymmetric"
        
        # Check difference calculation
        if agent_diff is not None and abs(expected_diff - agent_diff) < 1.0:
            bilateral_score += w_bilateral * 0.5
            feedback_parts.append(f"✓ Bilateral difference correct: {agent_diff:.1f}mm")
        elif agent_diff is not None:
            feedback_parts.append(f"△ Bilateral difference: {agent_diff:.1f}mm (expected {expected_diff:.1f}mm)")
        
        # Check symmetry assessment
        if agent_symmetry.lower() == expected_symmetry.lower():
            bilateral_score += w_bilateral * 0.5
            feedback_parts.append(f"✓ Symmetry assessment correct: {agent_symmetry}")
        elif agent_symmetry:
            feedback_parts.append(f"△ Symmetry: {agent_symmetry} (expected {expected_symmetry})")
    else:
        feedback_parts.append("✗ Cannot verify bilateral comparison - missing averages")
    
    score += bilateral_score
    details['bilateral_score'] = bilateral_score
    
    # ============================================================
    # FINAL RESULT
    # ============================================================
    score = min(100, max(0, score))
    
    # Key criteria: at least one kidney measured somewhat accurately
    key_criteria_met = (
        right_details.get('measurements_accurate', 0) >= 1 or
        left_details.get('measurements_accurate', 0) >= 1
    ) and (markup_valid or report_valid)
    
    passed = score >= 60 and key_criteria_met
    
    # Summary
    feedback_parts.insert(0, f"=== Renal Parenchymal Thickness Assessment ===")
    feedback_parts.append(f"\n=== TOTAL SCORE: {score:.0f}/100 ===")
    feedback_parts.append(f"Pass threshold: 60 points with key criteria")
    feedback_parts.append(f"Key criteria met: {key_criteria_met}")
    feedback_parts.append(f"Result: {'PASS ✓' if passed else 'FAIL ✗'}")
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": "\n".join(feedback_parts),
        "details": to_python_type(details)
    }


def verify_kidney_measurements(agent_kidney, gt_kidney, kidney_name, tolerance_mm, max_points):
    """
    Verify measurements for a single kidney.
    
    Returns:
        tuple: (score, feedback_string, details_dict)
    """
    score = 0
    feedback_parts = []
    details = {
        'measurements_accurate': 0,
        'total_measurements': 0,
        'errors': {}
    }
    
    locations = ['anterior_mm', 'posterior_mm', 'lateral_mm']
    points_per_measurement = max_points / 3
    
    for location in locations:
        agent_val = parse_float(agent_kidney.get(location))
        gt_val = gt_kidney.get(location, 15.0)  # Default if no GT
        
        details['total_measurements'] += 1
        
        if agent_val is not None:
            error = abs(agent_val - gt_val)
            details['errors'][location] = error
            
            if error <= tolerance_mm:
                score += points_per_measurement
                details['measurements_accurate'] += 1
                feedback_parts.append(f"{location.replace('_mm', '')}: {agent_val:.1f}mm ✓")
            else:
                partial = max(0, points_per_measurement * (1 - error / (tolerance_mm * 2)))
                score += partial
                feedback_parts.append(f"{location.replace('_mm', '')}: {agent_val:.1f}mm (GT: {gt_val:.1f}mm, err: {error:.1f}mm)")
        else:
            feedback_parts.append(f"{location.replace('_mm', '')}: missing")
    
    accurate = details['measurements_accurate']
    total = details['total_measurements']
    
    if accurate == total:
        summary = f"✓ {kidney_name}: all {total} measurements within tolerance (+{score:.0f})"
    elif accurate > 0:
        summary = f"△ {kidney_name}: {accurate}/{total} measurements accurate (+{score:.0f})"
    else:
        summary = f"✗ {kidney_name}: no accurate measurements"
    
    details['score'] = score
    return score, summary, details