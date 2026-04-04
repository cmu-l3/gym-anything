#!/usr/bin/env python3
"""
Verifier for Common Bile Duct (CBD) diameter measurement task.

VERIFICATION STRATEGY:
1. Measurement exists (15 points) - ruler/line markup was created
2. Correct anatomical region (20 points) - measurement near porta hepatis
3. Diameter accuracy (25 points) - physiologically reasonable value (2-15mm)
4. Classification correct (15 points) - Normal/Borderline/Dilated matches value
5. Anatomical level documented (10 points) - report includes measurement level
6. Clinical interpretation (10 points) - appropriate clinical context
7. Report completeness (5 points) - all required JSON fields present

CBD Reference:
- Normal CBD: ≤ 6mm
- Borderline: 7-8mm  
- Dilated: > 8mm
- Physiological range: 2-15mm (anything outside is likely wrong structure)
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


def classify_cbd_diameter(diameter_mm):
    """
    Classify CBD diameter according to clinical thresholds.
    
    Returns:
        str: 'Normal', 'Borderline', or 'Dilated'
    """
    if diameter_mm <= 6.0:
        return "Normal"
    elif diameter_mm <= 8.0:
        return "Borderline"
    else:
        return "Dilated"


def parse_location_string(loc_str):
    """Parse a comma-separated location string into coordinates."""
    try:
        parts = loc_str.split(',')
        if len(parts) >= 3:
            return [float(parts[0]), float(parts[1]), float(parts[2])]
    except:
        pass
    return None


def calculate_distance(point1, point2):
    """Calculate Euclidean distance between two 3D points."""
    if point1 is None or point2 is None:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(point1, point2)))


def verify_cbd_measurement(traj, env_info, task_info):
    """
    Verify CBD measurement task completion.
    
    Scoring (100 points total):
    - Measurement exists: 15 points
    - Correct anatomical region: 20 points (near porta hepatis)
    - Diameter accuracy: 25 points (physiologically reasonable 2-15mm)
    - Classification correct: 15 points (matches measured value)
    - Anatomical level documented: 10 points
    - Clinical interpretation: 10 points
    - Report completeness: 5 points
    
    Pass threshold: 60 points with key criteria met
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
    weights = metadata.get('scoring_weights', {})
    cbd_range = metadata.get('cbd_diameter_range', {})
    
    w_measurement = weights.get('measurement_exists', 15)
    w_region = weights.get('correct_anatomical_region', 20)
    w_diameter = weights.get('diameter_accuracy', 25)
    w_classification = weights.get('classification_correct', 15)
    w_level = weights.get('anatomical_level_documented', 10)
    w_interpretation = weights.get('clinical_interpretation', 10)
    w_completeness = weights.get('report_completeness', 5)
    
    min_physiological = cbd_range.get('min_physiological_mm', 2.0)
    max_physiological = cbd_range.get('max_physiological_mm', 15.0)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/cbd_task_result.json", temp_result.name)
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
    
    # Load ground truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/cbd_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    # Parse ground truth porta hepatis location
    gt_porta_hepatis = gt_data.get('porta_hepatis_region_mm')
    if gt_porta_hepatis is None:
        gt_porta_str = result.get('gt_porta_hepatis_mm', '')
        gt_porta_hepatis = parse_location_string(gt_porta_str)
    
    details['gt_porta_hepatis_mm'] = gt_porta_hepatis
    
    # ============================================================
    # CRITERION 1: Measurement exists (15 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_created = result.get('measurement_created_during_task', False)
    
    if measurement_exists and measurement_created:
        score += w_measurement
        feedback_parts.append(f"✓ Measurement created during task (+{w_measurement})")
        details['measurement_exists'] = True
    elif measurement_exists:
        score += w_measurement * 0.5
        feedback_parts.append(f"~ Measurement exists but may predate task (+{int(w_measurement*0.5)})")
        details['measurement_exists'] = True
    else:
        feedback_parts.append(f"✗ No measurement markup found (+0)")
        details['measurement_exists'] = False
        # Early exit - no measurement means task not attempted
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    # ============================================================
    # CRITERION 2: Correct anatomical region (20 points)
    # ============================================================
    meas_location_str = result.get('measurement_location_mm', '')
    meas_location = parse_location_string(meas_location_str)
    details['measurement_location_mm'] = meas_location
    
    if meas_location and gt_porta_hepatis:
        distance_to_porta = calculate_distance(meas_location, gt_porta_hepatis)
        details['distance_to_porta_hepatis_mm'] = distance_to_porta
        
        # Accept measurements within 50mm of porta hepatis
        # (generous tolerance for anatomical variation)
        if distance_to_porta <= 30:
            score += w_region
            feedback_parts.append(f"✓ Measurement at porta hepatis ({distance_to_porta:.1f}mm away) (+{w_region})")
        elif distance_to_porta <= 50:
            partial = int(w_region * 0.7)
            score += partial
            feedback_parts.append(f"~ Measurement near porta hepatis ({distance_to_porta:.1f}mm away) (+{partial})")
        elif distance_to_porta <= 80:
            partial = int(w_region * 0.4)
            score += partial
            feedback_parts.append(f"~ Measurement in hepatic region ({distance_to_porta:.1f}mm from porta) (+{partial})")
        else:
            feedback_parts.append(f"✗ Measurement far from porta hepatis ({distance_to_porta:.1f}mm away) (+0)")
    else:
        # Can't verify location - give partial credit if measurement exists
        partial = int(w_region * 0.3)
        score += partial
        feedback_parts.append(f"~ Cannot verify anatomical location (+{partial})")
    
    # ============================================================
    # CRITERION 3: Diameter accuracy (25 points)
    # ============================================================
    measured_diameter = 0.0
    measured_diameter_str = result.get('measured_diameter_mm', '')
    
    # Try to get diameter from measurement or report
    if measured_diameter_str:
        try:
            measured_diameter = float(measured_diameter_str)
        except ValueError:
            pass
    
    if measured_diameter == 0:
        reported_diameter_str = result.get('reported_diameter_mm', '')
        if reported_diameter_str:
            try:
                measured_diameter = float(reported_diameter_str)
            except ValueError:
                pass
    
    details['measured_diameter_mm'] = measured_diameter
    
    if measured_diameter > 0:
        # Check if diameter is physiologically reasonable for CBD
        if min_physiological <= measured_diameter <= max_physiological:
            # Full points for reasonable CBD measurement
            score += w_diameter
            feedback_parts.append(f"✓ CBD diameter {measured_diameter:.1f}mm (physiologically reasonable) (+{w_diameter})")
            details['diameter_valid'] = True
        elif 1.0 <= measured_diameter < min_physiological:
            # Slightly too small - might be a small CBD or wrong structure
            partial = int(w_diameter * 0.5)
            score += partial
            feedback_parts.append(f"~ Diameter {measured_diameter:.1f}mm is small for CBD (+{partial})")
            details['diameter_valid'] = 'borderline_small'
        elif max_physiological < measured_diameter <= 20.0:
            # Slightly too large - might be dilated or wrong structure
            partial = int(w_diameter * 0.5)
            score += partial
            feedback_parts.append(f"~ Diameter {measured_diameter:.1f}mm is large (severely dilated or wrong structure?) (+{partial})")
            details['diameter_valid'] = 'borderline_large'
        else:
            # Way outside CBD range - likely wrong structure
            feedback_parts.append(f"✗ Diameter {measured_diameter:.1f}mm is outside CBD range ({min_physiological}-{max_physiological}mm) (+0)")
            details['diameter_valid'] = False
    else:
        feedback_parts.append(f"✗ No diameter measurement found (+0)")
        details['diameter_valid'] = False
    
    # ============================================================
    # CRITERION 4: Classification correct (15 points)
    # ============================================================
    reported_classification = result.get('reported_classification', '').strip()
    details['reported_classification'] = reported_classification
    
    if measured_diameter > 0:
        expected_classification = classify_cbd_diameter(measured_diameter)
        details['expected_classification'] = expected_classification
        
        if reported_classification:
            # Normalize classification strings for comparison
            reported_norm = reported_classification.lower().strip()
            expected_norm = expected_classification.lower()
            
            # Check for match (allow some variation in naming)
            classification_match = False
            if expected_norm in reported_norm or reported_norm in expected_norm:
                classification_match = True
            elif expected_norm == 'normal' and any(x in reported_norm for x in ['normal', 'wnl', 'unremarkable']):
                classification_match = True
            elif expected_norm == 'borderline' and any(x in reported_norm for x in ['borderline', 'mildly', 'mild']):
                classification_match = True
            elif expected_norm == 'dilated' and any(x in reported_norm for x in ['dilated', 'enlarged', 'abnormal', 'obstruct']):
                classification_match = True
            
            if classification_match:
                score += w_classification
                feedback_parts.append(f"✓ Classification '{reported_classification}' matches diameter ({expected_classification}) (+{w_classification})")
            else:
                # Partial credit for providing any classification
                partial = int(w_classification * 0.3)
                score += partial
                feedback_parts.append(f"~ Classification '{reported_classification}' doesn't match {measured_diameter:.1f}mm ({expected_classification}) (+{partial})")
        else:
            feedback_parts.append(f"✗ No classification provided (+0)")
    else:
        if reported_classification:
            partial = int(w_classification * 0.2)
            score += partial
            feedback_parts.append(f"~ Classification provided but no diameter to validate (+{partial})")
        else:
            feedback_parts.append(f"✗ No classification provided (+0)")
    
    # ============================================================
    # CRITERION 5: Anatomical level documented (10 points)
    # ============================================================
    reported_level = result.get('reported_anatomical_level', '').strip()
    details['reported_anatomical_level'] = reported_level
    
    if reported_level:
        # Check for valid anatomical level descriptions
        valid_levels = ['porta hepatis', 'portahepatis', 'hepatic', 'suprapancreatic', 
                       'intrapancreatic', 'pancreatic', 'hilum', 'hilar', 'hepatoduodenal']
        level_valid = any(level in reported_level.lower() for level in valid_levels)
        
        if level_valid:
            score += w_level
            feedback_parts.append(f"✓ Anatomical level documented: '{reported_level}' (+{w_level})")
        else:
            partial = int(w_level * 0.5)
            score += partial
            feedback_parts.append(f"~ Level documented but non-standard: '{reported_level}' (+{partial})")
    else:
        feedback_parts.append(f"✗ Anatomical level not documented (+0)")
    
    # ============================================================
    # CRITERION 6: Clinical interpretation (10 points)
    # ============================================================
    reported_interpretation = result.get('reported_interpretation', '').strip()
    details['reported_interpretation'] = reported_interpretation[:200] if reported_interpretation else ''
    
    if reported_interpretation:
        # Check for meaningful clinical content
        clinical_terms = ['obstruction', 'normal', 'dilat', 'stone', 'stricture', 
                         'choledo', 'biliary', 'duct', 'further', 'recommend', 
                         'suggest', 'consistent', 'concerning', 'unremarkable']
        has_clinical_content = any(term in reported_interpretation.lower() for term in clinical_terms)
        
        if has_clinical_content and len(reported_interpretation) > 20:
            score += w_interpretation
            feedback_parts.append(f"✓ Clinical interpretation provided (+{w_interpretation})")
        elif len(reported_interpretation) > 10:
            partial = int(w_interpretation * 0.5)
            score += partial
            feedback_parts.append(f"~ Brief interpretation provided (+{partial})")
        else:
            partial = int(w_interpretation * 0.2)
            score += partial
            feedback_parts.append(f"~ Minimal interpretation (+{partial})")
    else:
        feedback_parts.append(f"✗ No clinical interpretation provided (+0)")
    
    # ============================================================
    # CRITERION 7: Report completeness (5 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    if report_exists and report_created:
        # Check for required fields
        required_fields = ['diameter', 'classification', 'level', 'interpretation']
        fields_present = 0
        if measured_diameter > 0 or result.get('reported_diameter_mm'):
            fields_present += 1
        if reported_classification:
            fields_present += 1
        if reported_level:
            fields_present += 1
        if reported_interpretation:
            fields_present += 1
        
        if fields_present == 4:
            score += w_completeness
            feedback_parts.append(f"✓ Report complete with all fields (+{w_completeness})")
        elif fields_present >= 2:
            partial = int(w_completeness * (fields_present / 4))
            score += partial
            feedback_parts.append(f"~ Report has {fields_present}/4 fields (+{partial})")
        else:
            feedback_parts.append(f"✗ Report incomplete ({fields_present}/4 fields) (+0)")
    elif report_exists:
        partial = int(w_completeness * 0.5)
        score += partial
        feedback_parts.append(f"~ Report exists but may predate task (+{partial})")
    else:
        feedback_parts.append(f"✗ No report file created (+0)")
    
    # ============================================================
    # Final assessment
    # ============================================================
    # Key criteria for passing:
    # 1. Measurement exists
    # 2. Diameter is physiologically reasonable
    key_criteria_met = (
        details.get('measurement_exists', False) and
        details.get('diameter_valid', False) in [True, 'borderline_small', 'borderline_large']
    )
    
    passed = score >= 60 and key_criteria_met
    
    if passed:
        feedback_parts.insert(0, f"✓ PASSED (Score: {score}/100)")
    else:
        if not key_criteria_met:
            feedback_parts.insert(0, f"✗ FAILED - Key criteria not met (Score: {score}/100)")
        else:
            feedback_parts.insert(0, f"✗ FAILED - Score below threshold (Score: {score}/100)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }