#!/usr/bin/env python3
"""
Verifier for Tumor-to-Ventricle Proximity Assessment task.

VERIFICATION METRICS:
1. Distance accuracy - how close is agent's measurement to ground truth (35 pts)
2. Classification correct - Contact/Adjacent/Close/Distant (20 pts)
3. Measurement placed - ruler markup exists and was created during task (15 pts)
4. Ventricle component identification (10 pts)
5. Invasion assessment accuracy (10 pts)
6. Report completeness (10 pts)

Ground Truth: Computed from BraTS tumor segmentation and T2-based ventricle identification
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


def get_classification(distance_mm):
    """Get classification from distance value."""
    if distance_mm < 1.0:
        return "Contact"
    elif distance_mm <= 5.0:
        return "Adjacent"
    elif distance_mm <= 10.0:
        return "Close"
    else:
        return "Distant"


def normalize_classification(cls):
    """Normalize classification string for comparison."""
    if not cls:
        return ""
    cls_lower = cls.lower().strip()
    
    if cls_lower in ["contact", "invasion", "contact/invasion", "touching"]:
        return "Contact"
    elif cls_lower in ["adjacent", "near", "close proximity"]:
        return "Adjacent"
    elif cls_lower in ["close", "nearby"]:
        return "Close"
    elif cls_lower in ["distant", "far", "remote", "separated"]:
        return "Distant"
    
    return cls.strip().title()


def normalize_component(comp):
    """Normalize ventricle component name for comparison."""
    if not comp:
        return ""
    comp_lower = comp.lower().strip()
    
    if "frontal" in comp_lower or "front" in comp_lower:
        return "frontal horn"
    elif "body" in comp_lower or "central" in comp_lower:
        return "body"
    elif "atrium" in comp_lower or "trigone" in comp_lower:
        return "atrium"
    elif "temporal" in comp_lower:
        return "temporal horn"
    elif "occipital" in comp_lower:
        return "occipital horn"
    
    return comp_lower


def verify_tumor_ventricle_proximity(traj, env_info, task_info):
    """
    Verify tumor-to-ventricle proximity measurement task.
    
    Scoring (100 points total):
    - Distance accuracy: 35 points (within 5mm of ground truth)
    - Classification correct: 20 points
    - Measurement placed: 15 points
    - Ventricle component: 10 points
    - Invasion assessment: 10 points
    - Report completeness: 10 points
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
    
    distance_error_max = thresholds.get('distance_error_max_mm', 5.0)
    
    w_distance = weights.get('distance_accuracy', 35)
    w_classification = weights.get('classification_correct', 20)
    w_measurement = weights.get('measurement_placed', 15)
    w_component = weights.get('ventricle_component', 10)
    w_invasion = weights.get('invasion_assessment', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Load task result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/proximity_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/proximity_ground_truth.json", temp_gt.name)
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
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # Extract ground truth values
    gt_distance = gt_data.get('min_distance_mm', -1)
    gt_classification = gt_data.get('classification', '')
    gt_component = gt_data.get('nearest_ventricle_component', '')
    gt_invasion = gt_data.get('ventricular_invasion_suspected', False)
    
    details['gt_distance_mm'] = gt_distance
    details['gt_classification'] = gt_classification
    details['gt_component'] = gt_component
    details['gt_invasion'] = gt_invasion
    
    # ================================================================
    # CRITERION 1: Measurement Placed (15 points)
    # ================================================================
    measurement_exists = result.get('measurement_exists', False)
    file_created = result.get('file_created_during_task', False)
    
    if measurement_exists and file_created:
        score += w_measurement
        feedback_parts.append(f"✓ Measurement created during task (+{w_measurement})")
    elif measurement_exists:
        score += w_measurement * 0.6  # Partial credit
        feedback_parts.append(f"~ Measurement exists but may be pre-existing (+{int(w_measurement * 0.6)})")
    else:
        feedback_parts.append("✗ No measurement markup found")
    
    details['measurement_exists'] = measurement_exists
    details['file_created_during_task'] = file_created
    
    # ================================================================
    # CRITERION 2: Distance Accuracy (35 points)
    # ================================================================
    agent_distance = 0.0
    
    # Try measured distance first, then reported
    measured_str = result.get('measured_distance_mm', '')
    reported_str = result.get('reported_distance_mm', '')
    
    try:
        if measured_str:
            agent_distance = float(measured_str)
        elif reported_str:
            agent_distance = float(reported_str)
    except (ValueError, TypeError):
        agent_distance = 0.0
    
    details['agent_distance_mm'] = agent_distance
    
    distance_accurate = False
    if gt_distance >= 0 and agent_distance > 0:
        distance_error = abs(agent_distance - gt_distance)
        details['distance_error_mm'] = round(distance_error, 2)
        
        if distance_error <= distance_error_max:
            score += w_distance
            distance_accurate = True
            feedback_parts.append(f"✓ Distance accurate: {agent_distance:.1f}mm (GT: {gt_distance:.1f}mm, error: {distance_error:.1f}mm) (+{w_distance})")
        elif distance_error <= distance_error_max * 2:
            partial = int(w_distance * 0.5)
            score += partial
            feedback_parts.append(f"~ Distance partially accurate: {agent_distance:.1f}mm (GT: {gt_distance:.1f}mm, error: {distance_error:.1f}mm) (+{partial})")
        else:
            feedback_parts.append(f"✗ Distance inaccurate: {agent_distance:.1f}mm (GT: {gt_distance:.1f}mm, error: {distance_error:.1f}mm)")
    elif agent_distance > 0:
        feedback_parts.append(f"? Distance measured ({agent_distance:.1f}mm) but no ground truth for comparison")
        score += int(w_distance * 0.3)
    else:
        feedback_parts.append("✗ No distance measurement found")
    
    # ================================================================
    # CRITERION 3: Classification Correct (20 points)
    # ================================================================
    agent_classification = normalize_classification(result.get('reported_classification', ''))
    
    # If no reported classification, infer from distance
    if not agent_classification and agent_distance > 0:
        agent_classification = get_classification(agent_distance)
        details['classification_inferred'] = True
    
    details['agent_classification'] = agent_classification
    
    gt_classification_norm = normalize_classification(gt_classification)
    
    if agent_classification and gt_classification_norm:
        if agent_classification == gt_classification_norm:
            score += w_classification
            feedback_parts.append(f"✓ Classification correct: {agent_classification} (+{w_classification})")
        else:
            # Check if one category off
            categories = ["Contact", "Adjacent", "Close", "Distant"]
            try:
                agent_idx = categories.index(agent_classification)
                gt_idx = categories.index(gt_classification_norm)
                if abs(agent_idx - gt_idx) == 1:
                    partial = int(w_classification * 0.5)
                    score += partial
                    feedback_parts.append(f"~ Classification close: {agent_classification} (GT: {gt_classification_norm}) (+{partial})")
                else:
                    feedback_parts.append(f"✗ Classification incorrect: {agent_classification} (GT: {gt_classification_norm})")
            except ValueError:
                feedback_parts.append(f"✗ Classification incorrect: {agent_classification} (GT: {gt_classification_norm})")
    elif agent_classification:
        feedback_parts.append(f"? Classification provided ({agent_classification}) but no ground truth")
        score += int(w_classification * 0.3)
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ================================================================
    # CRITERION 4: Ventricle Component Identification (10 points)
    # ================================================================
    agent_component = normalize_component(result.get('reported_ventricle_component', ''))
    gt_component_norm = normalize_component(gt_component)
    
    details['agent_component'] = agent_component
    
    if agent_component and gt_component_norm:
        if agent_component == gt_component_norm:
            score += w_component
            feedback_parts.append(f"✓ Ventricle component correct: {agent_component} (+{w_component})")
        elif agent_component in ["frontal horn", "body", "atrium", "temporal horn", "occipital horn"]:
            # Valid but incorrect
            partial = int(w_component * 0.3)
            score += partial
            feedback_parts.append(f"~ Ventricle component identified but incorrect: {agent_component} (GT: {gt_component_norm}) (+{partial})")
        else:
            feedback_parts.append(f"✗ Ventricle component incorrect: {agent_component} (GT: {gt_component_norm})")
    elif agent_component:
        score += int(w_component * 0.5)
        feedback_parts.append(f"? Ventricle component provided: {agent_component}")
    else:
        feedback_parts.append("✗ Ventricle component not identified")
    
    # ================================================================
    # CRITERION 5: Invasion Assessment (10 points)
    # ================================================================
    agent_invasion_str = result.get('reported_invasion_suspected', '')
    agent_invasion = None
    
    if agent_invasion_str.lower() in ['true', 'yes', '1']:
        agent_invasion = True
    elif agent_invasion_str.lower() in ['false', 'no', '0']:
        agent_invasion = False
    
    details['agent_invasion'] = agent_invasion
    
    if agent_invasion is not None:
        if agent_invasion == gt_invasion:
            score += w_invasion
            feedback_parts.append(f"✓ Invasion assessment correct: {agent_invasion} (+{w_invasion})")
        else:
            feedback_parts.append(f"✗ Invasion assessment incorrect: {agent_invasion} (GT: {gt_invasion})")
    else:
        feedback_parts.append("✗ Invasion assessment not provided")
    
    # ================================================================
    # CRITERION 6: Report Completeness (10 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        # Check how many required fields are present
        required_fields = ['reported_distance_mm', 'reported_classification', 
                          'reported_ventricle_component', 'reported_invasion_suspected']
        present_fields = sum(1 for f in required_fields if result.get(f, ''))
        
        if present_fields >= 3:
            score += w_report
            feedback_parts.append(f"✓ Report complete ({present_fields}/4 fields) (+{w_report})")
        elif present_fields >= 1:
            partial = int(w_report * present_fields / 4)
            score += partial
            feedback_parts.append(f"~ Report partial ({present_fields}/4 fields) (+{partial})")
        else:
            feedback_parts.append("✗ Report exists but missing required fields")
    else:
        feedback_parts.append("✗ No report file created")
    
    details['report_exists'] = report_exists
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    # Key criteria: measurement placed AND (distance accurate OR classification correct)
    key_criteria_met = measurement_exists and (distance_accurate or agent_classification == gt_classification_norm)
    passed = score >= 60 and key_criteria_met
    
    if passed:
        feedback_parts.insert(0, f"✓ PASSED with score {score}/100")
    else:
        if not key_criteria_met:
            feedback_parts.insert(0, f"✗ FAILED - Key criteria not met (score: {score}/100)")
        else:
            feedback_parts.insert(0, f"✗ FAILED - Score below threshold (score: {score}/100)")
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }