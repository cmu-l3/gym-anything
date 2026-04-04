#!/usr/bin/env python3
"""
Verifier for pancreas size assessment task.

VERIFICATION METRICS:
1. Head AP measurement accuracy (25 pts) - within 5mm of ground truth
2. Body AP measurement accuracy (25 pts) - within 5mm of ground truth  
3. Tail AP measurement accuracy (20 pts) - within 5mm of ground truth
4. Atrophy classification correct (15 pts)
5. Report completeness (10 pts) - all required fields present
6. Markup file exists (5 pts) - measurement file was created

Total: 100 points
Pass threshold: 60 points with at least 2/3 measurements accurate
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


def parse_float(value):
    """Safely parse a float from various input types."""
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value).strip())
    except (ValueError, TypeError):
        return None


def classify_atrophy(head_mm, body_mm, tail_mm):
    """
    Classify pancreatic atrophy based on measurements.
    
    Atrophy thresholds:
    - Head: <18mm
    - Body: <12mm
    - Tail: <12mm
    
    Classification:
    - Normal: All segments within normal range
    - Mild Atrophy: One segment below threshold OR all in lower third of normal
    - Moderate Atrophy: Two segments below threshold
    - Severe Atrophy: All three segments below threshold
    """
    thresholds = {"head": 18, "body": 12, "tail": 12}
    affected = []
    
    if head_mm is not None and head_mm < thresholds["head"]:
        affected.append("head")
    if body_mm is not None and body_mm < thresholds["body"]:
        affected.append("body")
    if tail_mm is not None and tail_mm < thresholds["tail"]:
        affected.append("tail")
    
    if len(affected) == 0:
        # Check if all are in lower third of normal
        lower_third = (
            (head_mm is None or head_mm < 23.3) and
            (body_mm is None or body_mm < 18.3) and
            (tail_mm is None or tail_mm < 18.3)
        )
        if lower_third and head_mm is not None and body_mm is not None and tail_mm is not None:
            return "Mild Atrophy", affected
        return "Normal", affected
    elif len(affected) == 1:
        return "Mild Atrophy", affected
    elif len(affected) == 2:
        return "Moderate Atrophy", affected
    else:
        return "Severe Atrophy", affected


def verify_pancreas_size_assessment(traj, env_info, task_info):
    """
    Verify pancreas size assessment task completion.
    
    Scoring (100 points total):
    - Head measurement accuracy: 25 points (within 5mm)
    - Body measurement accuracy: 25 points (within 5mm)
    - Tail measurement accuracy: 20 points (within 5mm)
    - Classification correct: 15 points
    - Report completeness: 10 points
    - Markup exists: 5 points
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
    
    measurement_error_max = thresholds.get('measurement_error_max_mm', 5.0)
    
    w_head = weights.get('head_accuracy', 25)
    w_body = weights.get('body_accuracy', 25)
    w_tail = weights.get('tail_accuracy', 20)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_completeness', 10)
    w_markup = weights.get('markup_exists', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/pancreas_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/pancreas_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_head = gt_data.get('head_ap_mm', 0)
    gt_body = gt_data.get('body_ap_mm', 0)
    gt_tail = gt_data.get('tail_ap_mm', 0)
    gt_classification = gt_data.get('classification', '')
    
    details['gt_head_mm'] = gt_head
    details['gt_body_mm'] = gt_body
    details['gt_tail_mm'] = gt_tail
    details['gt_classification'] = gt_classification
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_head = parse_float(result.get('reported_head_mm', ''))
    agent_body = parse_float(result.get('reported_body_mm', ''))
    agent_tail = parse_float(result.get('reported_tail_mm', ''))
    agent_classification = result.get('reported_classification', '')
    
    # Also try to read the agent's report file directly
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_pancreas_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
        
        if agent_head is None:
            agent_head = parse_float(agent_report.get('head_ap_mm'))
        if agent_body is None:
            agent_body = parse_float(agent_report.get('body_ap_mm'))
        if agent_tail is None:
            agent_tail = parse_float(agent_report.get('tail_ap_mm'))
        if not agent_classification:
            agent_classification = agent_report.get('atrophy_classification', 
                                                      agent_report.get('classification', ''))
    except Exception as e:
        logger.debug(f"Could not read agent report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    details['agent_head_mm'] = agent_head
    details['agent_body_mm'] = agent_body
    details['agent_tail_mm'] = agent_tail
    details['agent_classification'] = agent_classification
    
    # ============================================================
    # CRITERION 1: Head measurement accuracy (25 pts)
    # ============================================================
    head_accurate = False
    if agent_head is not None and gt_head > 0:
        head_error = abs(agent_head - gt_head)
        details['head_error_mm'] = head_error
        
        if head_error <= measurement_error_max:
            score += w_head
            head_accurate = True
            feedback_parts.append(f"✓ Head: {agent_head:.1f}mm (error: {head_error:.1f}mm)")
        else:
            # Partial credit for close measurements
            if head_error <= measurement_error_max * 2:
                partial = int(w_head * 0.5)
                score += partial
                feedback_parts.append(f"~ Head: {agent_head:.1f}mm (error: {head_error:.1f}mm) [{partial}pts]")
            else:
                feedback_parts.append(f"✗ Head: {agent_head:.1f}mm (error: {head_error:.1f}mm, expected ~{gt_head:.1f})")
    elif agent_head is None:
        feedback_parts.append("✗ Head: not measured")
    else:
        feedback_parts.append(f"✗ Head: {agent_head:.1f}mm (no ground truth)")
    
    # ============================================================
    # CRITERION 2: Body measurement accuracy (25 pts)
    # ============================================================
    body_accurate = False
    if agent_body is not None and gt_body > 0:
        body_error = abs(agent_body - gt_body)
        details['body_error_mm'] = body_error
        
        if body_error <= measurement_error_max:
            score += w_body
            body_accurate = True
            feedback_parts.append(f"✓ Body: {agent_body:.1f}mm (error: {body_error:.1f}mm)")
        else:
            if body_error <= measurement_error_max * 2:
                partial = int(w_body * 0.5)
                score += partial
                feedback_parts.append(f"~ Body: {agent_body:.1f}mm (error: {body_error:.1f}mm) [{partial}pts]")
            else:
                feedback_parts.append(f"✗ Body: {agent_body:.1f}mm (error: {body_error:.1f}mm, expected ~{gt_body:.1f})")
    elif agent_body is None:
        feedback_parts.append("✗ Body: not measured")
    else:
        feedback_parts.append(f"✗ Body: {agent_body:.1f}mm (no ground truth)")
    
    # ============================================================
    # CRITERION 3: Tail measurement accuracy (20 pts)
    # ============================================================
    tail_accurate = False
    if agent_tail is not None and gt_tail > 0:
        tail_error = abs(agent_tail - gt_tail)
        details['tail_error_mm'] = tail_error
        
        if tail_error <= measurement_error_max:
            score += w_tail
            tail_accurate = True
            feedback_parts.append(f"✓ Tail: {agent_tail:.1f}mm (error: {tail_error:.1f}mm)")
        else:
            if tail_error <= measurement_error_max * 2:
                partial = int(w_tail * 0.5)
                score += partial
                feedback_parts.append(f"~ Tail: {agent_tail:.1f}mm (error: {tail_error:.1f}mm) [{partial}pts]")
            else:
                feedback_parts.append(f"✗ Tail: {agent_tail:.1f}mm (error: {tail_error:.1f}mm, expected ~{gt_tail:.1f})")
    elif agent_tail is None:
        feedback_parts.append("✗ Tail: not measured")
    else:
        feedback_parts.append(f"✗ Tail: {agent_tail:.1f}mm (no ground truth)")
    
    # ============================================================
    # CRITERION 4: Classification correct (15 pts)
    # ============================================================
    classification_correct = False
    
    if agent_classification:
        # Normalize classification strings
        agent_class_norm = agent_classification.lower().strip()
        gt_class_norm = gt_classification.lower().strip()
        
        # Handle variations
        class_map = {
            'normal': 'normal',
            'mild atrophy': 'mild atrophy',
            'mild': 'mild atrophy',
            'moderate atrophy': 'moderate atrophy',
            'moderate': 'moderate atrophy',
            'severe atrophy': 'severe atrophy',
            'severe': 'severe atrophy',
        }
        
        agent_class_norm = class_map.get(agent_class_norm, agent_class_norm)
        gt_class_norm = class_map.get(gt_class_norm, gt_class_norm)
        
        if agent_class_norm == gt_class_norm:
            score += w_classification
            classification_correct = True
            feedback_parts.append(f"✓ Classification: {agent_classification}")
        else:
            # Check if agent's computed classification is reasonable based on their measurements
            if agent_head is not None and agent_body is not None and agent_tail is not None:
                computed_class, _ = classify_atrophy(agent_head, agent_body, agent_tail)
                if computed_class.lower() == agent_class_norm:
                    # Classification is consistent with measurements, partial credit
                    partial = int(w_classification * 0.5)
                    score += partial
                    feedback_parts.append(f"~ Classification: {agent_classification} (consistent with measurements) [{partial}pts]")
                else:
                    feedback_parts.append(f"✗ Classification: {agent_classification} (expected: {gt_classification})")
            else:
                feedback_parts.append(f"✗ Classification: {agent_classification} (expected: {gt_classification})")
    else:
        feedback_parts.append("✗ Classification: not provided")
    
    # ============================================================
    # CRITERION 5: Report completeness (10 pts)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    required_fields = ['head_ap_mm', 'body_ap_mm', 'tail_ap_mm', 'atrophy_classification']
    fields_present = sum([
        agent_head is not None,
        agent_body is not None,
        agent_tail is not None,
        bool(agent_classification)
    ])
    
    if report_exists and fields_present == 4:
        score += w_report
        feedback_parts.append(f"✓ Report complete ({fields_present}/4 fields)")
    elif fields_present > 0:
        partial = int(w_report * fields_present / 4)
        score += partial
        feedback_parts.append(f"~ Report partial ({fields_present}/4 fields) [{partial}pts]")
    else:
        feedback_parts.append("✗ Report: missing or incomplete")
    
    # ============================================================
    # CRITERION 6: Markup file exists (5 pts)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_count = result.get('measurement_count', 0)
    
    if measurement_exists and measurement_count >= 3:
        score += w_markup
        feedback_parts.append(f"✓ Markup: {measurement_count} measurements saved")
    elif measurement_exists:
        partial = int(w_markup * min(measurement_count, 3) / 3)
        score += partial
        feedback_parts.append(f"~ Markup: {measurement_count} measurements [{partial}pts]")
    else:
        feedback_parts.append("✗ Markup: no measurement file")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    measurements_accurate = sum([head_accurate, body_accurate, tail_accurate])
    details['measurements_accurate'] = measurements_accurate
    
    # Pass requires: score >= 60 AND at least 2/3 measurements accurate
    passed = score >= 60 and measurements_accurate >= 2
    
    if not passed and score >= 60:
        feedback_parts.append(f"Note: Score {score}/100 but only {measurements_accurate}/3 measurements accurate (need 2+)")
    
    # Convert any numpy types in details
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }