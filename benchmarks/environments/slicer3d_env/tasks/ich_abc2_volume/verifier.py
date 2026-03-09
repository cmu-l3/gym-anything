#!/usr/bin/env python3
"""
Verifier for Intracerebral Hemorrhage ABC/2 Volume Estimation task.

VERIFICATION METRICS:
1. Volume accuracy - compare agent's ABC/2 calculation to ground truth
2. A measurement accuracy - largest diameter on max slice
3. B measurement accuracy - perpendicular diameter
4. C calculation accuracy - weighted slice count × thickness
5. Surgical threshold assessment - correct above/below 30mL determination
6. Report completeness - all required fields present

ABC/2 Formula: Volume (mL) = (A × B × C) / 2
where A, B are in cm and C = weighted_slice_count × slice_thickness_cm
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


def safe_float(val, default=0.0):
    """Safely convert value to float."""
    if val is None or val == '':
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def verify_ich_abc2_volume(traj, env_info, task_info):
    """
    Verify ICH ABC/2 volume estimation task completion.

    Scoring (100 points total):
    - Volume accuracy: 30 points (within 20% of ground truth)
    - A measurement: 10 points (within 15%)
    - B measurement: 10 points (within 15%)
    - C calculation: 15 points (within 20%)
    - Formula application: 10 points (A×B×C/2 = reported volume)
    - Surgical threshold: 15 points (correct above/below 30mL)
    - Report completeness: 10 points (all fields present)
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
    surgical_threshold_ml = metadata.get('surgical_threshold_ml', 30)

    volume_error_max = thresholds.get('volume_error_max_percent', 20.0)
    a_error_max = thresholds.get('a_error_max_percent', 15.0)
    b_error_max = thresholds.get('b_error_max_percent', 15.0)
    c_error_max = thresholds.get('c_error_max_percent', 20.0)

    w_volume = weights.get('volume_accuracy', 30)
    w_a = weights.get('a_measurement', 10)
    w_b = weights.get('b_measurement', 10)
    w_c = weights.get('c_calculation', 15)
    w_formula = weights.get('formula_application', 10)
    w_threshold = weights.get('surgical_threshold', 15)
    w_report = weights.get('report_completeness', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/ich_task_result.json", temp_result.name)
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
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/ich_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load ground truth: {e}"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Extract ground truth values
    gt_actual = gt_data.get('actual_measurements', {})
    gt_A = gt_actual.get('A_cm', 0)
    gt_B = gt_actual.get('B_cm', 0)
    gt_C = gt_actual.get('C_cm', 0)
    gt_volume = gt_actual.get('abc2_volume_ml', 0)
    gt_exceeds = gt_data.get('exceeds_30ml_threshold', False)

    details['gt_A_cm'] = gt_A
    details['gt_B_cm'] = gt_B
    details['gt_C_cm'] = gt_C
    details['gt_volume_ml'] = gt_volume
    details['gt_exceeds_30ml'] = gt_exceeds

    # ============================================================
    # EXTRACT AGENT'S VALUES
    # ============================================================
    reported = result.get('reported_values', {})
    agent_A = safe_float(reported.get('A_cm', ''))
    agent_B = safe_float(reported.get('B_cm', ''))
    agent_C = safe_float(reported.get('C_cm', ''))
    agent_volume = safe_float(reported.get('volume_ml', ''))
    agent_threshold_str = reported.get('exceeds_threshold', '')

    # Parse threshold boolean
    agent_exceeds = None
    if agent_threshold_str.lower() in ['true', '1', 'yes']:
        agent_exceeds = True
    elif agent_threshold_str.lower() in ['false', '0', 'no']:
        agent_exceeds = False

    details['agent_A_cm'] = agent_A
    details['agent_B_cm'] = agent_B
    details['agent_C_cm'] = agent_C
    details['agent_volume_ml'] = agent_volume
    details['agent_exceeds_30ml'] = agent_exceeds

    # ============================================================
    # Try to load agent report directly for more fields
    # ============================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
        
        # Override with direct report values if available
        if agent_A == 0 and 'measurement_A_cm' in agent_report:
            agent_A = safe_float(agent_report.get('measurement_A_cm'))
        if agent_B == 0 and 'measurement_B_cm' in agent_report:
            agent_B = safe_float(agent_report.get('measurement_B_cm'))
        if agent_C == 0 and 'measurement_C_cm' in agent_report:
            agent_C = safe_float(agent_report.get('measurement_C_cm'))
        if agent_volume == 0 and 'calculated_volume_ml' in agent_report:
            agent_volume = safe_float(agent_report.get('calculated_volume_ml'))
        if agent_exceeds is None and 'exceeds_30ml_threshold' in agent_report:
            agent_exceeds = bool(agent_report.get('exceeds_30ml_threshold'))
        
        details['agent_report_loaded'] = True
    except Exception as e:
        details['agent_report_loaded'] = False
        logger.info(f"Could not load agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)

    # ============================================================
    # CRITERION 1: Volume Accuracy (30 points)
    # ============================================================
    if agent_volume > 0 and gt_volume > 0:
        volume_error_percent = abs(agent_volume - gt_volume) / gt_volume * 100
        details['volume_error_percent'] = round(volume_error_percent, 2)
        
        if volume_error_percent <= volume_error_max:
            score += w_volume
            feedback_parts.append(f"Volume accurate: {agent_volume:.1f}mL (GT: {gt_volume:.1f}mL, error: {volume_error_percent:.1f}%)")
        elif volume_error_percent <= volume_error_max * 1.5:
            partial = int(w_volume * 0.6)
            score += partial
            feedback_parts.append(f"Volume partially accurate: {agent_volume:.1f}mL (GT: {gt_volume:.1f}mL, error: {volume_error_percent:.1f}%)")
        else:
            feedback_parts.append(f"Volume inaccurate: {agent_volume:.1f}mL (GT: {gt_volume:.1f}mL, error: {volume_error_percent:.1f}%)")
    else:
        feedback_parts.append("No volume measurement provided")
        details['volume_error_percent'] = None

    # ============================================================
    # CRITERION 2: A Measurement (10 points)
    # ============================================================
    if agent_A > 0 and gt_A > 0:
        a_error_percent = abs(agent_A - gt_A) / gt_A * 100
        details['a_error_percent'] = round(a_error_percent, 2)
        
        if a_error_percent <= a_error_max:
            score += w_a
            feedback_parts.append(f"A measurement correct: {agent_A:.2f}cm (GT: {gt_A:.2f}cm)")
        elif a_error_percent <= a_error_max * 2:
            partial = int(w_a * 0.5)
            score += partial
            feedback_parts.append(f"A measurement close: {agent_A:.2f}cm (GT: {gt_A:.2f}cm, error: {a_error_percent:.1f}%)")
        else:
            feedback_parts.append(f"A measurement off: {agent_A:.2f}cm (GT: {gt_A:.2f}cm)")
    else:
        feedback_parts.append("No A measurement provided")
        details['a_error_percent'] = None

    # ============================================================
    # CRITERION 3: B Measurement (10 points)
    # ============================================================
    if agent_B > 0 and gt_B > 0:
        b_error_percent = abs(agent_B - gt_B) / gt_B * 100
        details['b_error_percent'] = round(b_error_percent, 2)
        
        if b_error_percent <= b_error_max:
            score += w_b
            feedback_parts.append(f"B measurement correct: {agent_B:.2f}cm (GT: {gt_B:.2f}cm)")
        elif b_error_percent <= b_error_max * 2:
            partial = int(w_b * 0.5)
            score += partial
            feedback_parts.append(f"B measurement close: {agent_B:.2f}cm (GT: {gt_B:.2f}cm, error: {b_error_percent:.1f}%)")
        else:
            feedback_parts.append(f"B measurement off: {agent_B:.2f}cm (GT: {gt_B:.2f}cm)")
    else:
        feedback_parts.append("No B measurement provided")
        details['b_error_percent'] = None

    # ============================================================
    # CRITERION 4: C Calculation (15 points)
    # ============================================================
    if agent_C > 0 and gt_C > 0:
        c_error_percent = abs(agent_C - gt_C) / gt_C * 100
        details['c_error_percent'] = round(c_error_percent, 2)
        
        if c_error_percent <= c_error_max:
            score += w_c
            feedback_parts.append(f"C calculation correct: {agent_C:.2f}cm (GT: {gt_C:.2f}cm)")
        elif c_error_percent <= c_error_max * 2:
            partial = int(w_c * 0.5)
            score += partial
            feedback_parts.append(f"C calculation close: {agent_C:.2f}cm (GT: {gt_C:.2f}cm, error: {c_error_percent:.1f}%)")
        else:
            feedback_parts.append(f"C calculation off: {agent_C:.2f}cm (GT: {gt_C:.2f}cm)")
    else:
        feedback_parts.append("No C measurement provided")
        details['c_error_percent'] = None

    # ============================================================
    # CRITERION 5: Formula Application (10 points)
    # Check if agent correctly applied ABC/2
    # ============================================================
    if agent_A > 0 and agent_B > 0 and agent_C > 0 and agent_volume > 0:
        expected_from_abc = (agent_A * agent_B * agent_C) / 2
        formula_error = abs(agent_volume - expected_from_abc)
        details['expected_from_abc'] = round(expected_from_abc, 2)
        details['formula_error_ml'] = round(formula_error, 2)
        
        # Allow small tolerance for rounding
        if formula_error <= 1.0:
            score += w_formula
            feedback_parts.append(f"ABC/2 formula applied correctly")
        elif formula_error <= 3.0:
            partial = int(w_formula * 0.5)
            score += partial
            feedback_parts.append(f"ABC/2 formula approximately correct (error: {formula_error:.1f}mL)")
        else:
            feedback_parts.append(f"ABC/2 formula may be incorrect (expected {expected_from_abc:.1f}mL from given A,B,C)")
    else:
        feedback_parts.append("Cannot verify formula application - missing A, B, C, or volume")

    # ============================================================
    # CRITERION 6: Surgical Threshold Assessment (15 points)
    # ============================================================
    if agent_exceeds is not None:
        # Check against ground truth
        if agent_exceeds == gt_exceeds:
            score += w_threshold
            threshold_status = "exceeds" if gt_exceeds else "does not exceed"
            feedback_parts.append(f"Surgical threshold assessment CORRECT: {threshold_status} 30mL")
        else:
            feedback_parts.append(f"Surgical threshold assessment INCORRECT: agent said {'exceeds' if agent_exceeds else 'under'}, GT is {'exceeds' if gt_exceeds else 'under'} 30mL")
        
        # Also check if agent's threshold is consistent with their volume
        if agent_volume > 0:
            agent_threshold_from_vol = agent_volume > surgical_threshold_ml
            if agent_threshold_from_vol == agent_exceeds:
                details['threshold_consistent_with_volume'] = True
            else:
                details['threshold_consistent_with_volume'] = False
                feedback_parts.append(f"Warning: Threshold inconsistent with reported volume ({agent_volume:.1f}mL)")
    else:
        feedback_parts.append("No surgical threshold assessment provided")

    # ============================================================
    # CRITERION 7: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    measurement_exists = result.get('measurement_exists', False)
    
    completeness_score = 0
    if report_exists:
        completeness_score += 3
    if report_created:
        completeness_score += 2  # Anti-gaming bonus
    if measurement_exists:
        completeness_score += 3
    if agent_A > 0 and agent_B > 0 and agent_C > 0 and agent_volume > 0:
        completeness_score += 2
    
    score += min(completeness_score, w_report)
    
    if completeness_score >= w_report:
        feedback_parts.append("Report complete with all required fields")
    elif completeness_score > 0:
        feedback_parts.append(f"Report partially complete ({completeness_score}/{w_report} points)")
    else:
        feedback_parts.append("Report missing or incomplete")

    details['report_exists'] = report_exists
    details['report_created_during_task'] = report_created
    details['measurement_exists'] = measurement_exists

    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: Volume within tolerance AND threshold assessment correct
    volume_ok = details.get('volume_error_percent', 100) is not None and details.get('volume_error_percent', 100) <= volume_error_max
    threshold_ok = agent_exceeds == gt_exceeds if agent_exceeds is not None else False
    
    passed = score >= 60 and (volume_ok or threshold_ok)
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    # Convert all values to Python native types
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details,
        "subscores": {
            "volume_accuracy": details.get('volume_error_percent', None),
            "a_accuracy": details.get('a_error_percent', None),
            "b_accuracy": details.get('b_error_percent', None),
            "c_accuracy": details.get('c_error_percent', None),
            "threshold_correct": agent_exceeds == gt_exceeds if agent_exceeds is not None else False
        }
    }