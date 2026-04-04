#!/usr/bin/env python3
"""
Verifier for Vertebral Compression Fracture Assessment task.

VERIFICATION CRITERIA:
1. Correct vertebral level identification (25 points)
2. Anterior height measurement accuracy (20 points) - within 3mm
3. Posterior height measurement accuracy (15 points) - within 3mm
4. Compression ratio accuracy (15 points) - within 0.05
5. Correct Genant fracture grade (15 points)
6. Report completeness (10 points)

ANTI-GAMING:
- Files must be created AFTER task start time
- Measurements must be anatomically plausible (5-40mm)
- Ratio must be consistent with reported heights

Pass threshold: 60 points with correct vertebral level
"""

import json
import os
import sys
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_vertebral_fracture_assessment(traj, env_info, task_info):
    """
    Verify vertebral fracture assessment task completion.
    
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
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
    height_range = metadata.get('vertebral_height_range_mm', {'min': 5, 'max': 40})
    
    ha_error_max = thresholds.get('anterior_height_error_max_mm', 3.0)
    hp_error_max = thresholds.get('posterior_height_error_max_mm', 3.0)
    ratio_error_max = thresholds.get('ratio_error_max', 0.05)
    
    w_level = weights.get('correct_level_id', 25)
    w_ha = weights.get('anterior_height_accuracy', 20)
    w_hp = weights.get('posterior_height_accuracy', 15)
    w_ratio = weights.get('compression_ratio_accuracy', 15)
    w_grade = weights.get('genant_grade_correct', 15)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/vertebral_task_result.json", temp_result.name)
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
    
    # ============================================================
    # ANTI-GAMING CHECK: Timestamp verification
    # ============================================================
    measurement_after_start = result.get('measurement_after_start', False)
    report_after_start = result.get('report_after_start', False)
    
    if not measurement_after_start and not report_after_start:
        # Neither file was created during the task
        if result.get('measurement_exists', False) or result.get('report_exists', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "ANTI-GAMING: Files existed before task started - no work detected",
                "details": {"anti_gaming": "failed_timestamp"}
            }
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("WARNING: Slicer was not running at export time")
    
    # ============================================================
    # Extract values
    # ============================================================
    agent_level = str(result.get('agent_level', '')).strip().upper()
    gt_level = str(result.get('gt_level', '')).strip().upper()
    
    try:
        agent_ha = float(result.get('agent_anterior_height', 0) or 0)
    except (ValueError, TypeError):
        agent_ha = 0.0
    
    try:
        agent_hp = float(result.get('agent_posterior_height', 0) or 0)
    except (ValueError, TypeError):
        agent_hp = 0.0
    
    try:
        agent_ratio = float(result.get('agent_ratio', 0) or 0)
    except (ValueError, TypeError):
        agent_ratio = 0.0
    
    try:
        agent_grade = int(result.get('agent_grade', -1) or -1)
    except (ValueError, TypeError):
        agent_grade = -1
    
    try:
        gt_ha = float(result.get('gt_anterior_height', 0) or 0)
    except (ValueError, TypeError):
        gt_ha = 0.0
    
    try:
        gt_hp = float(result.get('gt_posterior_height', 0) or 0)
    except (ValueError, TypeError):
        gt_hp = 0.0
    
    try:
        gt_ratio = float(result.get('gt_ratio', 0) or 0)
    except (ValueError, TypeError):
        gt_ratio = 0.0
    
    try:
        gt_grade = int(result.get('gt_grade', -1) or -1)
    except (ValueError, TypeError):
        gt_grade = -1
    
    details['agent'] = {
        'level': agent_level,
        'anterior_height': agent_ha,
        'posterior_height': agent_hp,
        'ratio': agent_ratio,
        'grade': agent_grade
    }
    details['ground_truth'] = {
        'level': gt_level,
        'anterior_height': gt_ha,
        'posterior_height': gt_hp,
        'ratio': gt_ratio,
        'grade': gt_grade
    }
    
    # ============================================================
    # CRITERION 1: Correct Level Identification (25 points)
    # ============================================================
    level_correct = False
    if agent_level and gt_level:
        # Normalize level names (L1, l1, L-1 all equivalent)
        agent_level_norm = agent_level.replace("-", "").replace(" ", "").replace("_", "")
        gt_level_norm = gt_level.replace("-", "").replace(" ", "").replace("_", "")
        level_correct = (agent_level_norm == gt_level_norm)
    
    if level_correct:
        score += w_level
        feedback_parts.append(f"✓ Correct vertebral level identified: {agent_level} ({w_level}/{w_level})")
    elif agent_level:
        feedback_parts.append(f"✗ Incorrect vertebral level: reported '{agent_level}', expected '{gt_level}' (0/{w_level})")
    else:
        feedback_parts.append(f"✗ No vertebral level reported (0/{w_level})")
    
    details['level_correct'] = level_correct
    
    # ============================================================
    # CRITERION 2: Anterior Height Accuracy (20 points)
    # ============================================================
    min_height = height_range.get('min', 5)
    max_height = height_range.get('max', 40)
    
    ha_plausible = min_height <= agent_ha <= max_height
    ha_correct = False
    ha_error = abs(agent_ha - gt_ha) if gt_ha > 0 else float('inf')
    
    if not ha_plausible and agent_ha > 0:
        feedback_parts.append(f"✗ Anterior height {agent_ha:.1f}mm is anatomically implausible (expected {min_height}-{max_height}mm) (0/{w_ha})")
    elif ha_error <= ha_error_max:
        score += w_ha
        ha_correct = True
        feedback_parts.append(f"✓ Anterior height accurate: {agent_ha:.1f}mm vs {gt_ha:.1f}mm (error: {ha_error:.1f}mm ≤ {ha_error_max}mm) ({w_ha}/{w_ha})")
    elif agent_ha > 0:
        feedback_parts.append(f"✗ Anterior height inaccurate: {agent_ha:.1f}mm vs {gt_ha:.1f}mm (error: {ha_error:.1f}mm > {ha_error_max}mm) (0/{w_ha})")
    else:
        feedback_parts.append(f"✗ No anterior height measurement (0/{w_ha})")
    
    details['anterior_height_correct'] = ha_correct
    details['anterior_height_error'] = ha_error
    
    # ============================================================
    # CRITERION 3: Posterior Height Accuracy (15 points)
    # ============================================================
    hp_plausible = min_height <= agent_hp <= max_height
    hp_correct = False
    hp_error = abs(agent_hp - gt_hp) if gt_hp > 0 else float('inf')
    
    if not hp_plausible and agent_hp > 0:
        feedback_parts.append(f"✗ Posterior height {agent_hp:.1f}mm is anatomically implausible (0/{w_hp})")
    elif hp_error <= hp_error_max:
        score += w_hp
        hp_correct = True
        feedback_parts.append(f"✓ Posterior height accurate: {agent_hp:.1f}mm vs {gt_hp:.1f}mm (error: {hp_error:.1f}mm ≤ {hp_error_max}mm) ({w_hp}/{w_hp})")
    elif agent_hp > 0:
        feedback_parts.append(f"✗ Posterior height inaccurate: {agent_hp:.1f}mm vs {gt_hp:.1f}mm (error: {hp_error:.1f}mm > {hp_error_max}mm) (0/{w_hp})")
    else:
        feedback_parts.append(f"✗ No posterior height measurement (0/{w_hp})")
    
    details['posterior_height_correct'] = hp_correct
    details['posterior_height_error'] = hp_error
    
    # ============================================================
    # CRITERION 4: Compression Ratio Accuracy (15 points)
    # ============================================================
    ratio_correct = False
    ratio_error = abs(agent_ratio - gt_ratio) if gt_ratio > 0 else float('inf')
    
    # Check ratio consistency with reported heights
    if agent_hp > 0:
        calculated_ratio = agent_ha / agent_hp
        ratio_consistency = abs(agent_ratio - calculated_ratio)
        if ratio_consistency > 0.03 and agent_ratio > 0:
            feedback_parts.append(f"  ⚠ Warning: Reported ratio {agent_ratio:.2f} inconsistent with Ha/Hp = {calculated_ratio:.2f}")
            details['ratio_consistency_warning'] = True
    
    if ratio_error <= ratio_error_max:
        score += w_ratio
        ratio_correct = True
        feedback_parts.append(f"✓ Compression ratio accurate: {agent_ratio:.2f} vs {gt_ratio:.2f} (error: {ratio_error:.2f} ≤ {ratio_error_max}) ({w_ratio}/{w_ratio})")
    elif agent_ratio > 0:
        feedback_parts.append(f"✗ Compression ratio inaccurate: {agent_ratio:.2f} vs {gt_ratio:.2f} (error: {ratio_error:.2f} > {ratio_error_max}) (0/{w_ratio})")
    else:
        feedback_parts.append(f"✗ No compression ratio reported (0/{w_ratio})")
    
    details['ratio_correct'] = ratio_correct
    details['ratio_error'] = ratio_error
    
    # ============================================================
    # CRITERION 5: Genant Grade Correct (15 points)
    # ============================================================
    grade_correct = False
    
    if agent_grade == gt_grade and agent_grade >= 0:
        score += w_grade
        grade_correct = True
        grade_names = {0: "Normal", 1: "Mild", 2: "Moderate", 3: "Severe"}
        grade_name = grade_names.get(agent_grade, "Unknown")
        feedback_parts.append(f"✓ Genant grade correct: Grade {agent_grade} ({grade_name}) ({w_grade}/{w_grade})")
    elif agent_grade >= 0:
        grade_names = {0: "Normal", 1: "Mild", 2: "Moderate", 3: "Severe"}
        agent_name = grade_names.get(agent_grade, "Unknown")
        gt_name = grade_names.get(gt_grade, "Unknown")
        feedback_parts.append(f"✗ Genant grade incorrect: Grade {agent_grade} ({agent_name}) vs Grade {gt_grade} ({gt_name}) (0/{w_grade})")
    else:
        feedback_parts.append(f"✗ No Genant grade reported (0/{w_grade})")
    
    details['grade_correct'] = grade_correct
    
    # ============================================================
    # CRITERION 6: Report Completeness (10 points)
    # ============================================================
    report_valid = result.get('report_valid', False)
    measurement_exists = result.get('measurement_exists', False)
    
    if report_valid and measurement_exists:
        score += w_report
        feedback_parts.append(f"✓ Report and measurements complete ({w_report}/{w_report})")
        details['report_complete'] = True
    elif report_valid:
        partial_score = w_report // 2
        score += partial_score
        feedback_parts.append(f"△ Report complete but no measurement markups ({partial_score}/{w_report})")
        details['report_complete'] = 'partial'
    elif measurement_exists:
        partial_score = w_report // 2
        score += partial_score
        feedback_parts.append(f"△ Measurements exist but no report JSON ({partial_score}/{w_report})")
        details['report_complete'] = 'partial'
    else:
        feedback_parts.append(f"✗ No report or measurements found (0/{w_report})")
        details['report_complete'] = False
    
    # ============================================================
    # SUMMARY
    # ============================================================
    # Pass requires: score >= 60 AND correct level identification
    passed = score >= 60 and level_correct
    
    feedback_parts.append("")
    feedback_parts.append(f"{'='*50}")
    feedback_parts.append(f"Total Score: {score}/100")
    
    if passed:
        feedback_parts.append("✓ PASSED: Task completed successfully")
    elif not level_correct:
        feedback_parts.append("✗ FAILED: Correct vertebral level identification is required to pass")
    else:
        feedback_parts.append("✗ FAILED: Score below 60 threshold")
    
    details['total_score'] = score
    details['passed'] = passed
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # Test mode
    print("Vertebral Fracture Assessment Verifier")
    print("This verifier requires copy_from_env function from the framework.")