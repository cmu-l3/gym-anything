#!/usr/bin/env python3
"""
Verifier for intervertebral disc height assessment task.

VERIFICATION METRICS:
1. Anterior disc height accuracy (within 2mm)
2. Posterior disc height accuracy (within 2mm)
3. Vertebral body height measured (within 3mm)
4. DHI calculation correct (within 0.05)
5. Classification correct (Normal/Mild/Moderate/Severe)
6. Correct vertebral level (L4-L5)
7. Report completeness

Scoring (100 points total):
- Anterior height accuracy: 20 points
- Posterior height accuracy: 20 points  
- Vertebral height measured: 15 points
- DHI calculated correctly: 15 points
- Classification correct: 15 points
- Correct level (L4-L5): 10 points
- Report complete: 5 points
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


def parse_numeric(value):
    """Safely parse a numeric value from string or number."""
    if value is None or value == "":
        return None
    try:
        return float(value)
    except (ValueError, TypeError):
        return None


def classify_dhi(dhi):
    """Classify degeneration based on DHI value."""
    if dhi is None:
        return None
    if dhi > 0.40:
        return "Normal"
    elif dhi >= 0.30:
        return "Mild"
    elif dhi >= 0.20:
        return "Moderate"
    else:
        return "Severe"


def verify_disc_height_assessment(traj, env_info, task_info):
    """
    Verify disc height assessment task completion.
    
    Uses multi-criteria scoring with anti-gaming checks.
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
    
    # Tolerances
    ant_tol = thresholds.get('anterior_error_max_mm', 2.0)
    post_tol = thresholds.get('posterior_error_max_mm', 2.0)
    vert_tol = thresholds.get('vertebral_error_max_mm', 3.0)
    dhi_tol = thresholds.get('dhi_error_max', 0.05)
    
    # Scoring weights
    w_anterior = weights.get('anterior_accuracy', 20)
    w_posterior = weights.get('posterior_accuracy', 20)
    w_vertebral = weights.get('vertebral_measured', 15)
    w_dhi = weights.get('dhi_calculated', 15)
    w_classification = weights.get('classification_correct', 15)
    w_level = weights.get('correct_level', 10)
    w_report = weights.get('report_complete', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/disc_task_result.json", temp_result.name)
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
    # ANTI-GAMING: Check timestamps
    # ============================================================
    meas_created = result.get('measurement_created_during_task', False)
    report_created = result.get('report_created_during_task', False)
    
    if not meas_created and not report_created:
        details['anti_gaming'] = "No files created during task"
        # Don't immediately fail - agent may have worked but files existed
    
    # ============================================================
    # LOAD GROUND TRUTH
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/disc_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_measurements = gt_data.get('measurements', {})
    gt_anterior = gt_measurements.get('anterior_height_mm', 0)
    gt_posterior = gt_measurements.get('posterior_height_mm', 0)
    gt_vertebral = gt_measurements.get('vertebral_height_mm', 0)
    gt_dhi = gt_measurements.get('disc_height_index', 0)
    gt_classification = gt_data.get('classification', '')
    gt_level = gt_data.get('target_level', 'L4-L5')
    
    details['ground_truth'] = {
        'anterior_mm': gt_anterior,
        'posterior_mm': gt_posterior,
        'vertebral_mm': gt_vertebral,
        'dhi': gt_dhi,
        'classification': gt_classification,
        'level': gt_level
    }
    
    # ============================================================
    # EXTRACT AGENT'S VALUES
    # ============================================================
    reported = result.get('reported_values', {})
    
    agent_anterior = parse_numeric(reported.get('anterior_height_mm'))
    agent_posterior = parse_numeric(reported.get('posterior_height_mm'))
    agent_vertebral = parse_numeric(reported.get('vertebral_height_mm'))
    agent_dhi = parse_numeric(reported.get('disc_height_index'))
    agent_classification = reported.get('degeneration_grade', '')
    agent_level = reported.get('vertebral_level', '')
    
    details['agent_values'] = {
        'anterior_mm': agent_anterior,
        'posterior_mm': agent_posterior,
        'vertebral_mm': agent_vertebral,
        'dhi': agent_dhi,
        'classification': agent_classification,
        'level': agent_level
    }
    
    # ============================================================
    # CRITERION 1: Anterior Height Accuracy (20 points)
    # ============================================================
    if agent_anterior is not None and gt_anterior > 0:
        ant_error = abs(agent_anterior - gt_anterior)
        details['anterior_error_mm'] = ant_error
        
        if ant_error <= ant_tol:
            score += w_anterior
            feedback_parts.append(f"✓ Anterior height accurate ({agent_anterior:.1f}mm, error {ant_error:.1f}mm)")
        elif ant_error <= ant_tol * 2:
            # Partial credit
            partial = int(w_anterior * 0.5)
            score += partial
            feedback_parts.append(f"~ Anterior height close ({agent_anterior:.1f}mm, error {ant_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Anterior height inaccurate ({agent_anterior:.1f}mm vs {gt_anterior:.1f}mm)")
    else:
        feedback_parts.append("✗ Anterior height not measured")
    
    # ============================================================
    # CRITERION 2: Posterior Height Accuracy (20 points)
    # ============================================================
    if agent_posterior is not None and gt_posterior > 0:
        post_error = abs(agent_posterior - gt_posterior)
        details['posterior_error_mm'] = post_error
        
        if post_error <= post_tol:
            score += w_posterior
            feedback_parts.append(f"✓ Posterior height accurate ({agent_posterior:.1f}mm, error {post_error:.1f}mm)")
        elif post_error <= post_tol * 2:
            partial = int(w_posterior * 0.5)
            score += partial
            feedback_parts.append(f"~ Posterior height close ({agent_posterior:.1f}mm, error {post_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Posterior height inaccurate ({agent_posterior:.1f}mm vs {gt_posterior:.1f}mm)")
    else:
        feedback_parts.append("✗ Posterior height not measured")
    
    # ============================================================
    # CRITERION 3: Vertebral Height Measured (15 points)
    # ============================================================
    if agent_vertebral is not None and gt_vertebral > 0:
        vert_error = abs(agent_vertebral - gt_vertebral)
        details['vertebral_error_mm'] = vert_error
        
        if vert_error <= vert_tol:
            score += w_vertebral
            feedback_parts.append(f"✓ Vertebral height accurate ({agent_vertebral:.1f}mm)")
        elif vert_error <= vert_tol * 2:
            partial = int(w_vertebral * 0.5)
            score += partial
            feedback_parts.append(f"~ Vertebral height measured ({agent_vertebral:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Vertebral height inaccurate ({agent_vertebral:.1f}mm vs {gt_vertebral:.1f}mm)")
    else:
        feedback_parts.append("✗ Vertebral height not measured")
    
    # ============================================================
    # CRITERION 4: DHI Calculated (15 points)
    # ============================================================
    # Check if agent calculated DHI, or calculate from their measurements
    calculated_dhi = None
    if agent_anterior is not None and agent_posterior is not None and agent_vertebral is not None and agent_vertebral > 0:
        calculated_dhi = (agent_anterior + agent_posterior) / 2 / agent_vertebral
    
    dhi_to_check = agent_dhi if agent_dhi is not None else calculated_dhi
    
    if dhi_to_check is not None and gt_dhi > 0:
        dhi_error = abs(dhi_to_check - gt_dhi)
        details['dhi_error'] = dhi_error
        details['agent_dhi_used'] = dhi_to_check
        
        if dhi_error <= dhi_tol:
            score += w_dhi
            feedback_parts.append(f"✓ DHI calculated correctly ({dhi_to_check:.3f})")
        elif dhi_error <= dhi_tol * 2:
            partial = int(w_dhi * 0.5)
            score += partial
            feedback_parts.append(f"~ DHI close ({dhi_to_check:.3f} vs {gt_dhi:.3f})")
        else:
            feedback_parts.append(f"✗ DHI incorrect ({dhi_to_check:.3f} vs {gt_dhi:.3f})")
    else:
        feedback_parts.append("✗ DHI not calculated")
    
    # ============================================================
    # CRITERION 5: Classification Correct (15 points)
    # ============================================================
    # Determine expected classification from agent's DHI
    expected_class_from_agent = classify_dhi(dhi_to_check) if dhi_to_check else None
    
    if agent_classification:
        agent_class_normalized = agent_classification.strip().title()
        gt_class_normalized = gt_classification.strip().title()
        
        # Check against ground truth classification
        if agent_class_normalized == gt_class_normalized:
            score += w_classification
            feedback_parts.append(f"✓ Classification correct ({agent_class_normalized})")
        # Also accept if classification matches their own DHI calculation
        elif expected_class_from_agent and agent_class_normalized == expected_class_from_agent:
            partial = int(w_classification * 0.7)
            score += partial
            feedback_parts.append(f"~ Classification consistent with agent's DHI ({agent_class_normalized})")
        # Partial credit if off by one grade
        else:
            grades = ["Severe", "Moderate", "Mild", "Normal"]
            try:
                agent_idx = grades.index(agent_class_normalized)
                gt_idx = grades.index(gt_class_normalized)
                if abs(agent_idx - gt_idx) == 1:
                    partial = int(w_classification * 0.5)
                    score += partial
                    feedback_parts.append(f"~ Classification off by one grade ({agent_class_normalized} vs {gt_class_normalized})")
                else:
                    feedback_parts.append(f"✗ Classification incorrect ({agent_class_normalized} vs {gt_class_normalized})")
            except ValueError:
                feedback_parts.append(f"✗ Invalid classification value: {agent_classification}")
    else:
        feedback_parts.append("✗ Classification not provided")
    
    # ============================================================
    # CRITERION 6: Correct Level (10 points)
    # ============================================================
    if agent_level:
        agent_level_normalized = agent_level.upper().replace(" ", "").replace("-", "")
        gt_level_normalized = gt_level.upper().replace(" ", "").replace("-", "")
        
        if agent_level_normalized == gt_level_normalized or agent_level_normalized in gt_level_normalized:
            score += w_level
            feedback_parts.append(f"✓ Correct vertebral level ({agent_level})")
        # Partial credit for adjacent levels
        elif any(adj in agent_level_normalized for adj in ["L3L4", "L5S1", "L34", "L5S"]):
            partial = int(w_level * 0.5)
            score += partial
            feedback_parts.append(f"~ Adjacent vertebral level ({agent_level})")
        else:
            feedback_parts.append(f"✗ Incorrect vertebral level ({agent_level})")
    else:
        feedback_parts.append("✗ Vertebral level not specified")
    
    # ============================================================
    # CRITERION 7: Report Completeness (5 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_fields = 0
    required_fields = ['anterior_height_mm', 'posterior_height_mm', 'vertebral_height_mm', 
                       'disc_height_index', 'degeneration_grade', 'vertebral_level']
    
    for field in required_fields:
        if reported.get(field):
            report_fields += 1
    
    if report_exists and report_fields >= 5:
        score += w_report
        feedback_parts.append(f"✓ Report complete ({report_fields}/6 fields)")
    elif report_exists and report_fields >= 3:
        partial = int(w_report * 0.5)
        score += partial
        feedback_parts.append(f"~ Report partial ({report_fields}/6 fields)")
    elif result.get('measurement_exists', False):
        # Some credit for having measurements even without formal report
        partial = int(w_report * 0.3)
        score += partial
        feedback_parts.append(f"~ Measurements exist but report incomplete")
    else:
        feedback_parts.append("✗ No report or measurements found")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: At least one height measurement accurate AND measurements were made
    key_criteria_met = (
        result.get('measurement_exists', False) and
        (details.get('anterior_error_mm', float('inf')) <= ant_tol * 2 or
         details.get('posterior_error_mm', float('inf')) <= post_tol * 2)
    )
    
    passed = score >= 60 and key_criteria_met
    
    # Final feedback
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    })