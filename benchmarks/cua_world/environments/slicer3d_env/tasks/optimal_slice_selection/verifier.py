#!/usr/bin/env python3
"""
Verifier for optimal slice selection task.

VERIFICATION CRITERIA:
1. Axial slice selection (15 pts): Within ±2 slices of ground truth optimal
2. Sagittal slice selection (15 pts): Within ±2 slices of ground truth optimal
3. Coronal slice selection (15 pts): Within ±2 slices of ground truth optimal
4. Axial diameter accuracy (10 pts): Within ±5mm of ground truth
5. Sagittal diameter accuracy (10 pts): Within ±5mm of ground truth
6. Coronal diameter accuracy (10 pts): Within ±5mm of ground truth
7. Markup files created (10 pts): Ruler/line markups exist
8. Screenshot quality (10 pts): Multi-panel view captured
9. Report completeness (5 pts): JSON with all required fields

Pass threshold: 60 points with at least 2 of 3 slice selections correct
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def to_python_type(val):
    """Convert numpy types to Python native types for JSON serialization."""
    if isinstance(val, (np.integer, np.int32, np.int64)):
        return int(val)
    elif isinstance(val, (np.floating, np.float32, np.float64)):
        return float(val)
    elif isinstance(val, np.ndarray):
        return val.tolist()
    elif isinstance(val, np.bool_):
        return bool(val)
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


def safe_int(value, default=None):
    """Safely convert a value to int."""
    if value is None or value == "":
        return default
    try:
        return int(float(value))
    except (ValueError, TypeError):
        return default


def verify_optimal_slice_selection(traj, env_info, task_info):
    """
    Verify optimal slice selection task completion.
    
    Scoring (100 points total):
    - Axial slice selection: 15 points (within ±2 slices)
    - Sagittal slice selection: 15 points (within ±2 slices)
    - Coronal slice selection: 15 points (within ±2 slices)
    - Axial diameter accuracy: 10 points (within ±5mm)
    - Sagittal diameter accuracy: 10 points (within ±5mm)
    - Coronal diameter accuracy: 10 points (within ±5mm)
    - Markup files created: 10 points
    - Screenshot quality: 10 points
    - Report completeness: 5 points
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
    
    slice_tolerance = thresholds.get('slice_tolerance', 2)
    diameter_tolerance = thresholds.get('diameter_tolerance_mm', 5.0)
    min_correct_slices = thresholds.get('min_correct_slices', 2)
    
    w_axial_slice = weights.get('axial_slice_selection', 15)
    w_sagittal_slice = weights.get('sagittal_slice_selection', 15)
    w_coronal_slice = weights.get('coronal_slice_selection', 15)
    w_axial_diam = weights.get('axial_diameter_accuracy', 10)
    w_sagittal_diam = weights.get('sagittal_diameter_accuracy', 10)
    w_coronal_diam = weights.get('coronal_diameter_accuracy', 10)
    w_markup = weights.get('markup_files_created', 10)
    w_screenshot = weights.get('screenshot_quality', 10)
    w_report = weights.get('report_completeness', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/optimal_slice_result.json", temp_result.name)
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
        copy_from_env("/tmp/ground_truth_optimal_slices.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load ground truth: {e}"
        }
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
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # Extract ground truth values
    gt_axial = gt_data.get('axial', {})
    gt_sagittal = gt_data.get('sagittal', {})
    gt_coronal = gt_data.get('coronal', {})
    
    gt_axial_slice = gt_axial.get('optimal_slice_index', 0)
    gt_sagittal_slice = gt_sagittal.get('optimal_slice_index', 0)
    gt_coronal_slice = gt_coronal.get('optimal_slice_index', 0)
    
    gt_axial_diam = gt_axial.get('max_diameter_mm', 0)
    gt_sagittal_diam = gt_sagittal.get('max_diameter_mm', 0)
    gt_coronal_diam = gt_coronal.get('max_diameter_mm', 0)
    
    details['ground_truth'] = {
        'axial_slice': gt_axial_slice,
        'axial_diameter_mm': gt_axial_diam,
        'sagittal_slice': gt_sagittal_slice,
        'sagittal_diameter_mm': gt_sagittal_diam,
        'coronal_slice': gt_coronal_slice,
        'coronal_diameter_mm': gt_coronal_diam
    }
    
    # Extract agent values
    agent_values = result.get('agent_values', {})
    
    agent_axial_slice = safe_int(agent_values.get('axial_slice_index'))
    agent_sagittal_slice = safe_int(agent_values.get('sagittal_slice_index'))
    agent_coronal_slice = safe_int(agent_values.get('coronal_slice_index'))
    
    agent_axial_diam = safe_float(agent_values.get('axial_diameter_mm'))
    agent_sagittal_diam = safe_float(agent_values.get('sagittal_diameter_mm'))
    agent_coronal_diam = safe_float(agent_values.get('coronal_diameter_mm'))
    
    details['agent_values'] = {
        'axial_slice': agent_axial_slice,
        'axial_diameter_mm': agent_axial_diam,
        'sagittal_slice': agent_sagittal_slice,
        'sagittal_diameter_mm': agent_sagittal_diam,
        'coronal_slice': agent_coronal_slice,
        'coronal_diameter_mm': agent_coronal_diam
    }
    
    correct_slices = 0
    
    # ============================================================
    # CRITERION 1: Axial slice selection (15 points)
    # ============================================================
    if agent_axial_slice is not None:
        axial_error = abs(agent_axial_slice - gt_axial_slice)
        details['axial_slice_error'] = axial_error
        
        if axial_error <= slice_tolerance:
            score += w_axial_slice
            correct_slices += 1
            feedback_parts.append(f"✓ Axial slice correct (error={axial_error})")
        elif axial_error <= slice_tolerance * 2:
            # Partial credit for being close
            partial = w_axial_slice * 0.5
            score += partial
            feedback_parts.append(f"~ Axial slice close (error={axial_error}, partial credit)")
        else:
            feedback_parts.append(f"✗ Axial slice wrong (agent={agent_axial_slice}, expected={gt_axial_slice}±{slice_tolerance})")
    else:
        feedback_parts.append("✗ Axial slice not reported")
    
    # ============================================================
    # CRITERION 2: Sagittal slice selection (15 points)
    # ============================================================
    if agent_sagittal_slice is not None:
        sagittal_error = abs(agent_sagittal_slice - gt_sagittal_slice)
        details['sagittal_slice_error'] = sagittal_error
        
        if sagittal_error <= slice_tolerance:
            score += w_sagittal_slice
            correct_slices += 1
            feedback_parts.append(f"✓ Sagittal slice correct (error={sagittal_error})")
        elif sagittal_error <= slice_tolerance * 2:
            partial = w_sagittal_slice * 0.5
            score += partial
            feedback_parts.append(f"~ Sagittal slice close (error={sagittal_error}, partial credit)")
        else:
            feedback_parts.append(f"✗ Sagittal slice wrong (agent={agent_sagittal_slice}, expected={gt_sagittal_slice}±{slice_tolerance})")
    else:
        feedback_parts.append("✗ Sagittal slice not reported")
    
    # ============================================================
    # CRITERION 3: Coronal slice selection (15 points)
    # ============================================================
    if agent_coronal_slice is not None:
        coronal_error = abs(agent_coronal_slice - gt_coronal_slice)
        details['coronal_slice_error'] = coronal_error
        
        if coronal_error <= slice_tolerance:
            score += w_coronal_slice
            correct_slices += 1
            feedback_parts.append(f"✓ Coronal slice correct (error={coronal_error})")
        elif coronal_error <= slice_tolerance * 2:
            partial = w_coronal_slice * 0.5
            score += partial
            feedback_parts.append(f"~ Coronal slice close (error={coronal_error}, partial credit)")
        else:
            feedback_parts.append(f"✗ Coronal slice wrong (agent={agent_coronal_slice}, expected={gt_coronal_slice}±{slice_tolerance})")
    else:
        feedback_parts.append("✗ Coronal slice not reported")
    
    details['correct_slices'] = correct_slices
    
    # ============================================================
    # CRITERION 4: Axial diameter accuracy (10 points)
    # ============================================================
    if agent_axial_diam > 0 and gt_axial_diam > 0:
        axial_diam_error = abs(agent_axial_diam - gt_axial_diam)
        details['axial_diameter_error_mm'] = axial_diam_error
        
        if axial_diam_error <= diameter_tolerance:
            score += w_axial_diam
            feedback_parts.append(f"✓ Axial diameter correct ({agent_axial_diam:.1f}mm, error={axial_diam_error:.1f}mm)")
        elif axial_diam_error <= diameter_tolerance * 2:
            partial = w_axial_diam * 0.5
            score += partial
            feedback_parts.append(f"~ Axial diameter close (error={axial_diam_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Axial diameter inaccurate ({agent_axial_diam:.1f}mm vs {gt_axial_diam:.1f}mm)")
    elif agent_axial_diam > 0:
        feedback_parts.append(f"? Axial diameter reported ({agent_axial_diam:.1f}mm) but no GT available")
    else:
        feedback_parts.append("✗ Axial diameter not measured")
    
    # ============================================================
    # CRITERION 5: Sagittal diameter accuracy (10 points)
    # ============================================================
    if agent_sagittal_diam > 0 and gt_sagittal_diam > 0:
        sagittal_diam_error = abs(agent_sagittal_diam - gt_sagittal_diam)
        details['sagittal_diameter_error_mm'] = sagittal_diam_error
        
        if sagittal_diam_error <= diameter_tolerance:
            score += w_sagittal_diam
            feedback_parts.append(f"✓ Sagittal diameter correct ({agent_sagittal_diam:.1f}mm)")
        elif sagittal_diam_error <= diameter_tolerance * 2:
            partial = w_sagittal_diam * 0.5
            score += partial
            feedback_parts.append(f"~ Sagittal diameter close (error={sagittal_diam_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Sagittal diameter inaccurate ({agent_sagittal_diam:.1f}mm vs {gt_sagittal_diam:.1f}mm)")
    else:
        feedback_parts.append("✗ Sagittal diameter not measured")
    
    # ============================================================
    # CRITERION 6: Coronal diameter accuracy (10 points)
    # ============================================================
    if agent_coronal_diam > 0 and gt_coronal_diam > 0:
        coronal_diam_error = abs(agent_coronal_diam - gt_coronal_diam)
        details['coronal_diameter_error_mm'] = coronal_diam_error
        
        if coronal_diam_error <= diameter_tolerance:
            score += w_coronal_diam
            feedback_parts.append(f"✓ Coronal diameter correct ({agent_coronal_diam:.1f}mm)")
        elif coronal_diam_error <= diameter_tolerance * 2:
            partial = w_coronal_diam * 0.5
            score += partial
            feedback_parts.append(f"~ Coronal diameter close (error={coronal_diam_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Coronal diameter inaccurate ({agent_coronal_diam:.1f}mm vs {gt_coronal_diam:.1f}mm)")
    else:
        feedback_parts.append("✗ Coronal diameter not measured")
    
    # ============================================================
    # CRITERION 7: Markup files created (10 points)
    # ============================================================
    measurements_exist = result.get('measurements_exists', False)
    measurement_count = result.get('measurement_count', 0)
    
    if measurements_exist and measurement_count >= 3:
        score += w_markup
        feedback_parts.append(f"✓ Measurement markups created ({measurement_count} measurements)")
    elif measurements_exist and measurement_count > 0:
        partial = w_markup * (measurement_count / 3.0)
        score += partial
        feedback_parts.append(f"~ Partial measurements created ({measurement_count}/3)")
    else:
        feedback_parts.append("✗ No measurement markups found")
    
    # ============================================================
    # CRITERION 8: Screenshot quality (10 points)
    # ============================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    screenshot_created = result.get('screenshot_created_during_task', False)
    
    if screenshot_exists and screenshot_created and screenshot_size > 50000:
        # Good quality screenshot created during task
        score += w_screenshot
        feedback_parts.append(f"✓ Screenshot captured ({screenshot_size//1024}KB)")
    elif screenshot_exists and screenshot_size > 10000:
        # Screenshot exists but may not be created during task
        partial = w_screenshot * 0.5
        score += partial
        feedback_parts.append(f"~ Screenshot exists but may be pre-existing")
    else:
        feedback_parts.append("✗ No valid screenshot found")
    
    # ============================================================
    # CRITERION 9: Report completeness (5 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    # Count how many required fields are present
    required_fields = [
        agent_axial_slice is not None,
        agent_sagittal_slice is not None,
        agent_coronal_slice is not None,
        agent_axial_diam > 0,
        agent_sagittal_diam > 0,
        agent_coronal_diam > 0
    ]
    fields_present = sum(required_fields)
    
    if report_exists and fields_present >= 6:
        score += w_report
        feedback_parts.append("✓ Report complete with all fields")
    elif report_exists and fields_present >= 3:
        partial = w_report * (fields_present / 6.0)
        score += partial
        feedback_parts.append(f"~ Report partially complete ({fields_present}/6 fields)")
    elif fields_present > 0:
        # Values exist but no formal report
        partial = w_report * 0.3
        score += partial
        feedback_parts.append(f"~ Values extracted but no formal report file")
    else:
        feedback_parts.append("✗ No report or values found")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Pass requires: score >= 60 AND at least 2 of 3 slice selections correct
    
    score = int(round(score))
    key_criteria_met = correct_slices >= min_correct_slices
    passed = score >= 60 and key_criteria_met
    
    if not key_criteria_met:
        feedback_parts.append(f"\n⚠ Key criteria not met: only {correct_slices}/{min_correct_slices} slices correctly identified")
    
    # Final feedback
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details,
        "subscores": {
            "correct_slices": correct_slices,
            "slice_tolerance": slice_tolerance,
            "diameter_tolerance_mm": diameter_tolerance,
            "screenshot_created": screenshot_created,
            "measurements_exist": measurements_exist
        }
    })