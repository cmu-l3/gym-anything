#!/usr/bin/env python3
"""
Verifier for tracheal diameter measurement task.

VERIFICATION METRICS:
1. Measurement exists - ruler/line markup was created (10 points)
2. Measurement in trachea - measurement is at correct anatomical location (15 points)
3. Diameter accuracy - measurement within 3mm of ground truth (40 points)
4. ETT recommendation - appropriate tube size for measured diameter (20 points)
5. Report completeness - JSON report with required fields (15 points)

Ground Truth: Computed from CT using air HU thresholding
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


def get_recommended_ett(tracheal_diameter_mm: float) -> float:
    """
    Calculate recommended ETT size based on tracheal diameter.
    
    Rule: ETT OD should be 2-3mm less than tracheal diameter
    ETT OD ≈ ETT ID + 2mm
    So: ETT ID ≈ tracheal_diameter - 4 to 5mm
    
    Returns nearest standard size.
    """
    ett_id_calc = tracheal_diameter_mm - 4.5
    standard_sizes = [6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0]
    return min(standard_sizes, key=lambda x: abs(x - ett_id_calc))


def is_valid_ett_for_diameter(ett_size: float, tracheal_diameter: float) -> bool:
    """
    Check if ETT size is appropriate for given tracheal diameter.
    
    ETT OD = ETT ID + 2mm (approximately)
    ETT OD should be 2-4mm less than tracheal diameter (leaving clearance)
    
    So: ETT ID should be in range [tracheal_diameter - 6, tracheal_diameter - 4]
    We'll be lenient: within 2mm of ideal
    """
    ideal_ett = get_recommended_ett(tracheal_diameter)
    return abs(ett_size - ideal_ett) <= 1.5  # Within 1.5mm of ideal


def verify_tracheal_measurement(traj, env_info, task_info):
    """
    Verify tracheal measurement task completion.
    
    Scoring (100 points total):
    - Measurement exists: 10 points
    - Measurement in trachea: 15 points
    - Diameter accuracy: 40 points (within 3mm)
    - ETT recommendation: 20 points
    - Report completeness: 15 points
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
    
    diameter_error_max = thresholds.get('diameter_error_max_mm', 3.0)
    
    w_measurement_exists = weights.get('measurement_exists', 10)
    w_measurement_location = weights.get('measurement_in_trachea', 15)
    w_diameter_accuracy = weights.get('diameter_accuracy', 40)
    w_ett_recommendation = weights.get('ett_recommendation', 20)
    w_report = weights.get('report_complete', 15)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/tracheal_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/trachea_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_diameter = gt_data.get('tracheal_diameter_mm', 0)
    gt_ett = gt_data.get('recommended_ett_size_mm', 0)
    gt_z = gt_data.get('measurement_z_mm', 0)
    gt_carina_z = gt_data.get('carina_slice_z', 0) * gt_data.get('voxel_spacing_mm', [1,1,1])[2]
    
    details['gt_diameter_mm'] = gt_diameter
    details['gt_ett_size_mm'] = gt_ett
    details['gt_measurement_z_mm'] = gt_z
    
    # ============================================================
    # CRITERION 1: Measurement exists (10 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_created = result.get('measurement_created_during_task', False)
    
    if measurement_exists and measurement_created:
        score += w_measurement_exists
        feedback_parts.append(f"✓ Measurement created ({w_measurement_exists}pts)")
        details['measurement_exists'] = True
    elif measurement_exists:
        # File exists but wasn't created during task - partial credit
        score += w_measurement_exists * 0.5
        feedback_parts.append(f"△ Measurement exists but may be pre-existing ({w_measurement_exists*0.5:.0f}pts)")
        details['measurement_exists'] = True
        details['measurement_timing_issue'] = True
    else:
        feedback_parts.append(f"✗ No measurement found (0/{w_measurement_exists}pts)")
        details['measurement_exists'] = False
        # Can't verify much else without a measurement
        return {
            "passed": False,
            "score": to_python_type(score),
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    # ============================================================
    # Get agent's measured values
    # ============================================================
    agent_diameter = 0.0
    agent_ett = 0.0
    agent_z = 0.0
    
    # Try from exported measurement
    measured_diam_str = result.get('measured_diameter_mm', '')
    if measured_diam_str:
        try:
            agent_diameter = float(measured_diam_str)
        except (ValueError, TypeError):
            pass
    
    # Try from report
    reported_diam_str = result.get('reported_diameter_mm', '')
    if reported_diam_str and agent_diameter == 0:
        try:
            agent_diameter = float(reported_diam_str)
        except (ValueError, TypeError):
            pass
    
    # If still no diameter from measurement, check if any value was reported
    if agent_diameter == 0:
        feedback_parts.append("✗ No diameter value could be extracted")
        return {
            "passed": False,
            "score": to_python_type(score),
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    details['agent_diameter_mm'] = agent_diameter
    
    # Get z-coordinate
    meas_z_str = result.get('measurement_z_mm', '')
    if meas_z_str:
        try:
            agent_z = float(meas_z_str)
        except (ValueError, TypeError):
            pass
    details['agent_z_mm'] = agent_z
    
    # Get ETT recommendation
    reported_ett_str = result.get('reported_ett_size_mm', '')
    if reported_ett_str:
        try:
            agent_ett = float(reported_ett_str)
        except (ValueError, TypeError):
            pass
    details['agent_ett_mm'] = agent_ett
    
    # ============================================================
    # CRITERION 2: Measurement in trachea location (15 points)
    # ============================================================
    # Check if measurement z-coordinate is in reasonable trachea range
    # (above carina, not too high in neck)
    
    if agent_z > 0 and gt_z > 0:
        z_error = abs(agent_z - gt_z)
        max_z_error = 50.0  # mm - allow 5cm range
        
        if z_error <= max_z_error:
            score += w_measurement_location
            feedback_parts.append(f"✓ Measurement at trachea level (z={agent_z:.0f}mm, {w_measurement_location}pts)")
            details['z_error_mm'] = z_error
        elif z_error <= max_z_error * 2:
            # Partial credit
            partial = w_measurement_location * 0.5
            score += partial
            feedback_parts.append(f"△ Measurement location slightly off (z={agent_z:.0f}mm, {partial:.0f}pts)")
            details['z_error_mm'] = z_error
        else:
            feedback_parts.append(f"✗ Measurement not at trachea level (z={agent_z:.0f}mm, 0/{w_measurement_location}pts)")
            details['z_error_mm'] = z_error
    else:
        # Can't verify location, give benefit of doubt if diameter is reasonable
        if 10 <= agent_diameter <= 30:
            score += w_measurement_location * 0.7
            feedback_parts.append(f"△ Location not verified but diameter reasonable ({w_measurement_location*0.7:.0f}pts)")
        else:
            feedback_parts.append(f"✗ Cannot verify measurement location (0/{w_measurement_location}pts)")
    
    # ============================================================
    # CRITERION 3: Diameter accuracy (40 points)
    # ============================================================
    if gt_diameter > 0:
        diameter_error = abs(agent_diameter - gt_diameter)
        details['diameter_error_mm'] = diameter_error
        
        if diameter_error <= diameter_error_max:
            # Full points
            score += w_diameter_accuracy
            feedback_parts.append(f"✓ Diameter accurate: {agent_diameter:.1f}mm (GT: {gt_diameter:.1f}mm, error: {diameter_error:.1f}mm, {w_diameter_accuracy}pts)")
            details['diameter_accurate'] = True
        elif diameter_error <= diameter_error_max * 2:
            # Partial points (within 6mm)
            partial = w_diameter_accuracy * (1 - (diameter_error - diameter_error_max) / diameter_error_max)
            partial = max(0, partial)
            score += partial
            feedback_parts.append(f"△ Diameter partially accurate: {agent_diameter:.1f}mm (GT: {gt_diameter:.1f}mm, error: {diameter_error:.1f}mm, {partial:.0f}pts)")
            details['diameter_accurate'] = False
        else:
            feedback_parts.append(f"✗ Diameter inaccurate: {agent_diameter:.1f}mm (GT: {gt_diameter:.1f}mm, error: {diameter_error:.1f}mm, 0/{w_diameter_accuracy}pts)")
            details['diameter_accurate'] = False
    else:
        # No ground truth - check if measurement is physiologically reasonable
        if 10 <= agent_diameter <= 30:
            # Normal adult trachea range
            score += w_diameter_accuracy * 0.5
            feedback_parts.append(f"△ Diameter {agent_diameter:.1f}mm is physiologically reasonable ({w_diameter_accuracy*0.5:.0f}pts)")
        else:
            feedback_parts.append(f"✗ Diameter {agent_diameter:.1f}mm outside normal range (0/{w_diameter_accuracy}pts)")
    
    # ============================================================
    # CRITERION 4: ETT recommendation (20 points)
    # ============================================================
    if agent_ett > 0:
        # Check if ETT is valid for the measured diameter
        ideal_ett = get_recommended_ett(agent_diameter)
        details['ideal_ett_for_measured'] = ideal_ett
        
        if is_valid_ett_for_diameter(agent_ett, agent_diameter):
            score += w_ett_recommendation
            feedback_parts.append(f"✓ ETT recommendation {agent_ett}mm appropriate for {agent_diameter:.1f}mm trachea ({w_ett_recommendation}pts)")
            details['ett_appropriate'] = True
        elif abs(agent_ett - ideal_ett) <= 1.0:
            # Close enough
            partial = w_ett_recommendation * 0.7
            score += partial
            feedback_parts.append(f"△ ETT {agent_ett}mm slightly off (ideal: {ideal_ett}mm, {partial:.0f}pts)")
            details['ett_appropriate'] = False
        else:
            feedback_parts.append(f"✗ ETT {agent_ett}mm not appropriate for {agent_diameter:.1f}mm trachea (ideal: {ideal_ett}mm, 0/{w_ett_recommendation}pts)")
            details['ett_appropriate'] = False
    else:
        feedback_parts.append(f"✗ No ETT recommendation provided (0/{w_ett_recommendation}pts)")
        details['ett_appropriate'] = False
    
    # ============================================================
    # CRITERION 5: Report completeness (15 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    required_fields = ['tracheal_diameter_mm', 'recommended_ett_size_mm']
    optional_fields = ['ap_diameter_mm', 'transverse_diameter_mm', 'trachea_shape', 'measurement_slice', 'abnormalities']
    
    fields_present = 0
    if report_exists:
        # Count which fields are present based on what we extracted
        if result.get('reported_diameter_mm'):
            fields_present += 1
        if result.get('reported_ett_size_mm'):
            fields_present += 1
        if result.get('reported_trachea_shape') and result.get('reported_trachea_shape') != 'unknown':
            fields_present += 0.5  # Bonus for optional field
    
    if report_exists and report_created:
        if fields_present >= 2:
            score += w_report
            feedback_parts.append(f"✓ Report complete with required fields ({w_report}pts)")
            details['report_complete'] = True
        elif fields_present >= 1:
            partial = w_report * 0.6
            score += partial
            feedback_parts.append(f"△ Report partially complete ({partial:.0f}pts)")
            details['report_complete'] = False
        else:
            score += w_report * 0.3
            feedback_parts.append(f"△ Report exists but missing fields ({w_report*0.3:.0f}pts)")
            details['report_complete'] = False
    elif report_exists:
        score += w_report * 0.5
        feedback_parts.append(f"△ Report exists but may be pre-existing ({w_report*0.5:.0f}pts)")
        details['report_complete'] = False
    else:
        feedback_parts.append(f"✗ No report found (0/{w_report}pts)")
        details['report_complete'] = False
    
    # ============================================================
    # FINAL RESULT
    # ============================================================
    max_score = w_measurement_exists + w_measurement_location + w_diameter_accuracy + w_ett_recommendation + w_report
    
    # Determine pass/fail
    # Must have: measurement exists AND (diameter accurate OR physiologically reasonable)
    diameter_ok = details.get('diameter_accurate', False) or (10 <= agent_diameter <= 30)
    key_criteria_met = measurement_exists and diameter_ok
    
    passed = score >= 60 and key_criteria_met
    
    details['max_score'] = max_score
    details['key_criteria_met'] = key_criteria_met
    
    return {
        "passed": passed,
        "score": to_python_type(int(score)),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }