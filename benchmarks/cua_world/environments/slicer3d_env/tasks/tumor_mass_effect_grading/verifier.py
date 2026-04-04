#!/usr/bin/env python3
"""
Verifier for Brain Tumor Mass Effect Grading task.

VERIFICATION METRICS:
1. Midline shift measurement accuracy (within 4mm of expected)
2. Ventricular compression ratio accuracy (within 0.2)
3. Herniation assessment (correct Present/Absent)
4. Sulcal effacement score (within 1 point)
5. Overall grade (must match expected)
6. Report completeness
7. Screenshots created

Scoring (100 points total):
- Midline shift accurate: 25 points
- Ventricular ratio accurate: 20 points
- Herniation assessment correct: 15 points
- Sulcal effacement score: 10 points
- Overall grade correct: 15 points
- Report completeness: 10 points
- Screenshots present: 5 points

Pass threshold: 60 points with midline shift present
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


def parse_float(value, default=None):
    """Safely parse a float from various input types."""
    if value is None or value == "":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def parse_int(value, default=None):
    """Safely parse an int from various input types."""
    if value is None or value == "":
        return default
    try:
        return int(float(value))
    except (ValueError, TypeError):
        return default


def normalize_string(s):
    """Normalize string for comparison."""
    if s is None:
        return ""
    return str(s).strip().lower()


def verify_mass_effect_grading(traj, env_info, task_info):
    """
    Verify brain tumor mass effect grading task completion.
    
    Uses copy_from_env to read exported results and ground truth.
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
    
    midline_error_max = thresholds.get('midline_shift_error_max_mm', 4.0)
    vent_ratio_error_max = thresholds.get('ventricular_ratio_error_max', 0.2)
    
    w_midline = weights.get('midline_shift_accurate', 25)
    w_vent_ratio = weights.get('ventricular_ratio_accurate', 20)
    w_herniation = weights.get('herniation_assessment', 15)
    w_sulcal = weights.get('sulcal_effacement_score', 10)
    w_grade = weights.get('overall_grade_correct', 15)
    w_report = weights.get('report_complete', 10)
    w_screenshots = weights.get('screenshots_present', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/mass_effect_task_result.json", temp_result.name)
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
        copy_from_env("/tmp/mass_effect_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
    
    gt_midline_shift = gt_data.get('expected_midline_shift_mm', 0)
    gt_vent_ratio = gt_data.get('expected_ventricular_ratio', 1.0)
    gt_subfalcine = gt_data.get('expected_subfalcine_herniation', 'Absent')
    gt_uncal = gt_data.get('expected_uncal_herniation', 'Absent')
    gt_sulcal = gt_data.get('expected_sulcal_effacement', 0)
    gt_grade = gt_data.get('expected_overall_grade', 'Mild')
    
    details['ground_truth'] = {
        'midline_shift_mm': gt_midline_shift,
        'ventricular_ratio': gt_vent_ratio,
        'subfalcine_herniation': gt_subfalcine,
        'uncal_herniation': gt_uncal,
        'sulcal_effacement': gt_sulcal,
        'overall_grade': gt_grade
    }
    
    # ============================================================
    # EXTRACT AGENT'S MEASUREMENTS
    # ============================================================
    agent_midline = parse_float(result.get('reported_midline_shift_mm'))
    agent_vent_ratio = parse_float(result.get('reported_ventricular_ratio'))
    agent_subfalcine = result.get('reported_subfalcine_herniation', '')
    agent_uncal = result.get('reported_uncal_herniation', '')
    agent_sulcal = parse_int(result.get('reported_sulcal_effacement'))
    agent_grade = result.get('reported_grade', '')
    
    details['agent_reported'] = {
        'midline_shift_mm': agent_midline,
        'ventricular_ratio': agent_vent_ratio,
        'subfalcine_herniation': agent_subfalcine,
        'uncal_herniation': agent_uncal,
        'sulcal_effacement': agent_sulcal,
        'overall_grade': agent_grade
    }
    
    # ============================================================
    # CRITERION 1: Midline Shift Accuracy (25 points)
    # ============================================================
    midline_accurate = False
    if agent_midline is not None:
        midline_error = abs(agent_midline - gt_midline_shift)
        details['midline_error_mm'] = round(midline_error, 2)
        
        if midline_error <= midline_error_max:
            score += w_midline
            midline_accurate = True
            feedback_parts.append(f"✓ Midline shift accurate ({agent_midline:.1f}mm, error {midline_error:.1f}mm)")
        elif midline_error <= midline_error_max * 2:
            # Partial credit
            partial = w_midline * 0.5
            score += partial
            feedback_parts.append(f"~ Midline shift partially accurate ({agent_midline:.1f}mm, error {midline_error:.1f}mm)")
        else:
            feedback_parts.append(f"✗ Midline shift inaccurate ({agent_midline:.1f}mm vs expected {gt_midline_shift:.1f}mm)")
    else:
        feedback_parts.append("✗ Midline shift not measured")
    
    # ============================================================
    # CRITERION 2: Ventricular Ratio Accuracy (20 points)
    # ============================================================
    if agent_vent_ratio is not None:
        vent_ratio_error = abs(agent_vent_ratio - gt_vent_ratio)
        details['ventricular_ratio_error'] = round(vent_ratio_error, 3)
        
        if vent_ratio_error <= vent_ratio_error_max:
            score += w_vent_ratio
            feedback_parts.append(f"✓ Ventricular ratio accurate ({agent_vent_ratio:.2f})")
        elif vent_ratio_error <= vent_ratio_error_max * 2:
            partial = w_vent_ratio * 0.5
            score += partial
            feedback_parts.append(f"~ Ventricular ratio partially accurate ({agent_vent_ratio:.2f})")
        else:
            # Check if compression determination is correct (ratio < 0.7 indicates compression)
            agent_compressed = agent_vent_ratio < 0.7
            gt_compressed = gt_vent_ratio < 0.7
            if agent_compressed == gt_compressed:
                score += w_vent_ratio * 0.3
                feedback_parts.append(f"~ Compression determination correct, ratio value off ({agent_vent_ratio:.2f})")
            else:
                feedback_parts.append(f"✗ Ventricular ratio inaccurate ({agent_vent_ratio:.2f} vs expected {gt_vent_ratio:.2f})")
    else:
        feedback_parts.append("✗ Ventricular ratio not calculated")
    
    # ============================================================
    # CRITERION 3: Herniation Assessment (15 points)
    # ============================================================
    herniation_score = 0
    
    # Subfalcine herniation (10 points)
    if agent_subfalcine:
        agent_subfalcine_norm = normalize_string(agent_subfalcine)
        gt_subfalcine_norm = normalize_string(gt_subfalcine)
        
        if agent_subfalcine_norm == gt_subfalcine_norm:
            herniation_score += 10
            feedback_parts.append(f"✓ Subfalcine herniation correct ({agent_subfalcine})")
        elif agent_subfalcine_norm in ['present', 'absent'] and gt_subfalcine_norm in ['present', 'absent']:
            feedback_parts.append(f"✗ Subfalcine herniation wrong ({agent_subfalcine} vs {gt_subfalcine})")
        else:
            # Partial credit for attempting
            herniation_score += 3
            feedback_parts.append(f"~ Subfalcine herniation unclear ({agent_subfalcine})")
    else:
        feedback_parts.append("✗ Subfalcine herniation not assessed")
    
    # Uncal herniation (5 points)
    if agent_uncal:
        agent_uncal_norm = normalize_string(agent_uncal)
        gt_uncal_norm = normalize_string(gt_uncal)
        
        if agent_uncal_norm == gt_uncal_norm:
            herniation_score += 5
            feedback_parts.append(f"✓ Uncal herniation correct ({agent_uncal})")
        else:
            feedback_parts.append(f"✗ Uncal herniation wrong ({agent_uncal} vs {gt_uncal})")
    else:
        feedback_parts.append("✗ Uncal herniation not assessed")
    
    score += herniation_score
    
    # ============================================================
    # CRITERION 4: Sulcal Effacement Score (10 points)
    # ============================================================
    if agent_sulcal is not None:
        sulcal_error = abs(agent_sulcal - gt_sulcal)
        
        if sulcal_error == 0:
            score += w_sulcal
            feedback_parts.append(f"✓ Sulcal effacement score correct ({agent_sulcal})")
        elif sulcal_error == 1:
            score += w_sulcal * 0.5
            feedback_parts.append(f"~ Sulcal effacement score close ({agent_sulcal} vs expected {gt_sulcal})")
        else:
            feedback_parts.append(f"✗ Sulcal effacement score wrong ({agent_sulcal} vs expected {gt_sulcal})")
    else:
        feedback_parts.append("✗ Sulcal effacement not scored")
    
    # ============================================================
    # CRITERION 5: Overall Grade Correct (15 points)
    # ============================================================
    if agent_grade:
        agent_grade_norm = normalize_string(agent_grade)
        gt_grade_norm = normalize_string(gt_grade)
        
        if agent_grade_norm == gt_grade_norm:
            score += w_grade
            feedback_parts.append(f"✓ Overall grade correct ({agent_grade})")
        else:
            # Check if adjacent grade (partial credit)
            grade_order = ['mild', 'moderate', 'severe']
            try:
                agent_idx = grade_order.index(agent_grade_norm)
                gt_idx = grade_order.index(gt_grade_norm)
                if abs(agent_idx - gt_idx) == 1:
                    score += w_grade * 0.4
                    feedback_parts.append(f"~ Overall grade one level off ({agent_grade} vs {gt_grade})")
                else:
                    feedback_parts.append(f"✗ Overall grade wrong ({agent_grade} vs expected {gt_grade})")
            except ValueError:
                feedback_parts.append(f"✗ Overall grade invalid ({agent_grade})")
    else:
        feedback_parts.append("✗ Overall grade not provided")
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    report_created_during_task = result.get('report_created_during_task', False)
    
    report_fields_present = sum([
        agent_midline is not None,
        agent_vent_ratio is not None,
        bool(agent_subfalcine),
        agent_sulcal is not None,
        bool(agent_uncal),
        bool(agent_grade)
    ])
    
    if report_exists and report_created_during_task:
        if report_fields_present >= 5:
            score += w_report
            feedback_parts.append(f"✓ Report complete ({report_fields_present}/6 fields)")
        elif report_fields_present >= 3:
            score += w_report * 0.6
            feedback_parts.append(f"~ Report partially complete ({report_fields_present}/6 fields)")
        else:
            score += w_report * 0.2
            feedback_parts.append(f"✗ Report incomplete ({report_fields_present}/6 fields)")
    elif report_exists:
        score += w_report * 0.3
        feedback_parts.append("~ Report exists but may not be from this task")
    else:
        feedback_parts.append("✗ No report file created")
    
    # ============================================================
    # CRITERION 7: Screenshots Present (5 points)
    # ============================================================
    screenshots_created = result.get('screenshots_created', False)
    screenshots_count = result.get('screenshots_count', 0)
    
    if screenshots_created and screenshots_count >= 2:
        score += w_screenshots
        feedback_parts.append(f"✓ Screenshots created ({screenshots_count})")
    elif screenshots_created or screenshots_count >= 1:
        score += w_screenshots * 0.5
        feedback_parts.append(f"~ Some screenshots ({screenshots_count})")
    else:
        feedback_parts.append("✗ No screenshots created")
    
    # ============================================================
    # ANTI-GAMING CHECK: Verify work was actually done
    # ============================================================
    measurements_exist = result.get('measurements_exists', False)
    measurements_created_during_task = result.get('measurements_created_during_task', False)
    
    # Agent should have placed measurements during the task
    work_evidence = (
        measurements_exist or 
        report_created_during_task or 
        (agent_midline is not None and agent_midline > 0)
    )
    
    if not work_evidence:
        # Penalize if no evidence of actual work
        score = max(0, score - 20)
        feedback_parts.append("⚠ No evidence of measurements placed during task")
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Must have attempted midline measurement and score >= 60
    midline_attempted = agent_midline is not None
    passed = score >= 60 and midline_attempted
    
    # Convert all numpy types for JSON serialization
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details,
        "subscores": {
            "midline_shift": midline_accurate,
            "ventricular_ratio": agent_vent_ratio is not None,
            "herniation_assessment": herniation_score,
            "sulcal_effacement": agent_sulcal is not None,
            "overall_grade": normalize_string(agent_grade) == normalize_string(gt_grade),
            "report_complete": report_fields_present >= 5,
            "screenshots": screenshots_count >= 2
        }
    }