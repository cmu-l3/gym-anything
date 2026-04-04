#!/usr/bin/env python3
"""
Verifier for bicaudate index measurement task.

VERIFICATION METRICS:
1. Intercaudate distance accuracy (within 3mm of ground truth)
2. Brain width accuracy (within 5mm of ground truth)
3. Bicaudate index accuracy (within 0.03 of ground truth)
4. Classification correctness (Normal/Borderline/Atrophic)
5. Anatomical level correctness (correct slice ±3)
6. Report completeness (all required fields present)

ANTI-GAMING CHECKS:
- File timestamps must be after task start
- Measurements must be plausible values
- IC and BW must be distinct (BW > IC)
- BCI must mathematically equal IC/BW
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


def safe_float(val, default=0.0):
    """Safely convert a value to float."""
    if val is None or val == '':
        return default
    try:
        return float(val)
    except (ValueError, TypeError):
        return default


def classify_bci(bci, thresholds):
    """Classify bicaudate index."""
    normal_max = thresholds.get('normal_max', 0.15)
    borderline_max = thresholds.get('borderline_max', 0.18)
    
    if bci < normal_max:
        return "Normal"
    elif bci <= borderline_max:
        return "Borderline"
    else:
        return "Atrophic"


def verify_bicaudate_index(traj, env_info, task_info):
    """
    Verify bicaudate index measurement task completion.
    
    Scoring (100 points total):
    - Intercaudate distance accuracy: 25 points (within 3mm)
    - Brain width accuracy: 20 points (within 5mm)
    - Bicaudate index accuracy: 20 points (within 0.03)
    - Classification correct: 15 points
    - Anatomical level: 10 points (correct slice ±3)
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
    clinical_thresholds = metadata.get('clinical_thresholds', {})
    
    ic_error_max = thresholds.get('ic_error_max_mm', 3.0)
    bw_error_max = thresholds.get('bw_error_max_mm', 5.0)
    bci_error_max = thresholds.get('bci_error_max', 0.03)
    slice_error_max = thresholds.get('slice_error_max', 3)
    
    w_ic = weights.get('intercaudate_accuracy', 25)
    w_bw = weights.get('brain_width_accuracy', 20)
    w_bci = weights.get('bci_accuracy', 20)
    w_class = weights.get('classification_correct', 15)
    w_level = weights.get('anatomical_level', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/bicaudate_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/bicaudate_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_ic = gt_data.get('intercaudate_distance_mm', 0)
    gt_bw = gt_data.get('brain_width_mm', 0)
    gt_bci = gt_data.get('bicaudate_index', 0)
    gt_class = gt_data.get('classification', '')
    gt_slice = gt_data.get('optimal_slice', 0)
    
    details['gt_intercaudate_mm'] = gt_ic
    details['gt_brain_width_mm'] = gt_bw
    details['gt_bicaudate_index'] = gt_bci
    details['gt_classification'] = gt_class
    details['gt_slice'] = gt_slice
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    
    # Try multiple sources for measurements
    agent_ic = 0.0
    agent_bw = 0.0
    agent_bci = 0.0
    agent_class = ''
    agent_slice = 0
    
    # From direct markup measurements
    ic_mm_str = result.get('ic_measurement_mm', '')
    bw_mm_str = result.get('bw_measurement_mm', '')
    
    agent_ic = safe_float(ic_mm_str)
    agent_bw = safe_float(bw_mm_str)
    
    # From report file
    reported_ic = safe_float(result.get('reported_intercaudate_mm', ''))
    reported_bw = safe_float(result.get('reported_brain_width_mm', ''))
    reported_bci = safe_float(result.get('reported_bicaudate_index', ''))
    reported_class = result.get('reported_classification', '')
    reported_slice = safe_float(result.get('reported_slice', ''), default=0)
    
    # Use report values if direct measurements are missing
    if agent_ic == 0 and reported_ic > 0:
        agent_ic = reported_ic
    if agent_bw == 0 and reported_bw > 0:
        agent_bw = reported_bw
    
    agent_class = reported_class
    agent_slice = int(reported_slice) if reported_slice > 0 else 0
    
    # Calculate BCI from measurements if not reported
    if agent_ic > 0 and agent_bw > 0:
        calculated_bci = agent_ic / agent_bw
        if reported_bci > 0:
            agent_bci = reported_bci
        else:
            agent_bci = calculated_bci
    elif reported_bci > 0:
        agent_bci = reported_bci
    
    details['agent_intercaudate_mm'] = agent_ic
    details['agent_brain_width_mm'] = agent_bw
    details['agent_bicaudate_index'] = agent_bci
    details['agent_classification'] = agent_class
    details['agent_slice'] = agent_slice
    
    # ============================================================
    # ANTI-GAMING CHECKS
    # ============================================================
    
    ic_created = result.get('ic_created_during_task', False)
    bw_created = result.get('bw_created_during_task', False)
    report_created = result.get('report_created_during_task', False)
    
    files_created_during_task = ic_created or bw_created or report_created
    
    # Plausibility checks
    measurements_plausible = True
    plausibility_issues = []
    
    # IC should be between 5-25mm typically
    if agent_ic > 0 and (agent_ic < 3 or agent_ic > 40):
        measurements_plausible = False
        plausibility_issues.append(f"IC ({agent_ic:.1f}mm) outside plausible range (3-40mm)")
    
    # BW should be between 100-180mm typically
    if agent_bw > 0 and (agent_bw < 80 or agent_bw > 200):
        measurements_plausible = False
        plausibility_issues.append(f"BW ({agent_bw:.1f}mm) outside plausible range (80-200mm)")
    
    # BW should be greater than IC
    if agent_ic > 0 and agent_bw > 0 and agent_bw <= agent_ic:
        measurements_plausible = False
        plausibility_issues.append(f"BW ({agent_bw:.1f}mm) should be > IC ({agent_ic:.1f}mm)")
    
    # BCI should mathematically equal IC/BW
    if agent_ic > 0 and agent_bw > 0 and agent_bci > 0:
        expected_bci = agent_ic / agent_bw
        bci_calc_error = abs(agent_bci - expected_bci)
        if bci_calc_error > 0.01:
            plausibility_issues.append(f"BCI ({agent_bci:.4f}) doesn't match IC/BW ({expected_bci:.4f})")
    
    details['files_created_during_task'] = files_created_during_task
    details['measurements_plausible'] = measurements_plausible
    details['plausibility_issues'] = plausibility_issues
    
    # ============================================================
    # CRITERION 1: INTERCAUDATE DISTANCE ACCURACY (25 points)
    # ============================================================
    ic_error = abs(agent_ic - gt_ic) if agent_ic > 0 and gt_ic > 0 else float('inf')
    details['ic_error_mm'] = ic_error
    
    if ic_error <= ic_error_max:
        score += w_ic
        feedback_parts.append(f"✓ IC accurate: {agent_ic:.1f}mm (GT: {gt_ic:.1f}mm, error: {ic_error:.1f}mm)")
    elif ic_error <= ic_error_max * 2:
        partial = int(w_ic * 0.5)
        score += partial
        feedback_parts.append(f"~ IC partially accurate: {agent_ic:.1f}mm (GT: {gt_ic:.1f}mm, error: {ic_error:.1f}mm)")
    elif agent_ic > 0:
        feedback_parts.append(f"✗ IC inaccurate: {agent_ic:.1f}mm (GT: {gt_ic:.1f}mm, error: {ic_error:.1f}mm)")
    else:
        feedback_parts.append("✗ IC measurement not found")
    
    # ============================================================
    # CRITERION 2: BRAIN WIDTH ACCURACY (20 points)
    # ============================================================
    bw_error = abs(agent_bw - gt_bw) if agent_bw > 0 and gt_bw > 0 else float('inf')
    details['bw_error_mm'] = bw_error
    
    if bw_error <= bw_error_max:
        score += w_bw
        feedback_parts.append(f"✓ BW accurate: {agent_bw:.1f}mm (GT: {gt_bw:.1f}mm, error: {bw_error:.1f}mm)")
    elif bw_error <= bw_error_max * 2:
        partial = int(w_bw * 0.5)
        score += partial
        feedback_parts.append(f"~ BW partially accurate: {agent_bw:.1f}mm (GT: {gt_bw:.1f}mm, error: {bw_error:.1f}mm)")
    elif agent_bw > 0:
        feedback_parts.append(f"✗ BW inaccurate: {agent_bw:.1f}mm (GT: {gt_bw:.1f}mm, error: {bw_error:.1f}mm)")
    else:
        feedback_parts.append("✗ BW measurement not found")
    
    # ============================================================
    # CRITERION 3: BICAUDATE INDEX ACCURACY (20 points)
    # ============================================================
    bci_error = abs(agent_bci - gt_bci) if agent_bci > 0 and gt_bci > 0 else float('inf')
    details['bci_error'] = bci_error
    
    if bci_error <= bci_error_max:
        score += w_bci
        feedback_parts.append(f"✓ BCI accurate: {agent_bci:.4f} (GT: {gt_bci:.4f}, error: {bci_error:.4f})")
    elif bci_error <= bci_error_max * 2:
        partial = int(w_bci * 0.5)
        score += partial
        feedback_parts.append(f"~ BCI partially accurate: {agent_bci:.4f} (GT: {gt_bci:.4f}, error: {bci_error:.4f})")
    elif agent_bci > 0:
        feedback_parts.append(f"✗ BCI inaccurate: {agent_bci:.4f} (GT: {gt_bci:.4f}, error: {bci_error:.4f})")
    else:
        feedback_parts.append("✗ BCI not calculated/reported")
    
    # ============================================================
    # CRITERION 4: CLASSIFICATION CORRECT (15 points)
    # ============================================================
    # Determine expected classification from agent's BCI (if they got the ratio right)
    expected_class_from_agent_bci = classify_bci(agent_bci, clinical_thresholds) if agent_bci > 0 else ''
    
    classification_correct = False
    if agent_class:
        agent_class_normalized = agent_class.strip().title()
        gt_class_normalized = gt_class.strip().title()
        
        if agent_class_normalized == gt_class_normalized:
            classification_correct = True
            score += w_class
            feedback_parts.append(f"✓ Classification correct: {agent_class}")
        elif agent_class_normalized == expected_class_from_agent_bci:
            # Classification matches their BCI calculation (internally consistent)
            partial = int(w_class * 0.5)
            score += partial
            feedback_parts.append(f"~ Classification consistent with agent's BCI: {agent_class} (GT: {gt_class})")
        else:
            feedback_parts.append(f"✗ Classification incorrect: {agent_class} (GT: {gt_class})")
    else:
        feedback_parts.append("✗ Classification not provided")
    
    details['classification_correct'] = classification_correct
    
    # ============================================================
    # CRITERION 5: ANATOMICAL LEVEL (10 points)
    # ============================================================
    slice_error = abs(agent_slice - gt_slice) if agent_slice > 0 and gt_slice > 0 else float('inf')
    details['slice_error'] = slice_error
    
    if slice_error <= slice_error_max:
        score += w_level
        feedback_parts.append(f"✓ Correct anatomical level: slice {agent_slice} (GT: {gt_slice})")
    elif slice_error <= slice_error_max * 2:
        partial = int(w_level * 0.5)
        score += partial
        feedback_parts.append(f"~ Close anatomical level: slice {agent_slice} (GT: {gt_slice}, diff: {slice_error})")
    elif agent_slice > 0:
        feedback_parts.append(f"✗ Wrong anatomical level: slice {agent_slice} (GT: {gt_slice})")
    else:
        # Can't verify slice - give partial credit if measurements are reasonable
        if agent_ic > 0 and agent_bw > 0:
            partial = int(w_level * 0.3)
            score += partial
            feedback_parts.append("~ Slice not reported (partial credit for measurements)")
        else:
            feedback_parts.append("✗ Slice number not reported")
    
    # ============================================================
    # CRITERION 6: REPORT COMPLETENESS (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    required_fields = ['intercaudate_distance_mm', 'brain_width_mm', 'bicaudate_index', 'classification', 'slice_number']
    
    if report_exists:
        fields_present = 0
        if reported_ic > 0:
            fields_present += 1
        if reported_bw > 0:
            fields_present += 1
        if reported_bci > 0:
            fields_present += 1
        if reported_class:
            fields_present += 1
        if reported_slice > 0:
            fields_present += 1
        
        completeness_ratio = fields_present / len(required_fields)
        report_points = int(w_report * completeness_ratio)
        score += report_points
        
        if completeness_ratio == 1.0:
            feedback_parts.append("✓ Report complete with all required fields")
        else:
            feedback_parts.append(f"~ Report partially complete ({fields_present}/{len(required_fields)} fields)")
        
        details['report_completeness'] = completeness_ratio
    else:
        feedback_parts.append("✗ Report file not found")
        details['report_completeness'] = 0
    
    # ============================================================
    # FINAL SCORING AND PASS DETERMINATION
    # ============================================================
    
    # Key criteria: BCI accuracy must be achieved AND files must be created during task
    key_criteria_met = (bci_error <= bci_error_max * 2) and files_created_during_task
    
    # Pass threshold: 60 points with key criteria met
    passed = score >= 60 and key_criteria_met
    
    # Penalize if anti-gaming checks fail
    if not files_created_during_task:
        feedback_parts.append("⚠ Warning: Files may have existed before task")
        score = min(score, 40)  # Cap at 40 if no files created during task
    
    if not measurements_plausible and plausibility_issues:
        feedback_parts.append(f"⚠ Plausibility issues: {'; '.join(plausibility_issues)}")
        score = max(0, score - 10)  # Penalty for implausible values
    
    # Compile final result
    final_feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": min(100, max(0, score)),
        "feedback": final_feedback,
        "details": details,
        "subscores": {
            "intercaudate_accuracy": w_ic if ic_error <= ic_error_max else 0,
            "brain_width_accuracy": w_bw if bw_error <= bw_error_max else 0,
            "bci_accuracy": w_bci if bci_error <= bci_error_max else 0,
            "classification_correct": w_class if classification_correct else 0,
            "anatomical_level": w_level if slice_error <= slice_error_max else 0,
            "report_completeness": int(w_report * details.get('report_completeness', 0))
        }
    })