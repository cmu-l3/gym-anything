#!/usr/bin/env python3
"""
Verifier for Sylvian Fissure Asymmetry Assessment task.

VERIFICATION STRATEGY:
1. Measurement accuracy - compare agent's measurements to ground truth
2. Calculation correctness - verify SFAI formula was applied correctly
3. Classification correctness - verify clinical category assignment
4. Bilateral consistency - measurements at similar z-levels
5. Report completeness - all required fields present

Scoring (100 points total):
- Left measurement accuracy: 20 points
- Right measurement accuracy: 20 points
- Level consistency: 10 points
- SFAI calculation correct: 15 points
- Classification correct: 15 points
- Wider side correct: 10 points
- Markup files present: 5 points
- Report complete: 5 points
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


def safe_float(value, default=0.0):
    """Safely convert a value to float."""
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def calculate_sfai(left_mm, right_mm):
    """Calculate Sylvian Fissure Asymmetry Index."""
    if left_mm <= 0 or right_mm <= 0:
        return 0.0
    mean_width = (left_mm + right_mm) / 2
    if mean_width == 0:
        return 0.0
    return abs(left_mm - right_mm) / mean_width * 100


def classify_sfai(sfai_percent):
    """Classify asymmetry based on SFAI percentage."""
    if sfai_percent < 15:
        return "Symmetric"
    elif sfai_percent < 25:
        return "Mildly Asymmetric"
    else:
        return "Significantly Asymmetric"


def determine_wider_side(left_mm, right_mm, sfai_percent):
    """Determine which side is wider."""
    if sfai_percent < 15:
        return "symmetric"
    return "left" if left_mm > right_mm else "right"


def verify_sylvian_asymmetry(traj, env_info, task_info):
    """
    Verify Sylvian fissure asymmetry assessment task completion.
    
    Returns:
        dict with 'passed', 'score', 'feedback', and 'details'
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
    
    measurement_error_max = thresholds.get('measurement_error_max_mm', 3.0)
    sfai_error_max = thresholds.get('sfai_calculation_error_max_percent', 1.0)
    level_diff_max = thresholds.get('level_difference_max_mm', 5.0)
    
    w_left = weights.get('left_measurement_accuracy', 20)
    w_right = weights.get('right_measurement_accuracy', 20)
    w_level = weights.get('level_consistency', 10)
    w_sfai = weights.get('sfai_calculation_correct', 15)
    w_classification = weights.get('classification_correct', 15)
    w_wider = weights.get('wider_side_correct', 10)
    w_markup = weights.get('markup_files_present', 5)
    w_report = weights.get('report_complete', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/sylvian_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/sylvian_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_left = gt_data.get('left_width_mm', 0)
    gt_right = gt_data.get('right_width_mm', 0)
    gt_sfai = gt_data.get('asymmetry_index_percent', 0)
    gt_classification = gt_data.get('classification', '')
    gt_wider_side = gt_data.get('wider_side', '')
    gt_z_mm = gt_data.get('measurement_z_mm', 0)
    
    details['gt_left_mm'] = gt_left
    details['gt_right_mm'] = gt_right
    details['gt_sfai_percent'] = gt_sfai
    details['gt_classification'] = gt_classification
    details['gt_wider_side'] = gt_wider_side
    
    # ============================================================
    # EXTRACT AGENT'S VALUES
    # ============================================================
    # Try to get measurements from report first, then from markup extraction
    agent_left = safe_float(result.get('reported_left_width_mm') or result.get('left_width_mm'), 0)
    agent_right = safe_float(result.get('reported_right_width_mm') or result.get('right_width_mm'), 0)
    agent_sfai = safe_float(result.get('reported_asymmetry_index'), 0)
    agent_classification = result.get('reported_classification', '').strip()
    agent_wider_side = result.get('reported_wider_side', '').strip().lower()
    
    details['agent_left_mm'] = agent_left
    details['agent_right_mm'] = agent_right
    details['agent_sfai_percent'] = agent_sfai
    details['agent_classification'] = agent_classification
    details['agent_wider_side'] = agent_wider_side
    
    # ============================================================
    # CRITERION 1: Left Measurement Accuracy (20 points)
    # ============================================================
    left_meas_exists = result.get('left_measurement_exists', False)
    
    if agent_left > 0:
        left_error = abs(agent_left - gt_left)
        details['left_error_mm'] = left_error
        
        if left_error <= measurement_error_max:
            score += w_left
            feedback_parts.append(f"✓ Left measurement accurate ({agent_left:.1f}mm, error {left_error:.1f}mm)")
        elif left_error <= measurement_error_max * 2:
            partial = int(w_left * 0.5)
            score += partial
            feedback_parts.append(f"~ Left measurement partially accurate ({agent_left:.1f}mm, error {left_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Left measurement inaccurate ({agent_left:.1f}mm vs GT {gt_left:.1f}mm)")
    else:
        feedback_parts.append("✗ No left measurement found")
    
    # ============================================================
    # CRITERION 2: Right Measurement Accuracy (20 points)
    # ============================================================
    right_meas_exists = result.get('right_measurement_exists', False)
    
    if agent_right > 0:
        right_error = abs(agent_right - gt_right)
        details['right_error_mm'] = right_error
        
        if right_error <= measurement_error_max:
            score += w_right
            feedback_parts.append(f"✓ Right measurement accurate ({agent_right:.1f}mm, error {right_error:.1f}mm)")
        elif right_error <= measurement_error_max * 2:
            partial = int(w_right * 0.5)
            score += partial
            feedback_parts.append(f"~ Right measurement partially accurate ({agent_right:.1f}mm, error {right_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Right measurement inaccurate ({agent_right:.1f}mm vs GT {gt_right:.1f}mm)")
    else:
        feedback_parts.append("✗ No right measurement found")
    
    # ============================================================
    # CRITERION 3: Level Consistency (10 points)
    # Both measurements should be at similar axial levels
    # ============================================================
    if left_meas_exists and right_meas_exists:
        # If we have z-position info, check consistency
        # For now, award points if both measurements exist
        score += w_level
        feedback_parts.append("✓ Both sides measured (assumed consistent level)")
        details['level_consistent'] = True
    else:
        feedback_parts.append("✗ Missing bilateral measurements for level check")
        details['level_consistent'] = False
    
    # ============================================================
    # CRITERION 4: SFAI Calculation Correct (15 points)
    # ============================================================
    if agent_left > 0 and agent_right > 0:
        # Calculate what SFAI should be given agent's measurements
        expected_sfai = calculate_sfai(agent_left, agent_right)
        details['expected_sfai_from_measurements'] = expected_sfai
        
        if agent_sfai > 0:
            sfai_calculation_error = abs(agent_sfai - expected_sfai)
            details['sfai_calculation_error'] = sfai_calculation_error
            
            if sfai_calculation_error <= sfai_error_max:
                score += w_sfai
                feedback_parts.append(f"✓ SFAI calculation correct ({agent_sfai:.1f}%)")
            elif sfai_calculation_error <= sfai_error_max * 3:
                partial = int(w_sfai * 0.5)
                score += partial
                feedback_parts.append(f"~ SFAI calculation close ({agent_sfai:.1f}% vs expected {expected_sfai:.1f}%)")
            else:
                feedback_parts.append(f"✗ SFAI calculation incorrect ({agent_sfai:.1f}% vs expected {expected_sfai:.1f}%)")
        else:
            # Agent didn't report SFAI - calculate it ourselves and give partial credit
            agent_sfai = expected_sfai
            partial = int(w_sfai * 0.3)
            score += partial
            feedback_parts.append(f"~ SFAI not reported (calculated: {expected_sfai:.1f}%)")
    else:
        feedback_parts.append("✗ Cannot verify SFAI - missing measurements")
    
    # ============================================================
    # CRITERION 5: Classification Correct (15 points)
    # ============================================================
    if agent_classification:
        # Normalize classification strings for comparison
        agent_class_norm = agent_classification.lower().replace('_', ' ').strip()
        gt_class_norm = gt_classification.lower().replace('_', ' ').strip()
        
        # Check for match (allow partial matches)
        class_correct = False
        if agent_class_norm == gt_class_norm:
            class_correct = True
        elif 'symmetric' in agent_class_norm and 'symmetric' in gt_class_norm:
            # Both say symmetric in some form
            if ('mild' in agent_class_norm) == ('mild' in gt_class_norm) and \
               ('significant' in agent_class_norm) == ('significant' in gt_class_norm):
                class_correct = True
        
        if class_correct:
            score += w_classification
            feedback_parts.append(f"✓ Classification correct ({agent_classification})")
        else:
            # Check if agent's classification matches what their measurements suggest
            agent_suggested_class = classify_sfai(agent_sfai if agent_sfai > 0 else calculate_sfai(agent_left, agent_right))
            if agent_class_norm == agent_suggested_class.lower():
                partial = int(w_classification * 0.5)
                score += partial
                feedback_parts.append(f"~ Classification consistent with measurements but differs from GT")
            else:
                feedback_parts.append(f"✗ Classification incorrect ({agent_classification} vs {gt_classification})")
    else:
        feedback_parts.append("✗ No classification provided")
    
    # ============================================================
    # CRITERION 6: Wider Side Correct (10 points)
    # ============================================================
    if agent_wider_side:
        wider_correct = (agent_wider_side == gt_wider_side.lower())
        
        # Also accept if classification is symmetric and agent says symmetric
        if not wider_correct and gt_wider_side.lower() == 'symmetric' and \
           agent_wider_side in ['symmetric', 'none', 'equal', 'n/a']:
            wider_correct = True
        
        if wider_correct:
            score += w_wider
            feedback_parts.append(f"✓ Wider side correct ({agent_wider_side})")
        else:
            # Check if consistent with agent's own measurements
            if agent_left > 0 and agent_right > 0:
                agent_suggested_wider = determine_wider_side(agent_left, agent_right, agent_sfai)
                if agent_wider_side == agent_suggested_wider:
                    partial = int(w_wider * 0.5)
                    score += partial
                    feedback_parts.append(f"~ Wider side consistent with measurements but differs from GT")
                else:
                    feedback_parts.append(f"✗ Wider side incorrect ({agent_wider_side} vs {gt_wider_side})")
            else:
                feedback_parts.append(f"✗ Wider side incorrect ({agent_wider_side} vs {gt_wider_side})")
    else:
        feedback_parts.append("✗ Wider side not specified")
    
    # ============================================================
    # CRITERION 7: Markup Files Present (5 points)
    # ============================================================
    if left_meas_exists and right_meas_exists:
        score += w_markup
        feedback_parts.append("✓ Both markup files present")
    elif left_meas_exists or right_meas_exists:
        partial = int(w_markup * 0.5)
        score += partial
        feedback_parts.append("~ One markup file present")
    else:
        feedback_parts.append("✗ No markup files found")
    
    # ============================================================
    # CRITERION 8: Report Completeness (5 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    if report_exists:
        # Check how many required fields are present
        required_fields = ['left_width_mm', 'right_width_mm', 'asymmetry_index_percent', 
                          'classification', 'wider_side', 'measurement_level']
        fields_present = sum([
            bool(result.get('reported_left_width_mm')),
            bool(result.get('reported_right_width_mm')),
            bool(result.get('reported_asymmetry_index')),
            bool(result.get('reported_classification')),
            bool(result.get('reported_wider_side')),
            bool(result.get('reported_level'))
        ])
        
        completeness = fields_present / len(required_fields)
        report_score = int(w_report * completeness)
        score += report_score
        
        if completeness >= 0.8:
            feedback_parts.append(f"✓ Report complete ({fields_present}/{len(required_fields)} fields)")
        elif completeness >= 0.5:
            feedback_parts.append(f"~ Report partially complete ({fields_present}/{len(required_fields)} fields)")
        else:
            feedback_parts.append(f"✗ Report incomplete ({fields_present}/{len(required_fields)} fields)")
    else:
        feedback_parts.append("✗ No report file found")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: at least one measurement within tolerance
    key_criteria_met = False
    if agent_left > 0 and agent_right > 0:
        left_ok = abs(agent_left - gt_left) <= measurement_error_max
        right_ok = abs(agent_right - gt_right) <= measurement_error_max
        key_criteria_met = left_ok or right_ok
    
    passed = score >= 60 and key_criteria_met
    
    # Build final feedback
    feedback = f"Score: {score}/100 | " + " | ".join(feedback_parts[:5])
    if len(feedback_parts) > 5:
        feedback += f" | (+{len(feedback_parts)-5} more criteria)"
    
    # Convert all numpy types
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }