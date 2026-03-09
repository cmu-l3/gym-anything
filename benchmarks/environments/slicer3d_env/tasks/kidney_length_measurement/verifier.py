#!/usr/bin/env python3
"""
Verifier for Bilateral Kidney Length Measurement task.

VERIFICATION METRICS:
1. Right kidney length accuracy (25 points) - within 1.0 cm of ground truth
2. Left kidney length accuracy (25 points) - within 1.0 cm of ground truth
3. Size classification (15 points) - correct Small/Normal/Large for both
4. Asymmetry assessment (10 points) - correct Normal/Significant
5. Measurements saved (10 points) - both markup files exist and created during task
6. Report completeness (10 points) - JSON with all required fields
7. Clinical interpretation (5 points) - reasonable clinical comment

Pass threshold: 60 points with at least one kidney measurement accurate
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


def classify_kidney_size(length_cm):
    """Classify kidney size based on length in cm."""
    if length_cm < 9.0:
        return "Small"
    elif length_cm <= 12.0:
        return "Normal"
    else:
        return "Large"


def classify_asymmetry(diff_cm):
    """Classify asymmetry based on difference in cm."""
    if diff_cm >= 1.5:
        return "Significant"
    else:
        return "Normal"


def verify_kidney_length_measurement(traj, env_info, task_info):
    """
    Verify bilateral kidney length measurement task completion.
    
    Scoring (100 points total):
    - Right kidney length accuracy: 25 points
    - Left kidney length accuracy: 25 points
    - Size classification: 15 points
    - Asymmetry assessment: 10 points
    - Measurements saved: 10 points
    - Report completeness: 10 points
    - Clinical interpretation: 5 points
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
    clinical = metadata.get('clinical_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    length_error_max = thresholds.get('length_error_max_cm', 1.0)
    small_max = clinical.get('small_max_cm', 9.0)
    normal_max = clinical.get('normal_max_cm', 12.0)
    asymmetry_significant = clinical.get('asymmetry_significant_cm', 1.5)
    
    w_right = weights.get('right_kidney_length', 25)
    w_left = weights.get('left_kidney_length', 25)
    w_classification = weights.get('size_classification', 15)
    w_asymmetry = weights.get('asymmetry_assessment', 10)
    w_measurements = weights.get('measurements_saved', 10)
    w_report = weights.get('report_completeness', 10)
    w_interpretation = weights.get('clinical_interpretation', 5)
    
    # ============================================================
    # Load result JSON from container
    # ============================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/kidney_task_result.json", temp_result.name)
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
    
    # ============================================================
    # Load ground truth
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/kidney_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_right = gt_data.get('right_kidney', {})
    gt_left = gt_data.get('left_kidney', {})
    gt_asymmetry = gt_data.get('asymmetry', {})
    
    gt_right_length = gt_right.get('length_cm', 0)
    gt_left_length = gt_left.get('length_cm', 0)
    gt_right_class = gt_right.get('classification', '')
    gt_left_class = gt_left.get('classification', '')
    gt_asymmetry_diff = gt_asymmetry.get('difference_cm', 0)
    gt_asymmetry_assessment = gt_asymmetry.get('assessment', '')
    
    # ============================================================
    # Initialize scoring
    # ============================================================
    score = 0
    feedback_parts = []
    details = {
        "ground_truth": {
            "right_kidney_cm": gt_right_length,
            "left_kidney_cm": gt_left_length,
            "right_classification": gt_right_class,
            "left_classification": gt_left_class,
            "asymmetry_cm": gt_asymmetry_diff,
            "asymmetry_assessment": gt_asymmetry_assessment
        }
    }
    
    # ============================================================
    # Extract agent's measurements
    # ============================================================
    right_data = result.get('right_kidney', {})
    left_data = result.get('left_kidney', {})
    report_data = result.get('report', {})
    
    agent_right_length = 0.0
    agent_left_length = 0.0
    
    # Try to get from measurement files
    try:
        right_str = right_data.get('measured_length_cm', '')
        if right_str:
            agent_right_length = float(right_str)
    except (ValueError, TypeError):
        pass
    
    try:
        left_str = left_data.get('measured_length_cm', '')
        if left_str:
            agent_left_length = float(left_str)
    except (ValueError, TypeError):
        pass
    
    # Also try from report
    try:
        if agent_right_length == 0:
            reported = report_data.get('reported_right_cm', '')
            if reported:
                agent_right_length = float(reported)
    except (ValueError, TypeError):
        pass
    
    try:
        if agent_left_length == 0:
            reported = report_data.get('reported_left_cm', '')
            if reported:
                agent_left_length = float(reported)
    except (ValueError, TypeError):
        pass
    
    details["agent_measurements"] = {
        "right_kidney_cm": agent_right_length,
        "left_kidney_cm": agent_left_length
    }
    
    # ============================================================
    # CRITERION 1: Right kidney length accuracy (25 points)
    # ============================================================
    right_accurate = False
    if agent_right_length > 0 and gt_right_length > 0:
        right_error = abs(agent_right_length - gt_right_length)
        details["right_kidney_error_cm"] = round(right_error, 2)
        
        if right_error <= length_error_max:
            score += w_right
            right_accurate = True
            feedback_parts.append(f"✓ Right kidney: {agent_right_length:.1f}cm (error: {right_error:.1f}cm)")
        elif right_error <= length_error_max * 2:
            score += w_right // 2
            feedback_parts.append(f"~ Right kidney: {agent_right_length:.1f}cm (error: {right_error:.1f}cm, partial credit)")
        else:
            feedback_parts.append(f"✗ Right kidney: {agent_right_length:.1f}cm (error: {right_error:.1f}cm exceeds {length_error_max}cm)")
    else:
        if agent_right_length == 0:
            feedback_parts.append("✗ Right kidney: No measurement found")
        else:
            feedback_parts.append("✗ Right kidney: Ground truth not available")
    
    # ============================================================
    # CRITERION 2: Left kidney length accuracy (25 points)
    # ============================================================
    left_accurate = False
    if agent_left_length > 0 and gt_left_length > 0:
        left_error = abs(agent_left_length - gt_left_length)
        details["left_kidney_error_cm"] = round(left_error, 2)
        
        if left_error <= length_error_max:
            score += w_left
            left_accurate = True
            feedback_parts.append(f"✓ Left kidney: {agent_left_length:.1f}cm (error: {left_error:.1f}cm)")
        elif left_error <= length_error_max * 2:
            score += w_left // 2
            feedback_parts.append(f"~ Left kidney: {agent_left_length:.1f}cm (error: {left_error:.1f}cm, partial credit)")
        else:
            feedback_parts.append(f"✗ Left kidney: {agent_left_length:.1f}cm (error: {left_error:.1f}cm exceeds {length_error_max}cm)")
    else:
        if agent_left_length == 0:
            feedback_parts.append("✗ Left kidney: No measurement found")
        else:
            feedback_parts.append("✗ Left kidney: Ground truth not available")
    
    # ============================================================
    # CRITERION 3: Size classification (15 points)
    # ============================================================
    # Load agent's report for classification
    agent_report = {}
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_kidney_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    agent_right_class = agent_report.get('right_kidney', {}).get('classification', '')
    agent_left_class = agent_report.get('left_kidney', {}).get('classification', '')
    
    # Also derive classification from measurements if not in report
    if not agent_right_class and agent_right_length > 0:
        agent_right_class = classify_kidney_size(agent_right_length)
    if not agent_left_class and agent_left_length > 0:
        agent_left_class = classify_kidney_size(agent_left_length)
    
    classification_correct = 0
    if agent_right_class.lower() == gt_right_class.lower():
        classification_correct += 1
    if agent_left_class.lower() == gt_left_class.lower():
        classification_correct += 1
    
    if classification_correct == 2:
        score += w_classification
        feedback_parts.append("✓ Size classification: Both correct")
    elif classification_correct == 1:
        score += w_classification // 2
        feedback_parts.append("~ Size classification: One correct")
    else:
        feedback_parts.append("✗ Size classification: Incorrect")
    
    details["classification"] = {
        "agent_right": agent_right_class,
        "agent_left": agent_left_class,
        "expected_right": gt_right_class,
        "expected_left": gt_left_class
    }
    
    # ============================================================
    # CRITERION 4: Asymmetry assessment (10 points)
    # ============================================================
    agent_asymmetry = agent_report.get('asymmetry', {})
    agent_asymmetry_assessment = agent_asymmetry.get('assessment', '')
    
    # Calculate from measurements if not in report
    if not agent_asymmetry_assessment and agent_right_length > 0 and agent_left_length > 0:
        agent_diff = abs(agent_right_length - agent_left_length)
        agent_asymmetry_assessment = classify_asymmetry(agent_diff)
    
    if agent_asymmetry_assessment.lower() == gt_asymmetry_assessment.lower():
        score += w_asymmetry
        feedback_parts.append(f"✓ Asymmetry assessment: {agent_asymmetry_assessment}")
    elif agent_asymmetry_assessment:
        feedback_parts.append(f"✗ Asymmetry assessment: {agent_asymmetry_assessment} (expected {gt_asymmetry_assessment})")
    else:
        feedback_parts.append("✗ Asymmetry assessment: Not provided")
    
    # ============================================================
    # CRITERION 5: Measurements saved (10 points)
    # ============================================================
    right_exists = right_data.get('measurement_exists', False)
    left_exists = left_data.get('measurement_exists', False)
    right_during_task = right_data.get('created_during_task', False)
    left_during_task = left_data.get('created_during_task', False)
    
    measurements_score = 0
    if right_exists and right_during_task:
        measurements_score += w_measurements // 2
    if left_exists and left_during_task:
        measurements_score += w_measurements // 2
    
    score += measurements_score
    
    if measurements_score == w_measurements:
        feedback_parts.append("✓ Both measurements saved during task")
    elif measurements_score > 0:
        feedback_parts.append("~ Partial measurements saved")
    else:
        if right_exists or left_exists:
            feedback_parts.append("✗ Measurements exist but may not have been created during task")
        else:
            feedback_parts.append("✗ No measurement files found")
    
    # ============================================================
    # CRITERION 6: Report completeness (10 points)
    # ============================================================
    report_exists = report_data.get('exists', False)
    report_during_task = report_data.get('created_during_task', False)
    
    report_score = 0
    required_fields = ['right_kidney', 'left_kidney', 'asymmetry']
    if report_exists and report_during_task:
        fields_present = sum(1 for f in required_fields if f in agent_report)
        if fields_present == len(required_fields):
            report_score = w_report
            feedback_parts.append("✓ Report complete with all required fields")
        elif fields_present > 0:
            report_score = w_report * fields_present // len(required_fields)
            feedback_parts.append(f"~ Report partially complete ({fields_present}/{len(required_fields)} fields)")
        else:
            feedback_parts.append("✗ Report missing required fields")
    elif report_exists:
        report_score = w_report // 2
        feedback_parts.append("~ Report exists but may not have been created during task")
    else:
        feedback_parts.append("✗ Report file not found")
    
    score += report_score
    
    # ============================================================
    # CRITERION 7: Clinical interpretation (5 points)
    # ============================================================
    clinical_interpretation = agent_report.get('clinical_interpretation', '')
    if not clinical_interpretation:
        clinical_interpretation = agent_report.get('interpretation', '')
    if not clinical_interpretation:
        clinical_interpretation = agent_report.get('comment', '')
    
    if clinical_interpretation and len(clinical_interpretation) > 20:
        score += w_interpretation
        feedback_parts.append("✓ Clinical interpretation provided")
    elif clinical_interpretation:
        score += w_interpretation // 2
        feedback_parts.append("~ Brief clinical interpretation")
    else:
        feedback_parts.append("- No clinical interpretation (optional)")
    
    # ============================================================
    # Determine pass/fail
    # ============================================================
    # Pass if score >= 60 AND at least one kidney measurement is accurate
    at_least_one_accurate = right_accurate or left_accurate
    passed = (score >= 60) and at_least_one_accurate
    
    if not at_least_one_accurate and score >= 60:
        feedback_parts.append("Note: Score meets threshold but no accurate kidney measurement found")
    
    details["score_breakdown"] = {
        "right_kidney_length": w_right if right_accurate else (w_right // 2 if agent_right_length > 0 else 0),
        "left_kidney_length": w_left if left_accurate else (w_left // 2 if agent_left_length > 0 else 0),
        "classification": w_classification if classification_correct == 2 else (w_classification // 2 if classification_correct == 1 else 0),
        "asymmetry": w_asymmetry if agent_asymmetry_assessment.lower() == gt_asymmetry_assessment.lower() else 0,
        "measurements_saved": measurements_score,
        "report_completeness": report_score,
        "clinical_interpretation": w_interpretation if clinical_interpretation and len(clinical_interpretation) > 20 else (w_interpretation // 2 if clinical_interpretation else 0)
    }
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }