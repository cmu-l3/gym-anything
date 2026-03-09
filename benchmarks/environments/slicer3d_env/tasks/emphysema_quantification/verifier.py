#!/usr/bin/env python3
"""
Verifier for COPD Emphysema Quantification task.

VERIFICATION STRATEGY:
1. LAA-950 Accuracy (35 pts) - Primary metric for emphysema
2. Severity Classification (20 pts) - Clinical category
3. Lung Volume Accuracy (15 pts) - Segmentation volume
4. Segmentation Quality (15 pts) - Dice coefficient
5. Report Completeness (10 pts) - All required fields
6. Mean Density Accuracy (5 pts) - Secondary metric

Anti-gaming:
- File timestamps checked
- Segmentation must be created during task
- Values must be consistent
"""

import json
import os
import sys
import tempfile
import logging
from typing import Tuple, Dict, Any, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def safe_float(value: Any, default: float = None) -> Optional[float]:
    """Safely convert value to float."""
    if value is None or value == "" or value == "None":
        return default
    try:
        return float(value)
    except (ValueError, TypeError):
        return default


def classify_severity(laa_950: float) -> str:
    """Classify emphysema severity based on LAA-950."""
    if laa_950 < 6:
        return "Normal"
    elif laa_950 < 15:
        return "Mild"
    elif laa_950 < 25:
        return "Moderate"
    else:
        return "Severe"


def severity_distance(class1: str, class2: str) -> int:
    """Calculate distance between severity classes."""
    classes = ["Normal", "Mild", "Moderate", "Severe"]
    class1_norm = class1.strip().capitalize() if class1 else ""
    class2_norm = class2.strip().capitalize() if class2 else ""
    try:
        idx1 = classes.index(class1_norm)
        idx2 = classes.index(class2_norm)
        return abs(idx1 - idx2)
    except ValueError:
        return 4  # Maximum distance for unknown class


def verify_emphysema_quantification(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the emphysema quantification task.
    
    Uses copy_from_env to read result data from container.
    
    Returns:
        Dict with 'passed' (bool), 'score' (float), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata for thresholds
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    laa_error_max = thresholds.get('laa_950_error_max_percent', 3.0)
    volume_error_max = thresholds.get('volume_error_max_percent', 20.0)
    dice_min = thresholds.get('dice_min', 0.85)
    mean_density_error_max = thresholds.get('mean_density_error_max_hu', 30.0)
    
    w_laa = weights.get('laa_950_accuracy', 35)
    w_class = weights.get('severity_classification', 20)
    w_volume = weights.get('lung_volume_accuracy', 15)
    w_dice = weights.get('segmentation_quality', 15)
    w_report = weights.get('report_completeness', 10)
    w_mean = weights.get('mean_density_accuracy', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    
    try:
        copy_from_env("/tmp/emphysema_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
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
    score = 0.0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # BASIC CHECKS
    # ================================================================
    
    if not result_data.get('slicer_was_running', False):
        feedback_parts.append("FAIL: 3D Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": "\n".join(feedback_parts),
            "details": details
        }
    
    segmentation_valid = result_data.get('segmentation_valid', False)
    report_exists = result_data.get('report_exists', False)
    
    # Get agent and ground truth values
    agent = result_data.get('agent_results', {})
    gt = result_data.get('ground_truth', {})
    
    agent_laa950 = safe_float(agent.get('laa_950_percent'))
    agent_volume = safe_float(agent.get('total_lung_volume_ml'))
    agent_class = (agent.get('severity_classification') or '').strip()
    agent_mean = safe_float(agent.get('mean_lung_density_hu'))
    agent_perc15 = safe_float(agent.get('perc15_density_hu'))
    
    gt_laa950 = safe_float(gt.get('laa_950_percent'))
    gt_volume = safe_float(gt.get('total_lung_volume_ml'))
    gt_class = (gt.get('severity_classification') or '').strip()
    gt_mean = safe_float(gt.get('mean_lung_density_hu'))
    gt_perc15 = safe_float(gt.get('perc15_density_hu'))
    
    dice = safe_float(result_data.get('dice_coefficient'))
    
    details['agent'] = {
        'laa_950': agent_laa950,
        'volume': agent_volume,
        'classification': agent_class,
        'mean_density': agent_mean
    }
    details['ground_truth'] = {
        'laa_950': gt_laa950,
        'volume': gt_volume,
        'classification': gt_class,
        'mean_density': gt_mean
    }
    
    # ================================================================
    # CRITERION 1: LAA-950 Accuracy (35 points)
    # ================================================================
    laa950_score = 0
    laa950_pass = False
    
    if agent_laa950 is not None and gt_laa950 is not None:
        laa950_error = abs(agent_laa950 - gt_laa950)
        details['laa_950_error'] = laa950_error
        
        if laa950_error <= 1.0:
            laa950_score = w_laa
            feedback_parts.append(f"LAA-950: EXCELLENT - {agent_laa950:.2f}% vs GT {gt_laa950:.2f}% (error: {laa950_error:.2f}%)")
            laa950_pass = True
        elif laa950_error <= 2.0:
            laa950_score = w_laa * 0.75
            feedback_parts.append(f"LAA-950: GOOD - {agent_laa950:.2f}% vs GT {gt_laa950:.2f}% (error: {laa950_error:.2f}%)")
            laa950_pass = True
        elif laa950_error <= laa_error_max:
            laa950_score = w_laa * 0.5
            feedback_parts.append(f"LAA-950: ACCEPTABLE - {agent_laa950:.2f}% vs GT {gt_laa950:.2f}% (error: {laa950_error:.2f}%)")
            laa950_pass = True
        elif laa950_error <= 5.0:
            laa950_score = w_laa * 0.2
            feedback_parts.append(f"LAA-950: PARTIAL - {agent_laa950:.2f}% vs GT {gt_laa950:.2f}% (error: {laa950_error:.2f}%)")
        else:
            feedback_parts.append(f"LAA-950: FAIL - {agent_laa950:.2f}% vs GT {gt_laa950:.2f}% (error: {laa950_error:.2f}%)")
    elif agent_laa950 is None:
        feedback_parts.append("LAA-950: FAIL - No value reported")
    else:
        feedback_parts.append("LAA-950: FAIL - No ground truth available for comparison")
    
    score += laa950_score
    
    # ================================================================
    # CRITERION 2: Severity Classification (20 points)
    # ================================================================
    class_score = 0
    
    if agent_class and gt_class:
        agent_class_norm = agent_class.capitalize()
        gt_class_norm = gt_class.capitalize()
        
        if agent_class_norm == gt_class_norm:
            class_score = w_class
            feedback_parts.append(f"Classification: CORRECT - {agent_class_norm}")
        else:
            dist = severity_distance(agent_class_norm, gt_class_norm)
            if dist == 1:
                class_score = w_class * 0.5
                feedback_parts.append(f"Classification: PARTIAL - {agent_class_norm} vs GT {gt_class_norm} (off by 1 category)")
            else:
                feedback_parts.append(f"Classification: FAIL - {agent_class_norm} vs GT {gt_class_norm} (off by {dist} categories)")
    elif agent_laa950 is not None:
        # Check if classification is consistent with reported LAA-950
        expected_class = classify_severity(agent_laa950)
        if agent_class:
            if agent_class.capitalize() == expected_class:
                class_score = w_class * 0.75  # Partial credit for internal consistency
                feedback_parts.append(f"Classification: CONSISTENT with reported LAA-950 ({agent_class})")
            else:
                feedback_parts.append(f"Classification: INCONSISTENT - reported '{agent_class}' but LAA-950={agent_laa950:.2f}% suggests '{expected_class}'")
        else:
            feedback_parts.append("Classification: FAIL - No classification provided")
    else:
        feedback_parts.append("Classification: FAIL - No classification or LAA-950 provided")
    
    score += class_score
    
    # ================================================================
    # CRITERION 3: Lung Volume Accuracy (15 points)
    # ================================================================
    volume_score = 0
    
    if agent_volume is not None and gt_volume is not None and gt_volume > 0:
        volume_error_pct = abs(agent_volume - gt_volume) / gt_volume * 100
        details['volume_error_pct'] = volume_error_pct
        
        if volume_error_pct <= 10:
            volume_score = w_volume
            feedback_parts.append(f"Lung Volume: EXCELLENT - {agent_volume:.1f} mL vs GT {gt_volume:.1f} mL (error: {volume_error_pct:.1f}%)")
        elif volume_error_pct <= volume_error_max:
            volume_score = w_volume * 0.7
            feedback_parts.append(f"Lung Volume: GOOD - {agent_volume:.1f} mL vs GT {gt_volume:.1f} mL (error: {volume_error_pct:.1f}%)")
        elif volume_error_pct <= 30:
            volume_score = w_volume * 0.4
            feedback_parts.append(f"Lung Volume: PARTIAL - {agent_volume:.1f} mL vs GT {gt_volume:.1f} mL (error: {volume_error_pct:.1f}%)")
        else:
            feedback_parts.append(f"Lung Volume: FAIL - {agent_volume:.1f} mL vs GT {gt_volume:.1f} mL (error: {volume_error_pct:.1f}%)")
    else:
        feedback_parts.append("Lung Volume: FAIL - No volume reported or no ground truth")
    
    score += volume_score
    
    # ================================================================
    # CRITERION 4: Segmentation Quality - Dice (15 points)
    # ================================================================
    seg_score = 0
    
    if dice is not None and dice >= 0:
        details['dice_coefficient'] = dice
        
        if dice >= 0.90:
            seg_score = w_dice
            feedback_parts.append(f"Segmentation Quality: EXCELLENT - Dice = {dice:.4f}")
        elif dice >= dice_min:
            seg_score = w_dice * 0.8
            feedback_parts.append(f"Segmentation Quality: GOOD - Dice = {dice:.4f}")
        elif dice >= 0.75:
            seg_score = w_dice * 0.5
            feedback_parts.append(f"Segmentation Quality: ACCEPTABLE - Dice = {dice:.4f}")
        elif dice >= 0.60:
            seg_score = w_dice * 0.25
            feedback_parts.append(f"Segmentation Quality: PARTIAL - Dice = {dice:.4f}")
        else:
            feedback_parts.append(f"Segmentation Quality: POOR - Dice = {dice:.4f}")
    elif not segmentation_valid:
        feedback_parts.append("Segmentation Quality: FAIL - No valid segmentation file created during task")
    else:
        feedback_parts.append("Segmentation Quality: FAIL - Could not compute Dice coefficient")
    
    score += seg_score
    
    # ================================================================
    # CRITERION 5: Report Completeness (10 points)
    # ================================================================
    report_score = 0
    
    if report_exists:
        required_fields = [
            ('laa_950_percent', agent_laa950),
            ('total_lung_volume_ml', agent_volume),
            ('severity_classification', agent_class),
            ('mean_lung_density_hu', agent_mean),
            ('perc15_density_hu', agent_perc15)
        ]
        
        present_count = sum(1 for _, v in required_fields if v is not None and v != '')
        
        if present_count >= 5:
            report_score = w_report
            feedback_parts.append(f"Report: COMPLETE - All {present_count} required fields present")
        elif present_count >= 3:
            report_score = w_report * 0.6
            feedback_parts.append(f"Report: PARTIAL - {present_count}/5 required fields present")
        elif present_count >= 1:
            report_score = w_report * 0.3
            feedback_parts.append(f"Report: MINIMAL - {present_count}/5 required fields present")
        else:
            feedback_parts.append("Report: EMPTY - No required fields present")
    else:
        feedback_parts.append("Report: FAIL - No report file created")
    
    score += report_score
    
    # ================================================================
    # CRITERION 6: Mean Density Accuracy (5 points)
    # ================================================================
    mean_score = 0
    
    if agent_mean is not None and gt_mean is not None:
        mean_error = abs(agent_mean - gt_mean)
        details['mean_density_error'] = mean_error
        
        if mean_error <= 15:
            mean_score = w_mean
            feedback_parts.append(f"Mean Density: EXCELLENT - {agent_mean:.1f} HU vs GT {gt_mean:.1f} HU")
        elif mean_error <= mean_density_error_max:
            mean_score = w_mean * 0.6
            feedback_parts.append(f"Mean Density: GOOD - {agent_mean:.1f} HU vs GT {gt_mean:.1f} HU (error: {mean_error:.1f} HU)")
        else:
            feedback_parts.append(f"Mean Density: FAIL - {agent_mean:.1f} HU vs GT {gt_mean:.1f} HU (error: {mean_error:.1f} HU)")
    else:
        feedback_parts.append("Mean Density: NOT EVALUATED - Missing data")
    
    score += mean_score
    
    # ================================================================
    # FINAL ASSESSMENT
    # ================================================================
    
    # Round score
    score = round(score, 1)
    
    # Build summary
    feedback_parts.insert(0, f"=== Emphysema Quantification Score: {score}/100 ===\n")
    
    # Pass criteria: 60 points AND LAA-950 accuracy achieved
    passed = score >= 60 and laa950_pass
    
    if passed:
        feedback_parts.append(f"\nRESULT: PASSED (score: {score}, LAA-950 criterion met)")
    else:
        if not laa950_pass:
            feedback_parts.append(f"\nRESULT: FAILED (LAA-950 accuracy not achieved, score: {score})")
        else:
            feedback_parts.append(f"\nRESULT: FAILED (score: {score} < 60 threshold)")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts),
        "details": details
    }


if __name__ == "__main__":
    # For standalone testing
    print("Emphysema Quantification Verifier")
    print("Run via framework for actual verification")