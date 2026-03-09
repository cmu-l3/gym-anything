#!/usr/bin/env python3
"""
Verifier for WHO Bidimensional Tumor Measurement task.

VERIFICATION CRITERIA:
1. D1 (longest diameter) accuracy - within 5mm of ground truth (20 points)
2. D2 (perpendicular diameter) accuracy - within 5mm of ground truth (20 points)
3. Perpendicularity - angle between lines is 90° ± 10° (20 points)
4. Slice selection - measurements from optimal slice ± 3 slices (10 points)
5. Product calculation - D1 × D2 correctly calculated (15 points)
6. Markups saved - two ruler markups exist (10 points)
7. Report complete - JSON with all required fields (5 points)

Pass threshold: 60 points with both diameter accuracies achieved
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
    """Convert numpy-like types to Python native types for JSON serialization."""
    if hasattr(val, 'item'):
        return val.item()
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def safe_float(value, default=0.0):
    """Safely convert a value to float."""
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def verify_who_bidimensional_measurement(traj, env_info, task_info):
    """
    Verify WHO bidimensional tumor measurement task completion.
    
    Scoring (100 points total):
    - D1 accuracy: 20 points (within 5mm)
    - D2 accuracy: 20 points (within 5mm)
    - Perpendicularity: 20 points (90° ± 10°)
    - Slice selection: 10 points (within ±3 slices)
    - Product calculation: 15 points (D1 × D2 correct)
    - Markups saved: 10 points (2 ruler markups)
    - Report complete: 5 points (all fields present)
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
    
    diameter_error_max = thresholds.get('diameter_error_max_mm', 5.0)
    perp_tolerance = thresholds.get('perpendicularity_tolerance_deg', 10.0)
    
    w_d1 = weights.get('d1_accuracy', 20)
    w_d2 = weights.get('d2_accuracy', 20)
    w_perp = weights.get('perpendicularity', 20)
    w_slice = weights.get('slice_selection', 10)
    w_product = weights.get('product_correct', 15)
    w_markups = weights.get('markups_saved', 10)
    w_report = weights.get('report_complete', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
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
    
    # Copy ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/who_ground_truth.json", temp_gt.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }
    
    # Extract ground truth values
    gt_d1 = safe_float(gt_data.get('longest_diameter_mm', 0))
    gt_d2 = safe_float(gt_data.get('perpendicular_diameter_mm', 0))
    gt_product = safe_float(gt_data.get('bidimensional_product_mm2', 0))
    gt_slice = int(gt_data.get('measurement_slice', 0))
    slice_range = gt_data.get('slice_range_acceptable', [gt_slice - 3, gt_slice + 3])
    
    details['gt_d1_mm'] = gt_d1
    details['gt_d2_mm'] = gt_d2
    details['gt_product_mm2'] = gt_product
    details['gt_slice'] = gt_slice
    details['acceptable_slice_range'] = slice_range
    
    # Extract agent's values
    agent_d1 = safe_float(result.get('agent_d1_mm', 0))
    agent_d2 = safe_float(result.get('agent_d2_mm', 0))
    agent_product = safe_float(result.get('agent_product_mm2', 0))
    agent_slice = int(safe_float(result.get('agent_slice', 0)))
    angle_deviation = safe_float(result.get('angle_deviation_degrees', 90))
    ruler_count = int(result.get('ruler_count', 0))
    
    details['agent_d1_mm'] = agent_d1
    details['agent_d2_mm'] = agent_d2
    details['agent_product_mm2'] = agent_product
    details['agent_slice'] = agent_slice
    details['angle_deviation_deg'] = angle_deviation
    details['ruler_count'] = ruler_count
    
    # ================================================================
    # CRITERION 1: Markups saved (10 points)
    # ================================================================
    measurements_exist = result.get('measurements_file_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if measurements_exist and ruler_count >= 2:
        score += w_markups
        feedback_parts.append(f"✓ Two ruler markups saved (+{w_markups})")
    elif measurements_exist and ruler_count == 1:
        partial = w_markups // 2
        score += partial
        feedback_parts.append(f"⚠ Only 1 ruler markup found (need 2) (+{partial})")
    elif measurements_exist:
        partial = w_markups // 4
        score += partial
        feedback_parts.append(f"⚠ Measurement file exists but no rulers found (+{partial})")
    else:
        feedback_parts.append("✗ No measurement markups saved")
    
    # ================================================================
    # CRITERION 2: Report completeness (5 points)
    # ================================================================
    report_exists = result.get('report_file_exists', False)
    has_d1 = agent_d1 > 0
    has_d2 = agent_d2 > 0
    has_product = agent_product > 0
    
    if report_exists and has_d1 and has_d2 and has_product:
        score += w_report
        feedback_parts.append(f"✓ Report complete with all fields (+{w_report})")
    elif report_exists:
        partial = w_report // 2
        score += partial
        feedback_parts.append(f"⚠ Report exists but missing some fields (+{partial})")
    else:
        feedback_parts.append("✗ No report file saved")
    
    # ================================================================
    # CRITERION 3: D1 accuracy (20 points)
    # ================================================================
    d1_error = abs(agent_d1 - gt_d1) if gt_d1 > 0 else float('inf')
    details['d1_error_mm'] = d1_error
    
    d1_accurate = False
    if agent_d1 > 0 and gt_d1 > 0:
        if d1_error <= diameter_error_max:
            score += w_d1
            d1_accurate = True
            feedback_parts.append(f"✓ D1 accurate: {agent_d1:.1f}mm vs GT {gt_d1:.1f}mm (error: {d1_error:.1f}mm) (+{w_d1})")
        elif d1_error <= diameter_error_max * 2:
            partial = w_d1 // 2
            score += partial
            feedback_parts.append(f"⚠ D1 partially accurate: {agent_d1:.1f}mm vs GT {gt_d1:.1f}mm (error: {d1_error:.1f}mm) (+{partial})")
        else:
            feedback_parts.append(f"✗ D1 inaccurate: {agent_d1:.1f}mm vs GT {gt_d1:.1f}mm (error: {d1_error:.1f}mm > {diameter_error_max}mm)")
    else:
        feedback_parts.append(f"✗ D1 not measured (agent: {agent_d1}, GT: {gt_d1})")
    
    # ================================================================
    # CRITERION 4: D2 accuracy (20 points)
    # ================================================================
    d2_error = abs(agent_d2 - gt_d2) if gt_d2 > 0 else float('inf')
    details['d2_error_mm'] = d2_error
    
    d2_accurate = False
    if agent_d2 > 0 and gt_d2 > 0:
        if d2_error <= diameter_error_max:
            score += w_d2
            d2_accurate = True
            feedback_parts.append(f"✓ D2 accurate: {agent_d2:.1f}mm vs GT {gt_d2:.1f}mm (error: {d2_error:.1f}mm) (+{w_d2})")
        elif d2_error <= diameter_error_max * 2:
            partial = w_d2 // 2
            score += partial
            feedback_parts.append(f"⚠ D2 partially accurate: {agent_d2:.1f}mm vs GT {gt_d2:.1f}mm (error: {d2_error:.1f}mm) (+{partial})")
        else:
            feedback_parts.append(f"✗ D2 inaccurate: {agent_d2:.1f}mm vs GT {gt_d2:.1f}mm (error: {d2_error:.1f}mm > {diameter_error_max}mm)")
    else:
        feedback_parts.append(f"✗ D2 not measured (agent: {agent_d2}, GT: {gt_d2})")
    
    # ================================================================
    # CRITERION 5: Perpendicularity (20 points)
    # ================================================================
    perpendicular = False
    if ruler_count >= 2:
        if angle_deviation <= perp_tolerance:
            score += w_perp
            perpendicular = True
            actual_angle = 90 - angle_deviation if angle_deviation < 45 else 90 + angle_deviation
            feedback_parts.append(f"✓ Measurements perpendicular: ~{actual_angle:.0f}° (+{w_perp})")
        elif angle_deviation <= perp_tolerance * 2:
            partial = w_perp // 2
            score += partial
            feedback_parts.append(f"⚠ Measurements nearly perpendicular: {angle_deviation:.1f}° from 90° (+{partial})")
        else:
            feedback_parts.append(f"✗ Measurements not perpendicular: {angle_deviation:.1f}° from 90°")
    else:
        feedback_parts.append("✗ Cannot check perpendicularity (need 2 rulers)")
    
    # ================================================================
    # CRITERION 6: Slice selection (10 points)
    # ================================================================
    if agent_slice > 0:
        if slice_range[0] <= agent_slice <= slice_range[1]:
            score += w_slice
            feedback_parts.append(f"✓ Slice selection appropriate: {agent_slice} in range {slice_range} (+{w_slice})")
        elif abs(agent_slice - gt_slice) <= 5:
            partial = w_slice // 2
            score += partial
            feedback_parts.append(f"⚠ Slice selection close: {agent_slice} (optimal: {gt_slice}) (+{partial})")
        else:
            feedback_parts.append(f"✗ Suboptimal slice: {agent_slice} (optimal range: {slice_range})")
    else:
        feedback_parts.append("✗ Slice number not reported")
    
    # ================================================================
    # CRITERION 7: Product calculation (15 points)
    # ================================================================
    if agent_d1 > 0 and agent_d2 > 0:
        expected_product = agent_d1 * agent_d2
        product_error = abs(agent_product - expected_product)
        
        if product_error <= 20:  # Allow small rounding errors
            score += w_product
            feedback_parts.append(f"✓ Product correctly calculated: {agent_product:.1f}mm² (+{w_product})")
        elif agent_product > 0:
            # Check if they at least tried to calculate
            partial = w_product // 2
            score += partial
            feedback_parts.append(f"⚠ Product calculation has error: {agent_product:.1f} vs expected {expected_product:.1f} (+{partial})")
        else:
            feedback_parts.append(f"✗ Product not calculated (expected: {expected_product:.1f}mm²)")
    else:
        feedback_parts.append("✗ Cannot verify product (missing D1 or D2)")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: both diameters must be accurate
    key_criteria_met = d1_accurate and d2_accurate
    passed = score >= 60 and key_criteria_met
    
    # Summary
    feedback_parts.append("")
    feedback_parts.append(f"Total Score: {score}/100")
    feedback_parts.append(f"Key Criteria (D1 + D2 accurate): {'Met' if key_criteria_met else 'Not Met'}")
    feedback_parts.append(f"Pass Threshold: 60 points with both diameter accuracies")
    feedback_parts.append(f"Result: {'PASS' if passed else 'FAIL'}")
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": "\n".join(feedback_parts),
        "details": to_python_type(details)
    }