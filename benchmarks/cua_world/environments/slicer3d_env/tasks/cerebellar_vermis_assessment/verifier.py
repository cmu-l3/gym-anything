#!/usr/bin/env python3
"""
Verifier for cerebellar vermis measurement task.

VERIFICATION CRITERIA (100 points total):
1. AP Diameter Measurement: 30 points (within 5mm of reference)
2. Measurement Location Valid: 20 points (endpoints in posterior fossa/midline)
3. Sagittal View Evidence: 15 points (trajectory shows navigation)
4. Markup File Saved: 10 points
5. Report AP Diameter: 10 points
6. Report Morphology: 10 points
7. Report Classification: 5 points

Pass threshold: 60 points with AP measurement achieved
"""

import json
import os
import sys
import math
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_cerebellar_vermis_assessment(traj, env_info, task_info):
    """
    Verify cerebellar vermis measurement task completion.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int), 'feedback' (str)
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
    min_score = thresholds.get('min_score', 60)
    
    # Scoring weights
    w_diameter = weights.get('ap_diameter_measurement', 30)
    w_location = weights.get('measurement_location_valid', 20)
    w_sagittal = weights.get('sagittal_view_used', 15)
    w_markup = weights.get('markup_file_saved', 10)
    w_report_ap = weights.get('report_ap_diameter', 10)
    w_report_morph = weights.get('report_morphology', 10)
    w_report_class = weights.get('report_classification', 5)
    
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ========================================
    # Load task results from container
    # ========================================
    result_data = {}
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vermis_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
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
    
    details['result_data'] = result_data
    
    # ========================================
    # Load ground truth
    # ========================================
    ground_truth = {}
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/vermis_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load ground truth: {e}")
        # Use reasonable defaults
        ground_truth = {
            'reference_ap_diameter_mm': 30.0,
            'measurement_tolerance_mm': 5.0,
            'expected_classification': 'Normal',
            'expected_region': {
                'x_min': -30, 'x_max': 30,
                'z_min': -100, 'z_max': 0
            }
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    details['ground_truth'] = ground_truth
    ref_ap = ground_truth.get('reference_ap_diameter_mm', 30.0)
    tolerance = ground_truth.get('measurement_tolerance_mm', diameter_error_max)
    expected_region = ground_truth.get('expected_region', {})
    expected_classification = ground_truth.get('expected_classification', 'Normal')
    
    # ========================================
    # Check 1: Markup File Saved (10 points)
    # ========================================
    measurement_exists = result_data.get('measurement_file_exists', False)
    measurement_valid = result_data.get('measurement_file_valid', False)
    measurement_created = result_data.get('measurement_created_during_task', False)
    
    if measurement_exists and measurement_valid:
        if measurement_created:
            score += w_markup
            feedback_parts.append(f"✓ Measurement markup file saved during task ({w_markup} pts)")
        else:
            score += w_markup // 2
            feedback_parts.append(f"△ Measurement file exists but may be pre-existing ({w_markup // 2} pts)")
    elif measurement_exists:
        score += w_markup // 3
        feedback_parts.append(f"△ Measurement file exists but invalid JSON ({w_markup // 3} pts)")
    else:
        feedback_parts.append("✗ No measurement markup file found (0 pts)")
    
    # ========================================
    # Check 2: AP Diameter Measurement (30 points)
    # ========================================
    measured_distance_str = result_data.get('measured_distance_mm', '')
    measured_distance = None
    ap_measurement_correct = False
    
    if measured_distance_str:
        try:
            measured_distance = float(measured_distance_str)
            details['measured_ap_diameter_mm'] = measured_distance
            
            error = abs(measured_distance - ref_ap)
            details['measurement_error_mm'] = error
            
            if error <= tolerance:
                score += w_diameter
                ap_measurement_correct = True
                feedback_parts.append(f"✓ AP diameter accurate: {measured_distance:.1f}mm (ref: {ref_ap:.1f}mm, error: {error:.1f}mm) ({w_diameter} pts)")
            elif error <= tolerance * 2:
                score += w_diameter // 2
                feedback_parts.append(f"△ AP diameter close: {measured_distance:.1f}mm (ref: {ref_ap:.1f}mm, error: {error:.1f}mm) ({w_diameter // 2} pts)")
            else:
                feedback_parts.append(f"✗ AP diameter inaccurate: {measured_distance:.1f}mm (ref: {ref_ap:.1f}mm, error: {error:.1f}mm) (0 pts)")
        except ValueError:
            feedback_parts.append(f"✗ Could not parse measured distance: {measured_distance_str} (0 pts)")
    else:
        feedback_parts.append("✗ No measurement distance found (0 pts)")
    
    # ========================================
    # Check 3: Measurement Location Valid (20 points)
    # ========================================
    point1_str = result_data.get('measurement_point1', '')
    point2_str = result_data.get('measurement_point2', '')
    
    location_valid = False
    if point1_str and point2_str and point1_str not in ['[]', '']:
        try:
            # Parse point coordinates
            point1 = eval(point1_str) if isinstance(point1_str, str) else point1_str
            point2 = eval(point2_str) if isinstance(point2_str, str) else point2_str
            
            if isinstance(point1, list) and isinstance(point2, list) and len(point1) >= 3 and len(point2) >= 3:
                details['measurement_points'] = {'point1': point1, 'point2': point2}
                
                # Check if points are near midline (X near 0 in RAS coordinates)
                midline_tolerance = 40  # mm
                p1_midline = abs(point1[0]) < midline_tolerance
                p2_midline = abs(point2[0]) < midline_tolerance
                
                # Check if points are in posterior/inferior region
                # In RAS: S (superior) is positive, so inferior is negative or low positive
                # Posterior fossa is typically in inferior brain
                p1_inferior = point1[2] < 50  # Relative check
                p2_inferior = point2[2] < 50
                
                if p1_midline and p2_midline:
                    if p1_inferior or p2_inferior:
                        score += w_location
                        location_valid = True
                        feedback_parts.append(f"✓ Measurement in cerebellar/midline region ({w_location} pts)")
                    else:
                        score += w_location // 2
                        feedback_parts.append(f"△ Measurement near midline but region uncertain ({w_location // 2} pts)")
                else:
                    score += w_location // 4
                    feedback_parts.append(f"△ Measurement points not clearly at midline ({w_location // 4} pts)")
            else:
                feedback_parts.append("✗ Invalid point coordinates format (0 pts)")
                
        except Exception as e:
            logger.warning(f"Could not validate measurement location: {e}")
            feedback_parts.append(f"✗ Could not validate measurement location (0 pts)")
    else:
        feedback_parts.append("✗ No measurement point coordinates found (0 pts)")
    
    # ========================================
    # Check 4: Sagittal View Evidence (15 points)
    # ========================================
    # Check trajectory for activity indicating navigation
    trajectory_length = 0
    if traj:
        if isinstance(traj, dict):
            trajectory_length = len(traj.get('steps', []))
        elif isinstance(traj, list):
            trajectory_length = len(traj)
    
    details['trajectory_length'] = trajectory_length
    
    if trajectory_length >= 10:
        score += w_sagittal
        feedback_parts.append(f"✓ Substantial trajectory activity ({trajectory_length} steps) ({w_sagittal} pts)")
    elif trajectory_length >= 5:
        score += w_sagittal * 2 // 3
        feedback_parts.append(f"△ Moderate trajectory activity ({trajectory_length} steps) ({w_sagittal * 2 // 3} pts)")
    elif trajectory_length >= 2:
        score += w_sagittal // 3
        feedback_parts.append(f"△ Minimal trajectory activity ({trajectory_length} steps) ({w_sagittal // 3} pts)")
    elif measurement_exists:
        # Give partial credit if measurement exists despite short trajectory
        score += w_sagittal // 4
        feedback_parts.append(f"△ Short trajectory but measurement exists ({w_sagittal // 4} pts)")
    else:
        feedback_parts.append("✗ Insufficient trajectory activity (0 pts)")
    
    # ========================================
    # Check 5: Report AP Diameter (10 points)
    # ========================================
    report_has_ap = result_data.get('report_has_ap_diameter', False)
    reported_ap_str = result_data.get('reported_ap_diameter', '')
    report_created = result_data.get('report_created_during_task', False)
    
    if report_has_ap and reported_ap_str:
        try:
            reported_ap_val = float(reported_ap_str)
            # Check if reported value is reasonable
            ref_check = measured_distance if measured_distance else ref_ap
            if abs(reported_ap_val - ref_check) / max(ref_check, 1) < 0.5:
                if report_created:
                    score += w_report_ap
                    feedback_parts.append(f"✓ Report contains AP diameter: {reported_ap_val}mm ({w_report_ap} pts)")
                else:
                    score += w_report_ap // 2
                    feedback_parts.append(f"△ Report AP diameter (may be pre-existing): {reported_ap_val}mm ({w_report_ap // 2} pts)")
            else:
                score += w_report_ap // 2
                feedback_parts.append(f"△ Report AP diameter inconsistent: {reported_ap_val}mm ({w_report_ap // 2} pts)")
        except:
            score += w_report_ap // 3
            feedback_parts.append(f"△ Report has AP diameter but unparseable ({w_report_ap // 3} pts)")
    elif result_data.get('report_file_exists', False):
        score += w_report_ap // 4
        feedback_parts.append(f"△ Report exists but no AP diameter found ({w_report_ap // 4} pts)")
    else:
        feedback_parts.append("✗ No report file with AP diameter (0 pts)")
    
    # ========================================
    # Check 6: Report Morphology (10 points)
    # ========================================
    report_has_morph = result_data.get('report_has_morphology', False)
    reported_morph = result_data.get('reported_morphology', '')
    
    if report_has_morph and reported_morph:
        score += w_report_morph
        feedback_parts.append(f"✓ Report contains morphology assessment ({w_report_morph} pts)")
    elif result_data.get('report_file_exists', False):
        score += w_report_morph // 4
        feedback_parts.append(f"△ Report exists but no morphology assessment ({w_report_morph // 4} pts)")
    else:
        feedback_parts.append("✗ No morphology assessment in report (0 pts)")
    
    # ========================================
    # Check 7: Report Classification (5 points)
    # ========================================
    reported_class = result_data.get('reported_classification', '')
    
    if reported_class:
        reported_lower = reported_class.lower().strip()
        expected_lower = expected_classification.lower()
        
        # Check for match
        valid_classifications = ['normal', 'borderline', 'hypoplastic', 'abnormal']
        
        if expected_lower in reported_lower or reported_lower in expected_lower:
            score += w_report_class
            feedback_parts.append(f"✓ Classification matches expected: {reported_class} ({w_report_class} pts)")
        elif any(c in reported_lower for c in valid_classifications):
            score += w_report_class * 2 // 3
            feedback_parts.append(f"△ Valid classification provided: {reported_class} (expected: {expected_classification}) ({w_report_class * 2 // 3} pts)")
        else:
            score += w_report_class // 2
            feedback_parts.append(f"△ Non-standard classification: {reported_class} ({w_report_class // 2} pts)")
    else:
        feedback_parts.append("✗ No classification in report (0 pts)")
    
    # ========================================
    # Final assessment
    # ========================================
    details['score'] = score
    details['max_score'] = max_score
    details['ap_measurement_correct'] = ap_measurement_correct
    
    # Pass criteria: 60+ points AND AP measurement achieved (within tolerance)
    passed = score >= min_score and ap_measurement_correct
    
    if passed:
        feedback_parts.insert(0, f"PASSED: Score {score}/{max_score}")
    else:
        if not ap_measurement_correct:
            feedback_parts.insert(0, f"FAILED: Score {score}/{max_score} (AP measurement accuracy required)")
        else:
            feedback_parts.insert(0, f"FAILED: Score {score}/{max_score} (need {min_score}+)")
    
    feedback = "\n".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }