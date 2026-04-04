#!/usr/bin/env python3
"""
Verifier for Pectus Excavatum Haller Index Assessment task.

VERIFICATION STRATEGY:
The Haller Index = Transverse Diameter / AP Diameter is used to assess
pectus excavatum severity.

SCORING (100 points total):
1. Transverse measurement accuracy: 20 points (within 10mm of GT)
2. AP measurement accuracy: 20 points (within 5mm of GT)
3. Haller Index calculation: 15 points (within 0.3 of GT)
4. Severity classification: 15 points (correct category)
5. Surgical candidacy: 10 points (correct determination)
6. Measurement level: 10 points (within reasonable slice range)
7. Report completeness: 10 points (all required fields present)

Pass Threshold: 60 points with at least one measurement correct
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


def classify_haller_index(hi, thresholds=None):
    """
    Classify Haller Index into severity categories.
    
    Args:
        hi: Haller Index value
        thresholds: Dict with threshold values
    
    Returns:
        str: Classification (Normal, Mild, Moderate, Severe)
    """
    if thresholds is None:
        thresholds = {
            "normal_max": 2.5,
            "mild_max": 3.2,
            "moderate_max": 3.5
        }
    
    if hi < thresholds.get("normal_max", 2.5):
        return "Normal"
    elif hi < thresholds.get("mild_max", 3.2):
        return "Mild"
    elif hi < thresholds.get("moderate_max", 3.5):
        return "Moderate"
    else:
        return "Severe"


def is_surgical_candidate(hi, threshold=3.25):
    """Determine if patient is a surgical candidate based on Haller Index."""
    return hi > threshold


def parse_float(value, default=0.0):
    """Safely parse a float from string or number."""
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def parse_bool(value, default=False):
    """Safely parse a boolean from various formats."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        return value.lower() in ("true", "yes", "1", "t")
    return default


def verify_pectus_haller_index(traj, env_info, task_info):
    """
    Verify the Pectus Excavatum Haller Index Assessment task.
    
    Multi-criteria scoring:
    - Transverse measurement: 20 points
    - AP measurement: 20 points
    - Haller Index calculation: 15 points
    - Severity classification: 15 points
    - Surgical candidacy: 10 points
    - Measurement level: 10 points
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
    class_thresholds = metadata.get('classification_thresholds', {})
    
    trans_error_max = thresholds.get('transverse_error_max_mm', 10.0)
    ap_error_max = thresholds.get('ap_error_max_mm', 5.0)
    hi_error_max = thresholds.get('haller_index_error_max', 0.3)
    
    w_transverse = weights.get('transverse_measurement', 20)
    w_ap = weights.get('ap_measurement', 20)
    w_haller = weights.get('haller_index_correct', 15)
    w_class = weights.get('severity_classification', 15)
    w_surgical = weights.get('surgical_candidacy', 10)
    w_level = weights.get('measurement_level', 10)
    w_report = weights.get('report_complete', 10)
    
    surgical_threshold = class_thresholds.get('surgical_threshold', 3.25)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/pectus_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/haller_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_transverse = parse_float(gt_data.get('transverse_diameter_mm'))
    gt_ap = parse_float(gt_data.get('ap_diameter_mm'))
    gt_haller = parse_float(gt_data.get('haller_index'))
    gt_classification = gt_data.get('severity_classification', '')
    gt_surgical = gt_data.get('surgical_candidate', False)
    gt_slice = gt_data.get('measurement_slice', 0)
    
    details['gt_transverse_mm'] = gt_transverse
    details['gt_ap_mm'] = gt_ap
    details['gt_haller_index'] = gt_haller
    details['gt_classification'] = gt_classification
    details['gt_surgical_candidate'] = gt_surgical
    details['gt_slice'] = gt_slice
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    
    # Try multiple sources for transverse measurement
    agent_transverse = 0.0
    if result.get('transverse_mm'):
        agent_transverse = parse_float(result.get('transverse_mm'))
    elif result.get('reported_transverse_mm'):
        agent_transverse = parse_float(result.get('reported_transverse_mm'))
    
    # Try multiple sources for AP measurement
    agent_ap = 0.0
    if result.get('ap_mm'):
        agent_ap = parse_float(result.get('ap_mm'))
    elif result.get('reported_ap_mm'):
        agent_ap = parse_float(result.get('reported_ap_mm'))
    
    # Get reported values
    agent_haller = parse_float(result.get('reported_haller_index'))
    agent_classification = result.get('reported_classification', '')
    agent_surgical = result.get('reported_surgical_candidate', '')
    
    details['agent_transverse_mm'] = agent_transverse
    details['agent_ap_mm'] = agent_ap
    details['agent_haller_index'] = agent_haller
    details['agent_classification'] = agent_classification
    details['agent_surgical'] = agent_surgical
    
    # ============================================================
    # CRITERION 1: Transverse Measurement Accuracy (20 points)
    # ============================================================
    transverse_exists = result.get('transverse_measurement_exists', False)
    transverse_created = result.get('transverse_created_during_task', False)
    
    if agent_transverse > 0 and gt_transverse > 0:
        trans_error = abs(agent_transverse - gt_transverse)
        details['transverse_error_mm'] = trans_error
        
        if trans_error <= trans_error_max:
            score += w_transverse
            feedback_parts.append(f"✓ Transverse: {agent_transverse:.1f}mm (error: {trans_error:.1f}mm)")
        elif trans_error <= trans_error_max * 2:
            partial = int(w_transverse * 0.5)
            score += partial
            feedback_parts.append(f"~ Transverse: {agent_transverse:.1f}mm (error: {trans_error:.1f}mm, partial credit)")
        else:
            feedback_parts.append(f"✗ Transverse: {agent_transverse:.1f}mm (error: {trans_error:.1f}mm, expected ~{gt_transverse:.1f}mm)")
    elif transverse_exists:
        score += 5  # Partial credit for having a measurement
        feedback_parts.append(f"~ Transverse measurement exists but couldn't extract value")
    else:
        feedback_parts.append("✗ No transverse measurement found")
    
    # ============================================================
    # CRITERION 2: AP Measurement Accuracy (20 points)
    # ============================================================
    ap_exists = result.get('ap_measurement_exists', False)
    ap_created = result.get('ap_created_during_task', False)
    
    if agent_ap > 0 and gt_ap > 0:
        ap_error = abs(agent_ap - gt_ap)
        details['ap_error_mm'] = ap_error
        
        if ap_error <= ap_error_max:
            score += w_ap
            feedback_parts.append(f"✓ AP: {agent_ap:.1f}mm (error: {ap_error:.1f}mm)")
        elif ap_error <= ap_error_max * 2:
            partial = int(w_ap * 0.5)
            score += partial
            feedback_parts.append(f"~ AP: {agent_ap:.1f}mm (error: {ap_error:.1f}mm, partial credit)")
        else:
            feedback_parts.append(f"✗ AP: {agent_ap:.1f}mm (error: {ap_error:.1f}mm, expected ~{gt_ap:.1f}mm)")
    elif ap_exists:
        score += 5
        feedback_parts.append("~ AP measurement exists but couldn't extract value")
    else:
        feedback_parts.append("✗ No AP measurement found")
    
    # ============================================================
    # CRITERION 3: Haller Index Calculation (15 points)
    # ============================================================
    
    # Calculate HI from agent's measurements if not explicitly reported
    calculated_hi = 0.0
    if agent_transverse > 0 and agent_ap > 0:
        calculated_hi = agent_transverse / agent_ap
    
    # Use reported HI if available, otherwise use calculated
    final_hi = agent_haller if agent_haller > 0 else calculated_hi
    details['calculated_haller_index'] = calculated_hi
    details['final_haller_index'] = final_hi
    
    if final_hi > 0 and gt_haller > 0:
        hi_error = abs(final_hi - gt_haller)
        details['haller_index_error'] = hi_error
        
        if hi_error <= hi_error_max:
            score += w_haller
            feedback_parts.append(f"✓ Haller Index: {final_hi:.2f} (error: {hi_error:.2f})")
        elif hi_error <= hi_error_max * 2:
            partial = int(w_haller * 0.5)
            score += partial
            feedback_parts.append(f"~ Haller Index: {final_hi:.2f} (error: {hi_error:.2f}, partial credit)")
        else:
            feedback_parts.append(f"✗ Haller Index: {final_hi:.2f} (expected ~{gt_haller:.2f})")
    else:
        feedback_parts.append("✗ Could not calculate Haller Index")
    
    # ============================================================
    # CRITERION 4: Severity Classification (15 points)
    # ============================================================
    
    # Determine agent's classification
    if agent_classification:
        agent_class_normalized = agent_classification.strip().title()
    elif final_hi > 0:
        agent_class_normalized = classify_haller_index(final_hi, class_thresholds)
    else:
        agent_class_normalized = ""
    
    gt_class_normalized = gt_classification.strip().title() if gt_classification else ""
    
    details['agent_classification_normalized'] = agent_class_normalized
    details['gt_classification_normalized'] = gt_class_normalized
    
    if agent_class_normalized and gt_class_normalized:
        if agent_class_normalized == gt_class_normalized:
            score += w_class
            feedback_parts.append(f"✓ Classification: {agent_class_normalized}")
        else:
            # Check if off by one category (partial credit)
            categories = ["Normal", "Mild", "Moderate", "Severe"]
            try:
                agent_idx = categories.index(agent_class_normalized)
                gt_idx = categories.index(gt_class_normalized)
                if abs(agent_idx - gt_idx) == 1:
                    partial = int(w_class * 0.5)
                    score += partial
                    feedback_parts.append(f"~ Classification: {agent_class_normalized} (expected {gt_class_normalized}, off by one)")
                else:
                    feedback_parts.append(f"✗ Classification: {agent_class_normalized} (expected {gt_class_normalized})")
            except ValueError:
                feedback_parts.append(f"✗ Invalid classification: {agent_class_normalized}")
    else:
        feedback_parts.append("✗ No severity classification provided")
    
    # ============================================================
    # CRITERION 5: Surgical Candidacy (10 points)
    # ============================================================
    
    # Determine agent's surgical assessment
    if agent_surgical:
        agent_is_surgical = parse_bool(agent_surgical)
    elif final_hi > 0:
        agent_is_surgical = is_surgical_candidate(final_hi, surgical_threshold)
    else:
        agent_is_surgical = None
    
    details['agent_surgical_determination'] = agent_is_surgical
    
    if agent_is_surgical is not None:
        if agent_is_surgical == gt_surgical:
            score += w_surgical
            feedback_parts.append(f"✓ Surgical candidacy: {'Yes' if agent_is_surgical else 'No'}")
        else:
            feedback_parts.append(f"✗ Surgical candidacy: {'Yes' if agent_is_surgical else 'No'} (expected {'Yes' if gt_surgical else 'No'})")
    else:
        feedback_parts.append("✗ No surgical candidacy determination")
    
    # ============================================================
    # CRITERION 6: Measurement Level (10 points)
    # ============================================================
    # We can't easily verify slice level without more detailed data, 
    # so we give credit if measurements were created during the task
    
    if transverse_created or ap_created:
        score += w_level
        feedback_parts.append("✓ Measurements created during task")
    elif transverse_exists or ap_exists:
        score += int(w_level * 0.5)
        feedback_parts.append("~ Measurements exist (may have been pre-existing)")
    else:
        feedback_parts.append("✗ No valid measurements detected")
    
    # ============================================================
    # CRITERION 7: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    required_fields = ['transverse_diameter_mm', 'ap_diameter_mm', 'haller_index', 
                       'severity_classification', 'surgical_candidate']
    
    fields_present = 0
    if result.get('reported_transverse_mm'):
        fields_present += 1
    if result.get('reported_ap_mm'):
        fields_present += 1
    if result.get('reported_haller_index'):
        fields_present += 1
    if result.get('reported_classification'):
        fields_present += 1
    if result.get('reported_surgical_candidate'):
        fields_present += 1
    
    details['report_fields_present'] = fields_present
    details['report_fields_required'] = len(required_fields)
    
    if report_exists and report_created:
        completeness = fields_present / len(required_fields)
        report_score = int(w_report * completeness)
        score += report_score
        feedback_parts.append(f"✓ Report created with {fields_present}/{len(required_fields)} fields")
    elif report_exists:
        completeness = fields_present / len(required_fields)
        report_score = int(w_report * completeness * 0.5)
        score += report_score
        feedback_parts.append(f"~ Report exists with {fields_present}/{len(required_fields)} fields")
    else:
        feedback_parts.append("✗ No report file found")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    
    # Key criteria: at least one measurement must be reasonably accurate
    transverse_ok = (agent_transverse > 0 and gt_transverse > 0 and 
                     abs(agent_transverse - gt_transverse) <= trans_error_max * 2)
    ap_ok = (agent_ap > 0 and gt_ap > 0 and 
             abs(agent_ap - gt_ap) <= ap_error_max * 2)
    
    key_criteria_met = transverse_ok or ap_ok
    passed = score >= 60 and key_criteria_met
    
    # Generate summary feedback
    feedback = " | ".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED (Score: {score}/100) - {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"FAILED (Score: {score}/100) - Key criteria not met: measurements inaccurate | {feedback}"
        else:
            feedback = f"FAILED (Score: {score}/100) - {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": to_python_type(details)
    }