#!/usr/bin/env python3
"""
Verifier for adrenal incidentaloma characterization task.

VERIFICATION METRICS:
1. Nodule Located (10 pts) - measurement exists in correct region
2. Laterality Correct (10 pts) - correctly identified left/right
3. Size Accuracy (25 pts) - diameter within 3mm of ground truth
4. Density Accuracy (25 pts) - HU within 15 of ground truth
5. Classification Correct (20 pts) - correct ACR category
6. Report Complete (10 pts) - all required fields present

Pass threshold: 60 points with size accuracy achieved
"""

import json
import os
import sys
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def classify_acr(size_mm: float, hu: float) -> str:
    """
    Classify adrenal nodule according to ACR Incidental Findings guidelines.
    
    Args:
        size_mm: Maximum diameter in millimeters
        hu: Mean Hounsfield Unit density
        
    Returns:
        Classification string
    """
    if size_mm < 10:
        return "benign_adenoma"
    elif size_mm >= 40:
        return "concerning"
    elif hu <= 10:
        return "benign_adenoma"
    elif hu <= 30:
        return "likely_benign"
    else:
        return "indeterminate"


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


def verify_adrenal_incidentaloma(traj, env_info, task_info):
    """
    Verify adrenal incidentaloma characterization task completion.
    
    Scoring (100 points total):
    - Nodule located: 10 points (measurement exists)
    - Laterality correct: 10 points
    - Size accuracy: 25 points (within 3mm)
    - Density accuracy: 25 points (within 15 HU)
    - Classification correct: 20 points
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
    
    diameter_error_max = thresholds.get('diameter_error_max_mm', 3.0)
    density_error_max = thresholds.get('density_error_max_hu', 15.0)
    
    w_located = weights.get('nodule_located', 10)
    w_laterality = weights.get('laterality_correct', 10)
    w_size = weights.get('size_accuracy', 25)
    w_density = weights.get('density_accuracy', 25)
    w_classification = weights.get('classification_correct', 20)
    w_report = weights.get('report_complete', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/adrenal_task_result.json", temp_result.name)
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
            "feedback": "Slicer was not running - task not attempted"
        }
    
    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/adrenal_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not load ground truth: {e}"
        }
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_laterality = gt_data.get('laterality', '')
    gt_diameter = gt_data.get('exact_diameter_mm', 0)
    gt_hu = gt_data.get('exact_density_hu', 0)
    gt_classification = gt_data.get('correct_classification', '')
    
    details['gt_laterality'] = gt_laterality
    details['gt_diameter_mm'] = gt_diameter
    details['gt_density_hu'] = gt_hu
    details['gt_classification'] = gt_classification
    
    # ============================================================
    # CRITERION 1: Nodule Located (measurement exists) - 10 pts
    # ============================================================
    measurement_exists = result.get('measurement_exists', False)
    measurement_created = result.get('measurement_created_during_task', False)
    
    if measurement_exists and measurement_created:
        score += w_located
        feedback_parts.append(f"✓ Measurement created during task (+{w_located})")
    elif measurement_exists:
        score += w_located // 2
        feedback_parts.append(f"~ Measurement exists but may be pre-existing (+{w_located // 2})")
    else:
        feedback_parts.append("✗ No measurement found")
    
    details['measurement_exists'] = measurement_exists
    details['measurement_created_during_task'] = measurement_created
    
    # ============================================================
    # CRITERION 2: Laterality Correct - 10 pts
    # ============================================================
    reported_laterality = result.get('reported_laterality', '').lower().strip()
    
    if reported_laterality and reported_laterality == gt_laterality.lower():
        score += w_laterality
        feedback_parts.append(f"✓ Laterality correct: {gt_laterality} (+{w_laterality})")
    elif reported_laterality:
        feedback_parts.append(f"✗ Laterality incorrect: reported '{reported_laterality}', expected '{gt_laterality}'")
    else:
        feedback_parts.append("✗ Laterality not reported")
    
    details['reported_laterality'] = reported_laterality
    
    # ============================================================
    # CRITERION 3: Size Accuracy - 25 pts
    # ============================================================
    agent_diameter = 0.0
    size_accurate = False
    
    # Try from reported size first
    reported_size = result.get('reported_size_mm', '')
    if reported_size:
        try:
            agent_diameter = float(reported_size)
        except ValueError:
            pass
    
    # Fallback to measured diameter from markup
    if agent_diameter == 0:
        measured_diam = result.get('measured_diameter_mm', '')
        if measured_diam:
            try:
                agent_diameter = float(measured_diam)
            except ValueError:
                pass
    
    details['agent_diameter_mm'] = agent_diameter
    
    if agent_diameter > 0:
        diameter_error = abs(agent_diameter - gt_diameter)
        details['diameter_error_mm'] = diameter_error
        
        if diameter_error <= diameter_error_max:
            score += w_size
            size_accurate = True
            feedback_parts.append(f"✓ Size accurate: {agent_diameter:.1f}mm vs GT {gt_diameter:.1f}mm (error: {diameter_error:.1f}mm) (+{w_size})")
        elif diameter_error <= diameter_error_max * 2:
            partial = w_size // 2
            score += partial
            feedback_parts.append(f"~ Size partially accurate: {agent_diameter:.1f}mm vs GT {gt_diameter:.1f}mm (error: {diameter_error:.1f}mm) (+{partial})")
        else:
            feedback_parts.append(f"✗ Size inaccurate: {agent_diameter:.1f}mm vs GT {gt_diameter:.1f}mm (error: {diameter_error:.1f}mm)")
    else:
        feedback_parts.append("✗ No size measurement found")
    
    # ============================================================
    # CRITERION 4: Density Accuracy - 25 pts
    # ============================================================
    agent_hu = None
    density_accurate = False
    
    reported_hu = result.get('reported_hu', '')
    if reported_hu:
        try:
            agent_hu = float(reported_hu)
        except ValueError:
            pass
    
    details['agent_density_hu'] = agent_hu
    
    if agent_hu is not None:
        density_error = abs(agent_hu - gt_hu)
        details['density_error_hu'] = density_error
        
        if density_error <= density_error_max:
            score += w_density
            density_accurate = True
            feedback_parts.append(f"✓ Density accurate: {agent_hu:.1f} HU vs GT {gt_hu:.1f} HU (error: {density_error:.1f}) (+{w_density})")
        elif density_error <= density_error_max * 2:
            partial = w_density // 2
            score += partial
            feedback_parts.append(f"~ Density partially accurate: {agent_hu:.1f} HU vs GT {gt_hu:.1f} HU (error: {density_error:.1f}) (+{partial})")
        else:
            feedback_parts.append(f"✗ Density inaccurate: {agent_hu:.1f} HU vs GT {gt_hu:.1f} HU (error: {density_error:.1f})")
    else:
        feedback_parts.append("✗ No density measurement found")
    
    # ============================================================
    # CRITERION 5: Classification Correct - 20 pts
    # ============================================================
    reported_classification = result.get('reported_classification', '').lower().strip()
    
    # Normalize classification names
    classification_map = {
        'benign': 'benign_adenoma',
        'benign_adenoma': 'benign_adenoma',
        'adenoma': 'benign_adenoma',
        'likely_benign': 'likely_benign',
        'likely benign': 'likely_benign',
        'indeterminate': 'indeterminate',
        'concerning': 'concerning',
        'suspicious': 'concerning',
        'malignant': 'concerning'
    }
    
    normalized_classification = classification_map.get(reported_classification, reported_classification)
    details['reported_classification'] = reported_classification
    details['normalized_classification'] = normalized_classification
    
    # Also calculate what classification SHOULD be based on agent's measurements
    if agent_diameter > 0 and agent_hu is not None:
        expected_from_measurements = classify_acr(agent_diameter, agent_hu)
        details['expected_from_agent_measurements'] = expected_from_measurements
    
    if normalized_classification and normalized_classification == gt_classification:
        score += w_classification
        feedback_parts.append(f"✓ Classification correct: {gt_classification} (+{w_classification})")
    elif normalized_classification:
        # Check if classification is internally consistent with measurements
        if agent_diameter > 0 and agent_hu is not None:
            agent_expected_class = classify_acr(agent_diameter, agent_hu)
            if normalized_classification == agent_expected_class:
                # Give partial credit for internally consistent but wrong (due to measurement error)
                partial = w_classification // 2
                score += partial
                feedback_parts.append(f"~ Classification consistent with measurements but GT is {gt_classification} (+{partial})")
            else:
                feedback_parts.append(f"✗ Classification incorrect: reported '{reported_classification}', expected '{gt_classification}'")
        else:
            feedback_parts.append(f"✗ Classification incorrect: reported '{reported_classification}', expected '{gt_classification}'")
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ============================================================
    # CRITERION 6: Report Completeness - 10 pts
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    required_fields = ['laterality', 'size_mm', 'density_hu', 'classification']
    fields_present = 0
    
    if reported_laterality:
        fields_present += 1
    if reported_size:
        fields_present += 1
    if reported_hu:
        fields_present += 1
    if reported_classification:
        fields_present += 1
    
    details['report_fields_present'] = fields_present
    details['report_fields_required'] = len(required_fields)
    
    if report_exists and report_created and fields_present == len(required_fields):
        score += w_report
        feedback_parts.append(f"✓ Report complete with all fields (+{w_report})")
    elif report_exists and fields_present >= len(required_fields) // 2:
        partial = w_report * fields_present // len(required_fields)
        score += partial
        feedback_parts.append(f"~ Report partial: {fields_present}/{len(required_fields)} fields (+{partial})")
    else:
        feedback_parts.append(f"✗ Report incomplete or missing ({fields_present}/{len(required_fields)} fields)")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: must have size accuracy to pass
    key_criteria_met = size_accurate
    passed = score >= 60 and key_criteria_met
    
    if not key_criteria_met and score >= 60:
        feedback_parts.append("Note: Score >= 60 but key criterion (size accuracy) not met")
    
    # Convert all numpy types to Python native
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "nodule_located": w_located if measurement_exists else 0,
            "laterality_correct": w_laterality if reported_laterality == gt_laterality.lower() else 0,
            "size_accuracy": w_size if size_accurate else 0,
            "density_accuracy": w_density if density_accurate else 0,
            "classification_correct": w_classification if normalized_classification == gt_classification else 0,
            "report_complete": w_report if fields_present == len(required_fields) else 0
        }
    }