#!/usr/bin/env python3
"""
Verifier for gallbladder morphometry and cholecystitis screening task.

VERIFICATION METRICS:
1. Gallbladder identified - measurement placed in correct anatomical location
2. Length accuracy - longitudinal measurement within tolerance
3. Transverse accuracy - width measurement within tolerance  
4. Wall thickness accuracy - critical for clinical classification
5. Classification correctness - matches expected clinical category
6. Report completeness - all required fields present
7. Internal consistency - findings match measurements

Scoring weights (100 points total):
- Gallbladder identified: 10 points
- Length accuracy: 20 points
- Transverse accuracy: 15 points
- Wall thickness accuracy: 25 points (critical)
- Classification correct: 15 points
- Report completeness: 10 points
- Internal consistency: 5 points

Pass threshold: 60 points with wall thickness accuracy achieved
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
    """Convert to Python native types for JSON serialization."""
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


def parse_float(val, default=0.0):
    """Safely parse a float from various input types."""
    if val is None or val == '':
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def classify_gallbladder(length_cm, transverse_cm, wall_mm):
    """
    Classify gallbladder based on measurements.
    
    Classifications:
    - Normal: All within normal limits
    - Distended (Hydrops): length >10cm OR transverse >5cm, wall ≤3mm
    - Wall Thickening: wall >3mm, no distension
    - Imaging Consistent with Acute Cholecystitis: wall >3mm AND distension
    """
    distension = length_cm > 10.0 or transverse_cm > 5.0
    wall_thickening = wall_mm > 3.0
    
    if wall_thickening and distension:
        return "Imaging Consistent with Acute Cholecystitis"
    elif wall_thickening:
        return "Wall Thickening"
    elif distension:
        return "Distended (Hydrops)"
    else:
        return "Normal"


def normalize_classification(classification):
    """Normalize classification string for comparison."""
    if not classification:
        return ""
    
    c = classification.lower().strip()
    
    # Map variations to standard categories
    if "cholecystitis" in c or ("wall" in c and "distension" in c):
        return "acute_cholecystitis"
    elif "wall" in c and ("thick" in c or ">3" in c):
        return "wall_thickening"
    elif "distend" in c or "hydrops" in c or "enlarg" in c:
        return "distended"
    elif "normal" in c or "unremarkable" in c:
        return "normal"
    else:
        return c


def verify_gallbladder_assessment(traj, env_info, task_info):
    """
    Verify gallbladder morphometry and cholecystitis screening task.
    
    Scoring:
    - Gallbladder identified: 10 points
    - Length accuracy (≤1.0cm error): 20 points
    - Transverse accuracy (≤0.8cm error): 15 points
    - Wall thickness accuracy (≤1.5mm error): 25 points
    - Classification correct: 15 points
    - Report completeness: 10 points
    - Internal consistency: 5 points
    
    Pass: 60 points AND wall thickness within tolerance
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
    
    length_error_max = thresholds.get('length_error_max_cm', 1.0)
    transverse_error_max = thresholds.get('transverse_error_max_cm', 0.8)
    wall_error_max = thresholds.get('wall_thickness_error_max_mm', 1.5)
    
    w_identified = weights.get('gallbladder_identified', 10)
    w_length = weights.get('length_accuracy', 20)
    w_transverse = weights.get('transverse_accuracy', 15)
    w_wall = weights.get('wall_thickness_accuracy', 25)
    w_classification = weights.get('classification_correct', 15)
    w_report = weights.get('report_completeness', 10)
    w_consistency = weights.get('internal_consistency', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/gallbladder_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/gallbladder_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_measurements = gt_data.get('measurements', {})
    gt_length = gt_measurements.get('length_cm', 0)
    gt_transverse = gt_measurements.get('transverse_diameter_cm', 0)
    gt_wall = gt_measurements.get('wall_thickness_mm', 0)
    gt_classification = gt_data.get('classification', '')
    gt_location = gt_data.get('gallbladder_location', {})
    
    details['gt_length_cm'] = gt_length
    details['gt_transverse_cm'] = gt_transverse
    details['gt_wall_mm'] = gt_wall
    details['gt_classification'] = gt_classification
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_length = parse_float(result.get('reported_length_cm', ''))
    agent_transverse = parse_float(result.get('reported_transverse_cm', ''))
    agent_wall = parse_float(result.get('reported_wall_mm', ''))
    agent_classification = result.get('reported_classification', '')
    
    # Try to get measurements from report file if not in result
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/agent_gb_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            agent_report = json.load(f)
        
        meas = agent_report.get('measurements', {})
        if agent_length == 0:
            agent_length = parse_float(meas.get('length_cm', meas.get('length', 0)))
        if agent_transverse == 0:
            agent_transverse = parse_float(meas.get('transverse_diameter_cm', 
                                          meas.get('transverse_cm', 
                                          meas.get('transverse', 0))))
        if agent_wall == 0:
            agent_wall = parse_float(meas.get('wall_thickness_mm', 
                                    meas.get('wall_mm', 
                                    meas.get('wall', 0))))
        if not agent_classification:
            agent_classification = agent_report.get('classification', '')
        
        details['agent_report_loaded'] = True
        details['agent_report'] = to_python_type(agent_report)
    except Exception as e:
        details['agent_report_loaded'] = False
        details['agent_report_error'] = str(e)
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    details['agent_length_cm'] = agent_length
    details['agent_transverse_cm'] = agent_transverse
    details['agent_wall_mm'] = agent_wall
    details['agent_classification'] = agent_classification
    
    # ============================================================
    # CRITERION 1: Gallbladder Identified (10 points)
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_modified = result.get('measurement_modified_during_task', False)
    measurement_count = result.get('measurement_count', 0)
    
    gb_identified = False
    if measurement_exists and measurement_modified and measurement_count > 0:
        score += w_identified
        gb_identified = True
        feedback_parts.append(f"✓ Gallbladder identified ({measurement_count} measurements)")
    elif measurement_exists:
        score += w_identified // 2
        gb_identified = True
        feedback_parts.append("~ Measurements exist but may predate task")
    else:
        feedback_parts.append("✗ No measurements found")
    
    details['gallbladder_identified'] = gb_identified
    
    # ============================================================
    # CRITERION 2: Length Accuracy (20 points)
    # ============================================================
    length_error = abs(agent_length - gt_length) if agent_length > 0 else float('inf')
    length_accurate = length_error <= length_error_max
    
    if agent_length > 0:
        if length_accurate:
            score += w_length
            feedback_parts.append(f"✓ Length accurate: {agent_length:.1f}cm (GT: {gt_length:.1f}cm, error: {length_error:.2f}cm)")
        elif length_error <= length_error_max * 2:
            score += w_length // 2
            feedback_parts.append(f"~ Length close: {agent_length:.1f}cm (GT: {gt_length:.1f}cm, error: {length_error:.2f}cm)")
        else:
            feedback_parts.append(f"✗ Length inaccurate: {agent_length:.1f}cm (GT: {gt_length:.1f}cm)")
    else:
        feedback_parts.append("✗ Length not reported")
    
    details['length_error_cm'] = to_python_type(length_error)
    details['length_accurate'] = length_accurate
    
    # ============================================================
    # CRITERION 3: Transverse Accuracy (15 points)
    # ============================================================
    transverse_error = abs(agent_transverse - gt_transverse) if agent_transverse > 0 else float('inf')
    transverse_accurate = transverse_error <= transverse_error_max
    
    if agent_transverse > 0:
        if transverse_accurate:
            score += w_transverse
            feedback_parts.append(f"✓ Transverse accurate: {agent_transverse:.1f}cm (GT: {gt_transverse:.1f}cm)")
        elif transverse_error <= transverse_error_max * 2:
            score += w_transverse // 2
            feedback_parts.append(f"~ Transverse close: {agent_transverse:.1f}cm (GT: {gt_transverse:.1f}cm)")
        else:
            feedback_parts.append(f"✗ Transverse inaccurate: {agent_transverse:.1f}cm (GT: {gt_transverse:.1f}cm)")
    else:
        feedback_parts.append("✗ Transverse diameter not reported")
    
    details['transverse_error_cm'] = to_python_type(transverse_error)
    details['transverse_accurate'] = transverse_accurate
    
    # ============================================================
    # CRITERION 4: Wall Thickness Accuracy (25 points) - CRITICAL
    # ============================================================
    wall_error = abs(agent_wall - gt_wall) if agent_wall > 0 else float('inf')
    wall_accurate = wall_error <= wall_error_max
    
    if agent_wall > 0:
        if wall_accurate:
            score += w_wall
            feedback_parts.append(f"✓ Wall thickness accurate: {agent_wall:.1f}mm (GT: {gt_wall:.1f}mm)")
        elif wall_error <= wall_error_max * 2:
            score += w_wall // 2
            feedback_parts.append(f"~ Wall thickness close: {agent_wall:.1f}mm (GT: {gt_wall:.1f}mm, error: {wall_error:.2f}mm)")
        else:
            feedback_parts.append(f"✗ Wall thickness inaccurate: {agent_wall:.1f}mm (GT: {gt_wall:.1f}mm)")
    else:
        feedback_parts.append("✗ Wall thickness not reported (CRITICAL)")
    
    details['wall_error_mm'] = to_python_type(wall_error)
    details['wall_accurate'] = wall_accurate
    
    # ============================================================
    # CRITERION 5: Classification Correct (15 points)
    # ============================================================
    agent_class_normalized = normalize_classification(agent_classification)
    gt_class_normalized = normalize_classification(gt_classification)
    
    # Also compute expected classification from agent's measurements
    if agent_length > 0 and agent_transverse > 0 and agent_wall > 0:
        expected_class = classify_gallbladder(agent_length, agent_transverse, agent_wall)
        expected_class_normalized = normalize_classification(expected_class)
    else:
        expected_class = ""
        expected_class_normalized = ""
    
    classification_matches_gt = agent_class_normalized == gt_class_normalized
    classification_matches_measurements = agent_class_normalized == expected_class_normalized
    
    if agent_classification:
        if classification_matches_gt:
            score += w_classification
            feedback_parts.append(f"✓ Classification correct: {agent_classification}")
        elif classification_matches_measurements:
            # Classification is consistent with their measurements, even if measurements are wrong
            score += w_classification // 2
            feedback_parts.append(f"~ Classification consistent with measurements: {agent_classification}")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {agent_classification} (expected: {gt_classification})")
    else:
        feedback_parts.append("✗ Classification not provided")
    
    details['classification_matches_gt'] = classification_matches_gt
    details['classification_matches_measurements'] = classification_matches_measurements
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_modified = result.get('report_modified_during_task', False)
    
    required_fields = ['length_cm', 'transverse_diameter_cm', 'wall_thickness_mm', 'classification']
    fields_present = sum([
        agent_length > 0,
        agent_transverse > 0,
        agent_wall > 0,
        bool(agent_classification)
    ])
    
    if report_exists and report_modified and fields_present >= 4:
        score += w_report
        feedback_parts.append(f"✓ Report complete ({fields_present}/4 fields)")
    elif report_exists and fields_present >= 2:
        score += w_report // 2
        feedback_parts.append(f"~ Report partial ({fields_present}/4 fields)")
    else:
        feedback_parts.append("✗ Report missing or incomplete")
    
    details['report_exists'] = report_exists
    details['report_modified'] = report_modified
    details['fields_present'] = fields_present
    
    # ============================================================
    # CRITERION 7: Internal Consistency (5 points)
    # ============================================================
    # Check if findings match measurements
    consistent = True
    consistency_issues = []
    
    if agent_length > 0 and agent_transverse > 0 and agent_wall > 0:
        expected_distension = agent_length > 10.0 or agent_transverse > 5.0
        expected_wall_thickening = agent_wall > 3.0
        
        # Check if classification is consistent with measurements
        if expected_wall_thickening and expected_distension:
            if "cholecystitis" not in agent_class_normalized and agent_class_normalized != "":
                consistent = False
                consistency_issues.append("Measurements suggest cholecystitis but classification differs")
        elif expected_wall_thickening:
            if "wall" not in agent_class_normalized and "thickening" not in agent_class_normalized and agent_class_normalized != "":
                if "cholecystitis" not in agent_class_normalized:
                    consistent = False
                    consistency_issues.append("Wall >3mm but not classified as wall thickening")
    else:
        consistent = False
        consistency_issues.append("Not all measurements provided for consistency check")
    
    if consistent:
        score += w_consistency
        feedback_parts.append("✓ Report internally consistent")
    else:
        feedback_parts.append(f"~ Consistency issues: {'; '.join(consistency_issues)}")
    
    details['internal_consistency'] = consistent
    details['consistency_issues'] = consistency_issues
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    # Pass criteria: 60 points AND wall thickness within tolerance (critical for clinical decision)
    key_criterion_met = wall_accurate
    passed = score >= 60 and key_criterion_met
    
    # Construct final feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED ({score}/100): {feedback}"
    else:
        if not key_criterion_met:
            feedback = f"FAILED ({score}/100) - Wall thickness accuracy required: {feedback}"
        else:
            feedback = f"FAILED ({score}/100) - Score below 60: {feedback}"
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback,
        "details": to_python_type(details)
    }