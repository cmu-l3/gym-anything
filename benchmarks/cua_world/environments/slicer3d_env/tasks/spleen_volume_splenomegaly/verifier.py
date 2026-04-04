#!/usr/bin/env python3
"""
Verifier for Spleen Volume Measurement task.

VERIFICATION STRATEGY (Multi-Signal):
1. Dice Coefficient - segmentation overlap with ground truth (35 points)
2. Volume Accuracy - reported volume within 15% of ground truth (20 points)
3. Classification Correct - correct clinical category (15 points)
4. Segmentation Saved - valid NIfTI file exists with proper timestamp (10 points)
5. Report Complete - JSON with required fields (10 points)
6. Anatomical Location - segmentation centroid in correct quadrant (5 points)
7. No Over-segmentation - false positive rate < 10% (5 points)

Pass Threshold: 60 points with Dice >= 0.60 and Classification Correct
"""

import json
import os
import sys
import tempfile
import logging
from typing import Dict, Any, Tuple

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


def verify_spleen_volume(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify spleen volume measurement task completion.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (float), 'feedback' (str)
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
    
    dice_min = thresholds.get('dice_min', 0.60)
    volume_error_max = thresholds.get('volume_error_max_percent', 15) / 100.0
    
    w_dice = weights.get('dice_coefficient', 35)
    w_volume = weights.get('volume_accuracy', 20)
    w_classification = weights.get('classification_correct', 15)
    w_segmentation = weights.get('segmentation_saved', 10)
    w_report = weights.get('report_complete', 10)
    w_location = weights.get('anatomical_location', 5)
    w_overseg = weights.get('no_oversegmentation', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
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
    score = 0.0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # CHECK BASIC TASK COMPLETION
    # ================================================================
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # CRITERION 1: Dice Coefficient (35 points)
    # ================================================================
    dice_score = float(result.get('dice_score', 0))
    details['dice_score'] = dice_score
    
    if dice_score >= 0.70:
        score += w_dice
        feedback_parts.append(f"✓ Excellent segmentation overlap (Dice: {dice_score:.3f})")
    elif dice_score >= 0.60:
        score += w_dice * 0.85
        feedback_parts.append(f"✓ Good segmentation overlap (Dice: {dice_score:.3f})")
    elif dice_score >= 0.50:
        score += w_dice * 0.65
        feedback_parts.append(f"○ Moderate segmentation overlap (Dice: {dice_score:.3f})")
    elif dice_score >= 0.30:
        score += w_dice * 0.40
        feedback_parts.append(f"○ Fair segmentation overlap (Dice: {dice_score:.3f})")
    elif dice_score > 0:
        score += w_dice * 0.15
        feedback_parts.append(f"✗ Poor segmentation overlap (Dice: {dice_score:.3f})")
    else:
        feedback_parts.append("✗ No valid segmentation overlap computed")
    
    # ================================================================
    # CRITERION 2: Volume Accuracy (20 points)
    # ================================================================
    volume_accuracy = float(result.get('volume_accuracy', 0))
    agent_volume = float(result.get('agent_computed_volume_ml', 0))
    gt_volume = float(result.get('gt_volume_ml', 0))
    
    details['agent_volume_ml'] = agent_volume
    details['gt_volume_ml'] = gt_volume
    details['volume_accuracy'] = volume_accuracy
    
    if volume_accuracy >= 0.85:
        score += w_volume
        feedback_parts.append(f"✓ Volume accurate: {agent_volume:.1f} mL (GT: {gt_volume:.1f} mL)")
    elif volume_accuracy >= 0.70:
        score += w_volume * 0.75
        feedback_parts.append(f"○ Volume moderately accurate: {agent_volume:.1f} mL (GT: {gt_volume:.1f} mL)")
    elif volume_accuracy >= 0.50:
        score += w_volume * 0.40
        feedback_parts.append(f"○ Volume partially accurate: {agent_volume:.1f} mL (GT: {gt_volume:.1f} mL)")
    elif volume_accuracy > 0:
        score += w_volume * 0.15
        feedback_parts.append(f"✗ Volume inaccurate: {agent_volume:.1f} mL (GT: {gt_volume:.1f} mL)")
    else:
        feedback_parts.append("✗ Could not verify volume accuracy")
    
    # ================================================================
    # CRITERION 3: Classification Correct (15 points)
    # ================================================================
    classification_correct = result.get('classification_correct', False)
    agent_classification = result.get('agent_reported_classification', 'Not provided')
    expected_classification = result.get('expected_classification', 'Unknown')
    
    details['agent_classification'] = agent_classification
    details['expected_classification'] = expected_classification
    
    if classification_correct:
        score += w_classification
        feedback_parts.append(f"✓ Correct classification: {agent_classification}")
    elif agent_classification and agent_classification != 'Not provided':
        # Partial credit for attempting classification
        score += w_classification * 0.3
        feedback_parts.append(f"✗ Incorrect classification: '{agent_classification}' (expected: '{expected_classification}')")
    else:
        feedback_parts.append(f"✗ No classification provided (expected: '{expected_classification}')")
    
    # ================================================================
    # CRITERION 4: Segmentation File Saved (10 points)
    # ================================================================
    segmentation_exists = result.get('segmentation_exists', False)
    segmentation_created = result.get('segmentation_created_during_task', False)
    segmentation_size = result.get('segmentation_size_bytes', 0)
    
    details['segmentation_exists'] = segmentation_exists
    details['segmentation_created_during_task'] = segmentation_created
    
    if segmentation_exists and segmentation_created and segmentation_size > 1000:
        score += w_segmentation
        feedback_parts.append(f"✓ Valid segmentation file saved ({segmentation_size / 1024:.1f} KB)")
    elif segmentation_exists and segmentation_size > 1000:
        score += w_segmentation * 0.6
        feedback_parts.append("○ Segmentation exists but timestamp check failed")
    elif segmentation_exists:
        score += w_segmentation * 0.3
        feedback_parts.append(f"✗ Segmentation file too small ({segmentation_size} bytes)")
    else:
        feedback_parts.append("✗ No segmentation file found at expected path")
    
    # ================================================================
    # CRITERION 5: Report Complete (10 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    agent_reported_volume = result.get('agent_reported_volume_ml', '')
    
    details['report_exists'] = report_exists
    
    if report_exists and agent_reported_volume and float(agent_reported_volume or 0) > 0:
        score += w_report
        feedback_parts.append(f"✓ Complete report with volume ({agent_reported_volume} mL) and classification")
    elif report_exists:
        score += w_report * 0.5
        feedback_parts.append("○ Report exists but incomplete or missing volume")
    else:
        feedback_parts.append("✗ No report file found at expected path")
    
    # ================================================================
    # CRITERION 6: Anatomical Location (5 points)
    # ================================================================
    correct_location = result.get('correct_location', False)
    details['correct_location'] = correct_location
    
    if correct_location:
        score += w_location
        feedback_parts.append("✓ Segmentation in correct anatomical location (left upper quadrant)")
    else:
        feedback_parts.append("○ Segmentation location could not be verified or incorrect")
    
    # ================================================================
    # CRITERION 7: No Over-segmentation (5 points)
    # ================================================================
    fp_rate = float(result.get('false_positive_rate', 1.0))
    details['false_positive_rate'] = fp_rate
    
    if fp_rate < 0.10:
        score += w_overseg
        feedback_parts.append(f"✓ Minimal over-segmentation (FP: {fp_rate:.1%})")
    elif fp_rate < 0.20:
        score += w_overseg * 0.6
        feedback_parts.append(f"○ Some over-segmentation (FP: {fp_rate:.1%})")
    elif fp_rate < 0.35:
        score += w_overseg * 0.3
        feedback_parts.append(f"○ Moderate over-segmentation (FP: {fp_rate:.1%})")
    else:
        feedback_parts.append(f"✗ Significant over-segmentation (FP: {fp_rate:.1%})")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    
    # Key criteria for passing:
    # 1. Dice >= 0.60 (minimum segmentation quality)
    # 2. Classification correct
    # 3. Score >= 60
    
    key_criteria_met = (dice_score >= dice_min) and classification_correct
    passed = (score >= 60) and key_criteria_met
    
    # Build final feedback
    score = round(score, 1)
    
    feedback = f"Score: {score}/100\n\n"
    feedback += "\n".join(feedback_parts)
    
    if passed:
        feedback = f"PASSED - {feedback}"
    else:
        feedback = f"FAILED - {feedback}"
        
        # Explain why failed
        failure_reasons = []
        if dice_score < dice_min:
            failure_reasons.append(f"Dice coefficient ({dice_score:.3f}) below minimum threshold ({dice_min})")
        if not classification_correct:
            failure_reasons.append("Clinical classification incorrect or missing")
        if score < 60:
            failure_reasons.append(f"Total score ({score}) below passing threshold (60)")
        
        if failure_reasons:
            feedback += "\n\nFailure reasons:\n- " + "\n- ".join(failure_reasons)
    
    # Convert all values to Python native types
    details = to_python_type(details)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }