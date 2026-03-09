#!/usr/bin/env python3
"""
Verifier for tracheal shape index assessment task.

VERIFICATION METRICS:
1. AP Diameter Accuracy (25 points) - within 3mm of ground truth
2. Transverse Diameter Accuracy (25 points) - within 3mm of ground truth  
3. Correct Measurement Level (15 points) - at aortic arch level (within 2 slices)
4. Tracheal Index Correct (15 points) - correctly calculated from diameters
5. Classification Correct (10 points) - Normal/Saber-sheath/AP narrowing
6. Report Completeness (10 points) - JSON with all required fields

Pass threshold: 60 points AND at least one diameter accurate (within 3mm)
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
    """Convert numpy types to Python native types for JSON serialization."""
    try:
        import numpy as np
        if isinstance(val, (np.integer, np.int32, np.int64)):
            return int(val)
        elif isinstance(val, (np.floating, np.float32, np.float64)):
            return float(val)
        elif isinstance(val, np.ndarray):
            return val.tolist()
        elif isinstance(val, np.bool_):
            return bool(val)
    except ImportError:
        pass
    
    if isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def verify_tracheal_shape_index(traj, env_info, task_info):
    """
    Verify tracheal shape index assessment task completion.
    
    Scoring (100 points total):
    - AP Diameter Accuracy: 25 points (within 3mm)
    - Transverse Diameter Accuracy: 25 points (within 3mm)
    - Correct Measurement Level: 15 points (within 2 slices of aortic arch)
    - Tracheal Index Correct: 15 points (correctly calculated)
    - Classification Correct: 10 points
    - Report Completeness: 10 points
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
    
    diameter_tol = thresholds.get('diameter_tolerance_mm', 3.0)
    slice_tol = thresholds.get('slice_tolerance', 2)
    ti_tol = thresholds.get('ti_tolerance', 0.1)
    
    w_ap = weights.get('ap_diameter_accuracy', 25)
    w_trans = weights.get('transverse_diameter_accuracy', 25)
    w_level = weights.get('measurement_level', 15)
    w_ti = weights.get('tracheal_index_correct', 15)
    w_class = weights.get('classification_correct', 10)
    w_report = weights.get('report_completeness', 10)
    
    feedback_parts = []
    score = 0.0
    details = {}
    
    # ================================================================
    # LOAD TASK RESULT
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/trachea_task_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("WARNING: Slicer was not running at export time")
    
    # Check if report exists
    report_exists = result.get('report_exists', False)
    if not report_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No trachea report file found. Agent must create ~/Documents/SlicerData/LIDC/trachea_report.json"
        }
    
    # Check anti-gaming: was report created during task?
    report_after_start = result.get('report_modified_after_start', False)
    if not report_after_start:
        feedback_parts.append("WARNING: Report file may predate task start (anti-gaming check)")
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/trachea_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use defaults if ground truth not available
        gt_data = {
            "ap_diameter_mm": 18.0,
            "transverse_diameter_mm": 16.0,
            "tracheal_index": 0.89,
            "classification": "Normal",
            "aortic_arch_slice": 50
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_ap = float(gt_data.get('ap_diameter_mm', 18.0))
    gt_trans = float(gt_data.get('transverse_diameter_mm', 16.0))
    gt_ti = float(gt_data.get('tracheal_index', 0.89))
    gt_class = str(gt_data.get('classification', 'Normal')).lower().strip()
    gt_slice = int(gt_data.get('aortic_arch_slice', 50))
    
    details['ground_truth'] = {
        'ap_diameter_mm': gt_ap,
        'transverse_diameter_mm': gt_trans,
        'tracheal_index': gt_ti,
        'classification': gt_class,
        'aortic_arch_slice': gt_slice
    }
    
    # ================================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ================================================================
    agent_ap = float(result.get('ap_diameter_mm', 0))
    agent_trans = float(result.get('transverse_diameter_mm', 0))
    agent_ti = float(result.get('tracheal_index', 0))
    agent_class = str(result.get('classification', '')).lower().strip()
    agent_slice = int(result.get('slice_number', 0))
    
    details['agent_measurements'] = {
        'ap_diameter_mm': agent_ap,
        'transverse_diameter_mm': agent_trans,
        'tracheal_index': agent_ti,
        'classification': agent_class,
        'slice_number': agent_slice
    }
    
    # ================================================================
    # CRITERION 1: AP Diameter Accuracy (25 points)
    # ================================================================
    ap_error = abs(agent_ap - gt_ap)
    details['ap_error_mm'] = ap_error
    
    if agent_ap > 0:
        if ap_error <= diameter_tol:
            score += w_ap
            feedback_parts.append(f"✓ AP diameter accurate: {agent_ap:.1f}mm (GT: {gt_ap:.1f}mm, error: {ap_error:.1f}mm)")
        else:
            # Partial credit for being close
            partial = max(0, w_ap * (1 - (ap_error - diameter_tol) / (diameter_tol * 2)))
            score += partial
            feedback_parts.append(f"✗ AP diameter error: {agent_ap:.1f}mm vs GT {gt_ap:.1f}mm (error: {ap_error:.1f}mm > {diameter_tol}mm)")
    else:
        feedback_parts.append("✗ AP diameter not measured or reported as 0")
    
    # ================================================================
    # CRITERION 2: Transverse Diameter Accuracy (25 points)
    # ================================================================
    trans_error = abs(agent_trans - gt_trans)
    details['trans_error_mm'] = trans_error
    
    if agent_trans > 0:
        if trans_error <= diameter_tol:
            score += w_trans
            feedback_parts.append(f"✓ Transverse diameter accurate: {agent_trans:.1f}mm (GT: {gt_trans:.1f}mm, error: {trans_error:.1f}mm)")
        else:
            partial = max(0, w_trans * (1 - (trans_error - diameter_tol) / (diameter_tol * 2)))
            score += partial
            feedback_parts.append(f"✗ Transverse diameter error: {agent_trans:.1f}mm vs GT {gt_trans:.1f}mm (error: {trans_error:.1f}mm > {diameter_tol}mm)")
    else:
        feedback_parts.append("✗ Transverse diameter not measured or reported as 0")
    
    # ================================================================
    # CRITERION 3: Correct Measurement Level (15 points)
    # ================================================================
    slice_error = abs(agent_slice - gt_slice)
    details['slice_error'] = slice_error
    
    if agent_slice > 0:
        if slice_error <= slice_tol:
            score += w_level
            feedback_parts.append(f"✓ Correct measurement level: slice {agent_slice} (GT: {gt_slice})")
        elif slice_error <= slice_tol * 2:
            score += w_level * 0.5
            feedback_parts.append(f"~ Measurement level close: slice {agent_slice} (GT: {gt_slice}, {slice_error} slices off)")
        else:
            feedback_parts.append(f"✗ Wrong measurement level: slice {agent_slice} (GT: {gt_slice}, {slice_error} slices off)")
    else:
        feedback_parts.append("✗ Measurement slice not reported")
    
    # ================================================================
    # CRITERION 4: Tracheal Index Correct (15 points)
    # ================================================================
    if agent_ap > 0 and agent_trans > 0:
        expected_ti = agent_trans / agent_ap
        ti_calc_error = abs(agent_ti - expected_ti)
        ti_gt_error = abs(agent_ti - gt_ti)
        
        details['expected_ti_from_diameters'] = expected_ti
        details['ti_calculation_error'] = ti_calc_error
        details['ti_gt_error'] = ti_gt_error
        
        if ti_calc_error < 0.02:  # Correctly calculated from their own diameters
            if ti_gt_error <= ti_tol:
                score += w_ti
                feedback_parts.append(f"✓ Tracheal Index correct: {agent_ti:.3f} (GT: {gt_ti:.3f})")
            else:
                score += w_ti * 0.7  # Calculation correct but value off due to diameter errors
                feedback_parts.append(f"~ TI calculated correctly ({agent_ti:.3f}) but differs from GT ({gt_ti:.3f})")
        else:
            if ti_gt_error <= ti_tol:
                score += w_ti * 0.5  # Value happens to be close but calculation was wrong
                feedback_parts.append(f"~ TI value close to GT but calculation inconsistent (reported {agent_ti:.3f}, diameters give {expected_ti:.3f})")
            else:
                feedback_parts.append(f"✗ TI calculation error: reported {agent_ti:.3f}, but diameters give {expected_ti:.3f}")
    elif agent_ti > 0:
        ti_gt_error = abs(agent_ti - gt_ti)
        if ti_gt_error <= ti_tol:
            score += w_ti * 0.5
            feedback_parts.append(f"~ TI reported ({agent_ti:.3f}) but diameters missing")
        else:
            feedback_parts.append(f"✗ TI error: {agent_ti:.3f} vs GT {gt_ti:.3f}")
    else:
        feedback_parts.append("✗ Tracheal Index not reported")
    
    # ================================================================
    # CRITERION 5: Classification Correct (10 points)
    # ================================================================
    # Normalize classifications for comparison
    def normalize_class(c):
        c = c.lower().strip()
        if "normal" in c:
            return "normal"
        elif "saber" in c or "sabre" in c:
            return "saber-sheath"
        elif "ap" in c or "narrow" in c:
            return "ap-narrowing"
        return c
    
    agent_class_norm = normalize_class(agent_class)
    gt_class_norm = normalize_class(gt_class)
    
    details['agent_classification_normalized'] = agent_class_norm
    details['gt_classification_normalized'] = gt_class_norm
    
    if agent_class_norm and agent_class_norm == gt_class_norm:
        score += w_class
        feedback_parts.append(f"✓ Classification correct: {result.get('classification', '')}")
    elif agent_class_norm:
        feedback_parts.append(f"✗ Classification incorrect: '{result.get('classification', '')}' vs GT '{gt_data.get('classification', '')}'")
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ================================================================
    # CRITERION 6: Report Completeness (10 points)
    # ================================================================
    has_ap = agent_ap > 0
    has_trans = agent_trans > 0
    has_ti = agent_ti > 0
    has_class = bool(agent_class)
    has_slice = agent_slice > 0
    
    required_fields = 5
    present_fields = sum([has_ap, has_trans, has_ti, has_class, has_slice])
    completeness = present_fields / required_fields
    completeness_score = w_report * completeness
    score += completeness_score
    
    details['report_completeness'] = {
        'has_ap_diameter': has_ap,
        'has_transverse_diameter': has_trans,
        'has_tracheal_index': has_ti,
        'has_classification': has_class,
        'has_slice_number': has_slice,
        'completeness_ratio': completeness
    }
    
    if completeness == 1.0:
        feedback_parts.append("✓ Report complete with all required fields")
    else:
        missing = []
        if not has_ap: missing.append("AP diameter")
        if not has_trans: missing.append("transverse diameter")
        if not has_ti: missing.append("tracheal index")
        if not has_class: missing.append("classification")
        if not has_slice: missing.append("slice number")
        feedback_parts.append(f"~ Report incomplete, missing: {', '.join(missing)}")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Pass requires:
    # 1. Score >= 60 points
    # 2. At least one diameter measurement is accurate (within tolerance)
    
    at_least_one_accurate = (ap_error <= diameter_tol and agent_ap > 0) or \
                           (trans_error <= diameter_tol and agent_trans > 0)
    
    passed = score >= 60.0 and at_least_one_accurate
    
    # Round score
    score = round(score, 1)
    
    # Build feedback
    feedback_parts.insert(0, f"Total Score: {score}/100")
    if passed:
        feedback_parts.insert(1, "PASSED: Score >= 60 with at least one accurate diameter measurement")
    else:
        if score < 60:
            feedback_parts.insert(1, f"FAILED: Score {score} < 60 required")
        else:
            feedback_parts.insert(1, "FAILED: Neither diameter measurement was accurate (within 3mm)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": to_python_type(details)
    }