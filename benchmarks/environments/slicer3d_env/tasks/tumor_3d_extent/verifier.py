#!/usr/bin/env python3
"""
Verifier for Three-Dimensional Tumor Extent Measurement task.

VERIFICATION STRATEGY:
1. AP dimension accuracy - compare to ground truth bounding box (20 pts)
2. ML dimension accuracy - compare to ground truth bounding box (20 pts)
3. SI dimension accuracy - compare to ground truth bounding box (20 pts)
4. Volume calculation correct - verify ellipsoid formula applied (15 pts)
5. Markups properly named - check for Tumor_AP_mm, Tumor_ML_mm, Tumor_SI_mm (10 pts)
6. Report completeness - JSON with all required fields (10 pts)
7. Markups file saved - file exists and created during task (5 pts)

Ground Truth: Computed from BraTS segmentation bounding box
Pass Threshold: 60 points with at least 2 dimensions within tolerance
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
    """Convert numpy types to Python native types."""
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


def safe_float(value, default=0.0):
    """Safely convert a value to float."""
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def calculate_ellipsoid_volume(ap_mm, ml_mm, si_mm):
    """Calculate ellipsoid volume: V = (π/6) × AP × ML × SI (in mL)."""
    if ap_mm <= 0 or ml_mm <= 0 or si_mm <= 0:
        return 0.0
    volume_mm3 = (math.pi / 6.0) * ap_mm * ml_mm * si_mm
    volume_ml = volume_mm3 / 1000.0
    return volume_ml


def verify_tumor_3d_extent(traj, env_info, task_info):
    """
    Verify three-dimensional tumor extent measurement task.
    
    Scoring (100 points total):
    - AP accuracy: 20 points (within tolerance)
    - ML accuracy: 20 points (within tolerance)
    - SI accuracy: 20 points (within tolerance)
    - Volume calculation: 15 points (correct application of formula)
    - Markups named correctly: 10 points
    - Report completeness: 10 points
    - Markups file saved: 5 points
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
    dimension_tolerance = metadata.get('dimension_tolerance_mm', 10.0)
    volume_tolerance_percent = metadata.get('volume_tolerance_percent', 25.0)
    weights = metadata.get('scoring_weights', {})
    
    w_ap = weights.get('ap_accuracy', 20)
    w_ml = weights.get('ml_accuracy', 20)
    w_si = weights.get('si_accuracy', 20)
    w_volume = weights.get('volume_calculation', 15)
    w_names = weights.get('markups_named', 10)
    w_report = weights.get('report_complete', 10)
    w_markups = weights.get('markups_saved', 5)
    
    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tumor_extent_result.json", temp_result.name)
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
        copy_from_env("/tmp/dimensions_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Extract ground truth dimensions
    gt_dims = gt_data.get('dimensions_mm', {})
    gt_ap = gt_dims.get('AP', 0)
    gt_ml = gt_dims.get('ML', 0)
    gt_si = gt_dims.get('SI', 0)
    gt_volume = gt_data.get('ellipsoid_volume_ml', 0)
    
    logger.info(f"Ground truth: AP={gt_ap}, ML={gt_ml}, SI={gt_si}, Volume={gt_volume}")
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {
        "ground_truth": {
            "AP_mm": gt_ap,
            "ML_mm": gt_ml,
            "SI_mm": gt_si,
            "volume_ml": gt_volume
        }
    }
    
    # Extract agent's measurements
    measurements = result.get('measurements', {})
    reported = result.get('reported_values', {})
    
    # Prefer direct markup measurements, fall back to reported values
    agent_ap = safe_float(measurements.get('ap_mm')) or safe_float(reported.get('ap_mm'))
    agent_ml = safe_float(measurements.get('ml_mm')) or safe_float(reported.get('ml_mm'))
    agent_si = safe_float(measurements.get('si_mm')) or safe_float(reported.get('si_mm'))
    agent_volume = safe_float(reported.get('volume_ml'))
    
    details['agent_measurements'] = {
        "AP_mm": agent_ap,
        "ML_mm": agent_ml,
        "SI_mm": agent_si,
        "volume_ml": agent_volume
    }
    
    logger.info(f"Agent measurements: AP={agent_ap}, ML={agent_ml}, SI={agent_si}, Volume={agent_volume}")
    
    # Track how many dimensions are correct
    dimensions_correct = 0
    
    # ============================================================
    # CRITERION 1: AP Dimension Accuracy (20 points)
    # ============================================================
    if agent_ap > 0 and gt_ap > 0:
        ap_error = abs(agent_ap - gt_ap)
        details['ap_error_mm'] = round(ap_error, 2)
        
        if ap_error <= dimension_tolerance:
            score += w_ap
            dimensions_correct += 1
            feedback_parts.append(f"✓ AP correct ({agent_ap:.1f}mm, error={ap_error:.1f}mm)")
        elif ap_error <= dimension_tolerance * 2:
            partial = int(w_ap * 0.5)
            score += partial
            feedback_parts.append(f"~ AP close ({agent_ap:.1f}mm, error={ap_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ AP inaccurate ({agent_ap:.1f}mm vs {gt_ap:.1f}mm)")
    else:
        feedback_parts.append("✗ AP not measured")
    
    # ============================================================
    # CRITERION 2: ML Dimension Accuracy (20 points)
    # ============================================================
    if agent_ml > 0 and gt_ml > 0:
        ml_error = abs(agent_ml - gt_ml)
        details['ml_error_mm'] = round(ml_error, 2)
        
        if ml_error <= dimension_tolerance:
            score += w_ml
            dimensions_correct += 1
            feedback_parts.append(f"✓ ML correct ({agent_ml:.1f}mm, error={ml_error:.1f}mm)")
        elif ml_error <= dimension_tolerance * 2:
            partial = int(w_ml * 0.5)
            score += partial
            feedback_parts.append(f"~ ML close ({agent_ml:.1f}mm, error={ml_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ ML inaccurate ({agent_ml:.1f}mm vs {gt_ml:.1f}mm)")
    else:
        feedback_parts.append("✗ ML not measured")
    
    # ============================================================
    # CRITERION 3: SI Dimension Accuracy (20 points)
    # ============================================================
    if agent_si > 0 and gt_si > 0:
        si_error = abs(agent_si - gt_si)
        details['si_error_mm'] = round(si_error, 2)
        
        if si_error <= dimension_tolerance:
            score += w_si
            dimensions_correct += 1
            feedback_parts.append(f"✓ SI correct ({agent_si:.1f}mm, error={si_error:.1f}mm)")
        elif si_error <= dimension_tolerance * 2:
            partial = int(w_si * 0.5)
            score += partial
            feedback_parts.append(f"~ SI close ({agent_si:.1f}mm, error={si_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ SI inaccurate ({agent_si:.1f}mm vs {gt_si:.1f}mm)")
    else:
        feedback_parts.append("✗ SI not measured")
    
    details['dimensions_correct'] = dimensions_correct
    
    # ============================================================
    # CRITERION 4: Volume Calculation (15 points)
    # ============================================================
    if agent_volume > 0:
        # Check if agent applied formula correctly with their measurements
        expected_from_agent = calculate_ellipsoid_volume(agent_ap, agent_ml, agent_si)
        volume_calc_error = abs(agent_volume - expected_from_agent) if expected_from_agent > 0 else float('inf')
        
        # Also check against ground truth volume
        gt_volume_error_pct = abs(agent_volume - gt_volume) / gt_volume * 100 if gt_volume > 0 else float('inf')
        
        details['agent_expected_volume'] = round(expected_from_agent, 2)
        details['volume_formula_error'] = round(volume_calc_error, 2)
        details['volume_gt_error_pct'] = round(gt_volume_error_pct, 2)
        
        # Give points if formula was applied correctly to agent's measurements
        if expected_from_agent > 0 and volume_calc_error < 1.0:  # Within 1 mL of expected
            score += w_volume
            feedback_parts.append(f"✓ Volume formula correct ({agent_volume:.2f} mL)")
        elif gt_volume_error_pct <= volume_tolerance_percent:
            score += int(w_volume * 0.7)
            feedback_parts.append(f"~ Volume close to GT ({agent_volume:.2f} vs {gt_volume:.2f} mL)")
        else:
            score += int(w_volume * 0.3)  # Partial credit for attempting
            feedback_parts.append(f"✗ Volume calculation error ({agent_volume:.2f} mL)")
    else:
        feedback_parts.append("✗ Volume not reported")
    
    # ============================================================
    # CRITERION 5: Markups Named Correctly (10 points)
    # ============================================================
    markup_names = result.get('markup_names_found', '').lower()
    names_found = 0
    
    if 'ap' in markup_names or 'anterior' in markup_names:
        names_found += 1
    if 'ml' in markup_names or 'mediolateral' in markup_names or 'lateral' in markup_names:
        names_found += 1
    if 'si' in markup_names or 'superior' in markup_names or 'inferior' in markup_names:
        names_found += 1
    
    details['markup_names_found'] = names_found
    
    if names_found >= 3:
        score += w_names
        feedback_parts.append("✓ All markups properly named")
    elif names_found >= 2:
        score += int(w_names * 0.7)
        feedback_parts.append(f"~ {names_found}/3 markups named correctly")
    elif names_found >= 1:
        score += int(w_names * 0.3)
        feedback_parts.append(f"~ Only {names_found}/3 markups named")
    else:
        feedback_parts.append("✗ Markups not properly named")
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_during_task = result.get('report_created_during_task', False)
    
    if report_exists and report_during_task:
        report_fields = 0
        if reported.get('ap_mm'):
            report_fields += 1
        if reported.get('ml_mm'):
            report_fields += 1
        if reported.get('si_mm'):
            report_fields += 1
        if reported.get('volume_ml'):
            report_fields += 1
        
        details['report_fields_found'] = report_fields
        
        if report_fields >= 4:
            score += w_report
            feedback_parts.append("✓ Report complete with all fields")
        elif report_fields >= 2:
            score += int(w_report * 0.5)
            feedback_parts.append(f"~ Report partial ({report_fields}/4 fields)")
        else:
            feedback_parts.append("✗ Report incomplete")
    elif report_exists:
        feedback_parts.append("✗ Report existed before task (not newly created)")
    else:
        feedback_parts.append("✗ No report file found")
    
    # ============================================================
    # CRITERION 7: Markups File Saved (5 points)
    # ============================================================
    markups_exists = result.get('markups_exists', False)
    markups_during_task = result.get('markups_created_during_task', False)
    
    if markups_exists and markups_during_task:
        score += w_markups
        feedback_parts.append("✓ Markups file saved")
    elif markups_exists:
        score += int(w_markups * 0.5)
        feedback_parts.append("~ Markups file exists but may predate task")
    else:
        feedback_parts.append("✗ Markups file not saved")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Pass requires 60+ points AND at least 2 dimensions correct
    key_criteria_met = dimensions_correct >= 2
    passed = score >= 60 and key_criteria_met
    
    if not key_criteria_met and score >= 60:
        feedback_parts.append(f"⚠ Score {score} but only {dimensions_correct}/3 dimensions correct")
    
    # Final feedback
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details
    })