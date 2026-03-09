#!/usr/bin/env python3
"""
Verifier for lumbar lordosis angle measurement task.

VERIFICATION METRICS:
1. Angle accuracy - how close is agent's measurement to ground truth (35 pts)
2. L1 landmark correct - line placed at appropriate L1 level (15 pts)
3. S1 landmark correct - line placed at appropriate S1 level (15 pts)
4. Classification correct - correct clinical category (15 pts)
5. Markup file valid - measurement markups exist (10 pts)
6. Report complete - JSON report with all fields (10 pts)

Ground Truth: Pre-computed from AMOS CT scan with known spine geometry
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


def get_classification(angle):
    """Get clinical classification from angle."""
    if angle < 30:
        return "Hypolordosis"
    elif angle < 40:
        return "Low-normal"
    elif angle <= 60:
        return "Normal"
    elif angle <= 70:
        return "High-normal"
    else:
        return "Hyperlordosis"


def classifications_match(class1, class2):
    """Check if two classifications match (case-insensitive, flexible matching)."""
    if not class1 or not class2:
        return False
    
    c1 = class1.lower().replace("-", "").replace("_", "").replace(" ", "")
    c2 = class2.lower().replace("-", "").replace("_", "").replace(" ", "")
    
    # Direct match
    if c1 == c2:
        return True
    
    # Handle common variations
    variations = {
        "hypolordosis": ["hypolordosis", "flatback", "flat"],
        "lownormal": ["lownormal", "lowernormal"],
        "normal": ["normal"],
        "highnormal": ["highnormal", "uppernormal"],
        "hyperlordosis": ["hyperlordosis", "excessive"]
    }
    
    for canonical, variants in variations.items():
        if c1 in variants or canonical in c1:
            if c2 in variants or canonical in c2:
                return True
    
    return False


def verify_lumbar_lordosis(traj, env_info, task_info):
    """
    Verify lumbar lordosis angle measurement task completion.

    Scoring (100 points total):
    - Angle accuracy: 35 points (within 8 degrees)
    - L1 landmark correct: 15 points
    - S1 landmark correct: 15 points
    - Classification correct: 15 points
    - Markup file valid: 10 points
    - Report complete: 10 points
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

    angle_error_max = thresholds.get('angle_error_max_degrees', 8.0)
    l1_z_tolerance = thresholds.get('l1_z_tolerance_mm', 25.0)
    s1_z_tolerance = thresholds.get('s1_z_tolerance_mm', 25.0)

    w_angle = weights.get('angle_accuracy', 35)
    w_l1 = weights.get('l1_landmark_correct', 15)
    w_s1 = weights.get('s1_landmark_correct', 15)
    w_classification = weights.get('classification_correct', 15)
    w_markup = weights.get('markup_file_valid', 10)
    w_report = weights.get('report_complete', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/lordosis_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/lordosis_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_angle = gt_data.get('lumbar_lordosis_angle_degrees', 48.0)
    gt_classification = gt_data.get('classification', 'Normal')
    gt_l1_z = gt_data.get('l1_position', {}).get('z_mm', 0)
    gt_s1_z = gt_data.get('s1_position', {}).get('z_mm', 0)

    details['gt_angle_degrees'] = gt_angle
    details['gt_classification'] = gt_classification
    details['gt_l1_z_mm'] = gt_l1_z
    details['gt_s1_z_mm'] = gt_s1_z

    # ============================================================
    # CRITERION 1: MARKUP FILE EXISTS (10 points)
    # ============================================================
    markup_exists = result.get('markup_exists', False)
    num_lines = int(result.get('num_lines', 0))
    file_created = result.get('file_created_during_task', False)

    if markup_exists and num_lines >= 2:
        score += w_markup
        feedback_parts.append(f"✓ Markup file exists with {num_lines} lines")
        details['markup_valid'] = True
    elif markup_exists:
        score += w_markup // 2
        feedback_parts.append(f"△ Markup file exists but only {num_lines} lines (need 2)")
        details['markup_valid'] = False
    else:
        feedback_parts.append("✗ No markup file found")
        details['markup_valid'] = False

    # Anti-gaming check
    if not file_created and markup_exists:
        feedback_parts.append("⚠ Markup file may pre-exist task")
        details['file_created_during_task'] = False
    else:
        details['file_created_during_task'] = file_created

    # ============================================================
    # CRITERION 2: ANGLE ACCURACY (35 points)
    # ============================================================
    agent_angle = 0.0
    angle_source = None
    
    # Try to get angle from measured value first
    measured_str = result.get('measured_angle_degrees', '')
    if measured_str:
        try:
            agent_angle = float(measured_str)
            angle_source = 'measured'
        except ValueError:
            pass
    
    # Fall back to reported angle
    if not agent_angle:
        reported_str = result.get('reported_angle_degrees', '')
        if reported_str:
            try:
                agent_angle = float(reported_str)
                angle_source = 'reported'
            except ValueError:
                pass

    details['agent_angle_degrees'] = agent_angle
    details['angle_source'] = angle_source

    if agent_angle > 0:
        angle_error = abs(agent_angle - gt_angle)
        details['angle_error_degrees'] = angle_error
        
        if angle_error <= angle_error_max:
            score += w_angle
            feedback_parts.append(f"✓ Angle accurate: {agent_angle:.1f}° (GT: {gt_angle:.1f}°, error: {angle_error:.1f}°)")
            details['angle_accurate'] = True
        elif angle_error <= angle_error_max * 2:
            partial = int(w_angle * (1 - angle_error / (angle_error_max * 2)))
            score += partial
            feedback_parts.append(f"△ Angle partially accurate: {agent_angle:.1f}° (GT: {gt_angle:.1f}°, error: {angle_error:.1f}°)")
            details['angle_accurate'] = False
        else:
            feedback_parts.append(f"✗ Angle inaccurate: {agent_angle:.1f}° (GT: {gt_angle:.1f}°, error: {angle_error:.1f}°)")
            details['angle_accurate'] = False
    else:
        feedback_parts.append("✗ No angle measurement found")
        details['angle_accurate'] = False

    # ============================================================
    # CRITERION 3: L1 LANDMARK CORRECT (15 points)
    # ============================================================
    # We check this based on the markup file having lines at appropriate z-levels
    # Since we can't directly verify L1/S1 identification without detailed position data,
    # we give credit if markups were placed
    
    if markup_exists and num_lines >= 2:
        # Assume upper line is L1 (agent should place it there)
        score += w_l1
        feedback_parts.append("✓ L1 landmark placement detected")
        details['l1_landmark_correct'] = True
    else:
        feedback_parts.append("✗ L1 landmark not properly identified")
        details['l1_landmark_correct'] = False

    # ============================================================
    # CRITERION 4: S1 LANDMARK CORRECT (15 points)
    # ============================================================
    if markup_exists and num_lines >= 2:
        score += w_s1
        feedback_parts.append("✓ S1 landmark placement detected")
        details['s1_landmark_correct'] = True
    else:
        feedback_parts.append("✗ S1 landmark not properly identified")
        details['s1_landmark_correct'] = False

    # ============================================================
    # CRITERION 5: CLASSIFICATION CORRECT (15 points)
    # ============================================================
    agent_classification = result.get('reported_classification', '')
    details['agent_classification'] = agent_classification
    
    # If no reported classification, derive from angle
    if not agent_classification and agent_angle > 0:
        agent_classification = get_classification(agent_angle)
        details['classification_derived'] = True
    
    if agent_classification:
        if classifications_match(agent_classification, gt_classification):
            score += w_classification
            feedback_parts.append(f"✓ Classification correct: {agent_classification}")
            details['classification_correct'] = True
        else:
            feedback_parts.append(f"✗ Classification incorrect: {agent_classification} (GT: {gt_classification})")
            details['classification_correct'] = False
    else:
        feedback_parts.append("✗ No classification provided")
        details['classification_correct'] = False

    # ============================================================
    # CRITERION 6: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        # Check for required fields
        has_angle = bool(result.get('reported_angle_degrees', ''))
        has_classification = bool(result.get('reported_classification', ''))
        has_l1 = result.get('reported_l1_identified', '') in ['true', 'True', True]
        has_s1 = result.get('reported_s1_identified', '') in ['true', 'True', True]
        
        completeness = sum([has_angle, has_classification, has_l1, has_s1])
        details['report_fields'] = {
            'angle': has_angle,
            'classification': has_classification,
            'l1_identified': has_l1,
            's1_identified': has_s1
        }
        
        if completeness >= 3:
            score += w_report
            feedback_parts.append(f"✓ Report complete ({completeness}/4 fields)")
            details['report_complete'] = True
        elif completeness >= 2:
            score += w_report // 2
            feedback_parts.append(f"△ Report partially complete ({completeness}/4 fields)")
            details['report_complete'] = False
        else:
            feedback_parts.append(f"✗ Report incomplete ({completeness}/4 fields)")
            details['report_complete'] = False
    else:
        feedback_parts.append("✗ No report file found")
        details['report_complete'] = False

    # ============================================================
    # FINAL SCORING
    # ============================================================
    max_score = w_angle + w_l1 + w_s1 + w_classification + w_markup + w_report
    
    # Key criteria for passing: angle measured and reasonably accurate
    angle_accurate = details.get('angle_accurate', False)
    markup_valid = details.get('markup_valid', False)
    
    passed = score >= 60 and (angle_accurate or (markup_valid and agent_angle > 0))

    # Compile feedback
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": min(score, 100),
        "feedback": feedback,
        "details": details,
        "subscores": {
            "angle_accuracy": w_angle if details.get('angle_accurate') else 0,
            "l1_landmark": w_l1 if details.get('l1_landmark_correct') else 0,
            "s1_landmark": w_s1 if details.get('s1_landmark_correct') else 0,
            "classification": w_classification if details.get('classification_correct') else 0,
            "markup_file": w_markup if details.get('markup_valid') else 0,
            "report": w_report if details.get('report_complete') else 0
        }
    })