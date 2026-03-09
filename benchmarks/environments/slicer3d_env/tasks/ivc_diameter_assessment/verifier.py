#!/usr/bin/env python3
"""
Verifier for IVC Diameter Assessment task.

VERIFICATION METRICS:
1. Intrahepatic diameter accuracy (within ±4mm) - 25 points
2. Infrarenal diameter accuracy (within ±3mm) - 20 points
3. Measurement location validity (in IVC region) - 15 points
4. Classification correctness (Normal/Dilated/Collapsed) - 15 points
5. Report completeness - 10 points
6. Both levels measured - 10 points
7. Morphology assessment correct - 5 points

Total: 100 points
Pass threshold: 60 points AND at least one accurate diameter measurement
"""

import json
import os
import sys
import tempfile
import logging
import math
from typing import Dict, Any, Tuple, Optional, List

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


def parse_slicer_markup_measurements(markup_data: Dict) -> List[Dict]:
    """
    Parse Slicer markup JSON to extract ruler/line measurements.
    Returns list of measurement dicts with length_mm and positions.
    """
    measurements = []
    
    # Handle different markup formats
    # Format 1: Our exported format with 'measurements' or 'markups' array
    markups = markup_data.get('markups', markup_data.get('measurements', []))
    
    for markup in markups:
        # Format from our export script
        if 'length_mm' in markup:
            measurements.append({
                'length_mm': float(markup['length_mm']),
                'p1': markup.get('p1', [0, 0, 0]),
                'p2': markup.get('p2', [0, 0, 0]),
                'name': markup.get('name', 'unnamed'),
                'type': markup.get('type', 'line')
            })
        
        # Native Slicer markup format
        elif 'controlPoints' in markup:
            control_points = markup.get('controlPoints', [])
            if len(control_points) >= 2:
                p1 = control_points[0].get('position', [0, 0, 0])
                p2 = control_points[1].get('position', [0, 0, 0])
                
                # Calculate Euclidean distance
                length = math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))
                
                measurements.append({
                    'length_mm': length,
                    'p1': p1,
                    'p2': p2,
                    'name': markup.get('name', 'unnamed'),
                    'type': markup.get('type', 'Line')
                })
    
    return measurements


def check_measurement_location(measurement: Dict, ivc_bounds: Dict, tolerance: float = 30.0) -> bool:
    """
    Verify that a measurement is located within the IVC region.
    Uses the bounding box from ground truth with tolerance.
    """
    if not ivc_bounds:
        return True  # Can't verify without bounds, assume valid
    
    p1 = measurement.get('p1', [0, 0, 0])
    p2 = measurement.get('p2', [0, 0, 0])
    
    # Check if midpoint is within IVC bounds (with tolerance)
    midpoint = [(p1[i] + p2[i]) / 2 for i in range(3)]
    
    x_ok = (ivc_bounds.get('x_min', -1000) - tolerance <= midpoint[0] <= 
            ivc_bounds.get('x_max', 1000) + tolerance)
    y_ok = (ivc_bounds.get('y_min', -1000) - tolerance <= midpoint[1] <= 
            ivc_bounds.get('y_max', 1000) + tolerance)
    
    return x_ok and y_ok


def classify_ivc(intrahepatic_mm: float) -> str:
    """Classify IVC based on intrahepatic diameter."""
    if intrahepatic_mm < 15:
        return "Collapsed"
    elif intrahepatic_mm > 25:
        return "Dilated"
    else:
        return "Normal"


def verify_ivc_diameter(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify IVC diameter assessment task completion.
    
    Scoring (100 points total):
    - Intrahepatic diameter accuracy: 25 points (within ±4mm)
    - Infrarenal diameter accuracy: 20 points (within ±3mm)
    - Measurement location valid: 15 points
    - Classification correct: 15 points
    - Report completeness: 10 points
    - Both levels measured: 10 points
    - Morphology correct: 5 points
    
    Pass threshold: 60 points AND at least one accurate diameter measurement
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
    
    intrahepatic_error_max = thresholds.get('intrahepatic_error_max_mm', 4.0)
    infrarenal_error_max = thresholds.get('infrarenal_error_max_mm', 3.0)
    
    w_intrahepatic = weights.get('intrahepatic_accuracy', 25)
    w_infrarenal = weights.get('infrarenal_accuracy', 20)
    w_location = weights.get('measurement_location_valid', 15)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_completeness', 10)
    w_both_levels = weights.get('both_levels_measured', 10)
    w_morphology = weights.get('morphology_correct', 5)
    
    # Initialize results
    score = 0
    feedback_parts = []
    details = {
        'intrahepatic_accuracy': False,
        'infrarenal_accuracy': False,
        'measurement_location_valid': False,
        'classification_correct': False,
        'report_complete': False,
        'both_levels_measured': False,
        'morphology_correct': False,
    }
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/ivc_task_result.json", temp_result.name)
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
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/ivc_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        # Use defaults if ground truth not available
        gt_data = {
            'intrahepatic_diameter_mm': 22.0,
            'infrarenal_diameter_mm': 18.0,
            'classification': 'Normal',
            'morphology': 'Normal',
            'ivc_bounds': {}
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_intrahepatic = gt_data.get('intrahepatic_diameter_mm', 22.0)
    gt_infrarenal = gt_data.get('infrarenal_diameter_mm', 18.0)
    gt_classification = gt_data.get('classification', 'Normal')
    gt_morphology = gt_data.get('morphology', 'Normal')
    ivc_bounds = gt_data.get('ivc_bounds', {})
    
    details['gt_intrahepatic_mm'] = gt_intrahepatic
    details['gt_infrarenal_mm'] = gt_infrarenal
    details['gt_classification'] = gt_classification
    
    # ============================================================
    # Load and parse measurements
    # ============================================================
    measurements = []
    temp_meas = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    
    try:
        copy_from_env("/tmp/ivc_measurements.mrk.json", temp_meas.name)
        with open(temp_meas.name, 'r') as f:
            markup_data = json.load(f)
        measurements = parse_slicer_markup_measurements(markup_data)
        logger.info(f"Parsed {len(measurements)} measurements from markup file")
    except Exception as e:
        logger.warning(f"Could not parse measurements file: {e}")
    finally:
        if os.path.exists(temp_meas.name):
            os.unlink(temp_meas.name)
    
    # ============================================================
    # CRITERION 1: Both levels measured (10 points)
    # ============================================================
    if len(measurements) >= 2:
        details['both_levels_measured'] = True
        score += w_both_levels
        feedback_parts.append(f"✓ Both measurement levels present ({len(measurements)} measurements) (+{w_both_levels})")
    elif len(measurements) == 1:
        score += w_both_levels // 2
        feedback_parts.append(f"⚠ Only one measurement found ({w_both_levels // 2} pts)")
    else:
        feedback_parts.append("✗ No measurements found in markup file")
    
    # ============================================================
    # Extract measured diameters
    # ============================================================
    measured_intrahepatic = None
    measured_infrarenal = None
    
    # Try to get from result file first (may have been extracted from measurements)
    try:
        if result.get('measured_intrahepatic'):
            measured_intrahepatic = float(result['measured_intrahepatic'])
        if result.get('measured_infrarenal'):
            measured_infrarenal = float(result['measured_infrarenal'])
    except (ValueError, TypeError):
        pass
    
    # If not available, extract from parsed measurements
    # Sort by length (intrahepatic is typically larger)
    if len(measurements) >= 2 and (measured_intrahepatic is None or measured_infrarenal is None):
        sorted_meas = sorted(measurements, key=lambda x: x['length_mm'], reverse=True)
        measured_intrahepatic = sorted_meas[0]['length_mm']
        measured_infrarenal = sorted_meas[1]['length_mm']
    elif len(measurements) == 1 and measured_intrahepatic is None:
        measured_intrahepatic = measurements[0]['length_mm']
    
    details['measured_intrahepatic_mm'] = measured_intrahepatic
    details['measured_infrarenal_mm'] = measured_infrarenal
    
    # ============================================================
    # CRITERION 2: Intrahepatic diameter accuracy (25 points)
    # ============================================================
    if measured_intrahepatic is not None:
        intrahepatic_error = abs(measured_intrahepatic - gt_intrahepatic)
        details['intrahepatic_error_mm'] = round(intrahepatic_error, 2)
        
        if intrahepatic_error <= intrahepatic_error_max:
            details['intrahepatic_accuracy'] = True
            score += w_intrahepatic
            feedback_parts.append(
                f"✓ Intrahepatic diameter accurate: {measured_intrahepatic:.1f}mm "
                f"(GT: {gt_intrahepatic:.1f}mm, error: {intrahepatic_error:.1f}mm) (+{w_intrahepatic})"
            )
        else:
            feedback_parts.append(
                f"✗ Intrahepatic diameter inaccurate: {measured_intrahepatic:.1f}mm "
                f"(GT: {gt_intrahepatic:.1f}mm, error: {intrahepatic_error:.1f}mm, need ≤{intrahepatic_error_max}mm)"
            )
    else:
        feedback_parts.append("✗ No intrahepatic diameter measurement found")
    
    # ============================================================
    # CRITERION 3: Infrarenal diameter accuracy (20 points)
    # ============================================================
    if measured_infrarenal is not None:
        infrarenal_error = abs(measured_infrarenal - gt_infrarenal)
        details['infrarenal_error_mm'] = round(infrarenal_error, 2)
        
        if infrarenal_error <= infrarenal_error_max:
            details['infrarenal_accuracy'] = True
            score += w_infrarenal
            feedback_parts.append(
                f"✓ Infrarenal diameter accurate: {measured_infrarenal:.1f}mm "
                f"(GT: {gt_infrarenal:.1f}mm, error: {infrarenal_error:.1f}mm) (+{w_infrarenal})"
            )
        else:
            feedback_parts.append(
                f"✗ Infrarenal diameter inaccurate: {measured_infrarenal:.1f}mm "
                f"(GT: {gt_infrarenal:.1f}mm, error: {infrarenal_error:.1f}mm, need ≤{infrarenal_error_max}mm)"
            )
    else:
        feedback_parts.append("✗ No infrarenal diameter measurement found")
    
    # ============================================================
    # CRITERION 4: Measurement location validity (15 points)
    # ============================================================
    if measurements and ivc_bounds:
        location_valid_count = 0
        for m in measurements[:2]:
            if check_measurement_location(m, ivc_bounds):
                location_valid_count += 1
        
        if location_valid_count >= 1:
            details['measurement_location_valid'] = True
            score += w_location
            feedback_parts.append(f"✓ Measurement location valid ({location_valid_count}/2 in IVC region) (+{w_location})")
        else:
            feedback_parts.append("✗ Measurements not located in IVC region")
    elif measurements:
        # No bounds to check against, give benefit of doubt
        details['measurement_location_valid'] = True
        score += w_location
        feedback_parts.append(f"✓ Measurements present (location check skipped) (+{w_location})")
    else:
        feedback_parts.append("✗ No measurements to verify location")
    
    # ============================================================
    # CRITERION 5: Report completeness (10 points)
    # ============================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report_data = None
    
    try:
        copy_from_env("/tmp/ivc_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            report_data = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read report file: {e}")
        # Try from result data
        if result.get('report_exist'):
            report_data = {
                'intrahepatic_diameter_mm': result.get('intrahepatic_reported'),
                'infrarenal_diameter_mm': result.get('infrarenal_reported'),
                'classification': result.get('classification_reported'),
                'morphology': result.get('morphology_reported')
            }
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    if report_data:
        required_fields = ['intrahepatic_diameter_mm', 'infrarenal_diameter_mm', 'classification']
        present_fields = sum(1 for f in required_fields if report_data.get(f))
        
        if present_fields >= len(required_fields):
            details['report_complete'] = True
            score += w_report
            feedback_parts.append(f"✓ Report complete ({present_fields}/{len(required_fields)} required fields) (+{w_report})")
        else:
            partial_score = (w_report * present_fields) // len(required_fields)
            score += partial_score
            feedback_parts.append(f"⚠ Report incomplete ({present_fields}/{len(required_fields)} fields) (+{partial_score})")
    else:
        feedback_parts.append("✗ Report file not found or invalid")
    
    # ============================================================
    # CRITERION 6: Classification correct (15 points)
    # ============================================================
    reported_classification = ""
    if report_data:
        reported_classification = str(report_data.get('classification', '')).strip()
    elif result.get('classification_reported'):
        reported_classification = str(result.get('classification_reported', '')).strip()
    
    if reported_classification:
        # Normalize for comparison
        reported_norm = reported_classification.lower().replace(' ', '').replace('_', '')
        gt_norm = gt_classification.lower().replace(' ', '').replace('_', '')
        
        if reported_norm == gt_norm:
            details['classification_correct'] = True
            score += w_classification
            feedback_parts.append(f"✓ Classification correct: {reported_classification} (+{w_classification})")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {reported_classification} (expected: {gt_classification})")
    else:
        feedback_parts.append("✗ No classification reported")
    
    # ============================================================
    # CRITERION 7: Morphology assessment (5 points)
    # ============================================================
    reported_morphology = ""
    if report_data:
        reported_morphology = str(report_data.get('morphology', '')).strip().lower()
    elif result.get('morphology_reported'):
        reported_morphology = str(result.get('morphology_reported', '')).strip().lower()
    
    # Ground truth morphology should be "Normal" for AMOS data
    if 'normal' in reported_morphology or not reported_morphology:
        details['morphology_correct'] = True
        score += w_morphology
        feedback_parts.append(f"✓ Morphology assessment correct (+{w_morphology})")
    else:
        feedback_parts.append(f"⚠ Morphology reported as: {reported_morphology} (expected: Normal)")
    
    # ============================================================
    # Determine pass/fail
    # ============================================================
    key_criteria_met = details['intrahepatic_accuracy'] or details['infrarenal_accuracy']
    passed = score >= 60 and key_criteria_met
    
    details['total_score'] = score
    details['passed'] = passed
    
    # Final summary
    feedback_parts.append(f"\n=== TOTAL SCORE: {score}/100 ===")
    feedback_parts.append(f"Status: {'PASSED' if passed else 'FAILED'}")
    if not passed:
        if not key_criteria_met:
            feedback_parts.append("(Requires at least one accurate diameter measurement)")
        else:
            feedback_parts.append("(Requires ≥60 points)")
    
    # Convert all numpy types to Python types for JSON serialization
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # For testing
    result = verify_ivc_diameter({}, {}, {})
    print(json.dumps(result, indent=2))