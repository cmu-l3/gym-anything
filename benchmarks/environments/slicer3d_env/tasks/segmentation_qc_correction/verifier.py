#!/usr/bin/env python3
"""
Verifier for Segmentation QC and Correction task.

VERIFICATION STRATEGY:
1. Dice Improvement - Did the corrected segmentation improve over the broken one?
2. Final Dice Score - Is the corrected segmentation high quality?
3. Under-segmentation Fix - Were missing tumor regions added?
4. Over-segmentation Fix - Were false positive regions removed?
5. Boundary Improvement - Was boundary quality improved?
6. QC Report - Did the agent document errors found?

Anti-gaming checks:
- Timestamp verification (segmentation modified after task start)
- Change detection (segmentation differs from broken input)
- Bidirectional improvement (both FP and FN must improve for full credit)
"""

import json
import os
import sys
import tempfile
import logging

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


def verify_segmentation_qc(traj, env_info, task_info):
    """
    Verify the segmentation QC task completion.
    
    Scoring (100 points total):
    - Dice improvement >= 0.05: 25 points
    - Final Dice >= 0.90: 20 points
    - Under-segmentation fixed (>= 70%): 15 points
    - Over-segmentation fixed (>= 70%): 15 points
    - Boundary improved: 10 points
    - QC report complete: 10 points
    - Error types identified: 5 points
    
    Returns:
        dict with 'passed' (bool), 'score' (float 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available - framework error"}
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    dice_improvement_min = thresholds.get('dice_improvement_min', 0.05)
    final_dice_min = thresholds.get('final_dice_min', 0.90)
    error_fix_threshold = thresholds.get('error_fix_threshold', 0.70)
    
    w_dice_improvement = weights.get('dice_improvement', 25)
    w_final_dice = weights.get('final_dice_high', 20)
    w_under_seg = weights.get('under_seg_fixed', 15)
    w_over_seg = weights.get('over_seg_fixed', 15)
    w_boundary = weights.get('boundary_improved', 10)
    w_report = weights.get('qc_report_complete', 10)
    w_error_types = weights.get('error_types_identified', 5)
    
    score = 0.0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Load task result JSON
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/qc_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    # ================================================================
    # Anti-gaming: Timestamp verification
    # ================================================================
    task_start = result.get('task_start_time', 0)
    corrected_mtime = result.get('corrected_segmentation_mtime', 0)
    
    if corrected_mtime > 0 and corrected_mtime < task_start:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Anti-gaming: Corrected segmentation was created before task started"
        }
    
    # ================================================================
    # Load QC metrics
    # ================================================================
    temp_metrics = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    metrics = {}
    try:
        copy_from_env("/tmp/qc_metrics.json", temp_metrics.name)
        with open(temp_metrics.name, 'r') as f:
            metrics = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read metrics: {e}")
        feedback_parts.append("Warning: Could not load detailed metrics")
    finally:
        if os.path.exists(temp_metrics.name):
            os.unlink(temp_metrics.name)
    
    details['metrics'] = to_python_type(metrics)
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # Check if corrected segmentation exists
    if not result.get('corrected_segmentation_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No corrected segmentation found - task incomplete",
            "details": details
        }
    
    # ================================================================
    # Anti-gaming: Check if segmentation was actually modified
    # ================================================================
    voxels_changed = metrics.get('voxels_changed', 0)
    segmentation_modified = metrics.get('segmentation_modified', False)
    
    if not segmentation_modified and voxels_changed < 100:
        feedback_parts.append(f"WARNING: Only {voxels_changed} voxels changed - minimal modification")
        details['anti_gaming_warning'] = 'minimal_modification'
    
    # ================================================================
    # CRITERION 1: Dice Improvement (25 points)
    # ================================================================
    initial_dice = metrics.get('initial_dice', metrics.get('broken_dice', 0))
    corrected_dice = metrics.get('corrected_dice', 0)
    dice_improvement = metrics.get('dice_improvement', corrected_dice - initial_dice)
    
    details['initial_dice'] = initial_dice
    details['corrected_dice'] = corrected_dice
    details['dice_improvement'] = dice_improvement
    
    if dice_improvement >= dice_improvement_min:
        score += w_dice_improvement
        feedback_parts.append(f"✓ Dice improved by {dice_improvement:.3f} (>= {dice_improvement_min})")
    elif dice_improvement > 0:
        partial = w_dice_improvement * (dice_improvement / dice_improvement_min)
        score += partial
        feedback_parts.append(f"~ Dice improved by {dice_improvement:.3f} (partial: {partial:.1f}/{w_dice_improvement})")
    else:
        feedback_parts.append(f"✗ Dice did not improve (change: {dice_improvement:.3f})")
    
    # ================================================================
    # CRITERION 2: Final Dice >= 0.90 (20 points)
    # ================================================================
    if corrected_dice >= final_dice_min:
        score += w_final_dice
        feedback_parts.append(f"✓ Final Dice: {corrected_dice:.3f} (>= {final_dice_min})")
    elif corrected_dice >= 0.85:
        partial = w_final_dice * ((corrected_dice - 0.85) / (final_dice_min - 0.85))
        score += partial
        feedback_parts.append(f"~ Final Dice: {corrected_dice:.3f} (partial: {partial:.1f}/{w_final_dice})")
    else:
        feedback_parts.append(f"✗ Final Dice: {corrected_dice:.3f} (< 0.85)")
    
    # ================================================================
    # CRITERION 3: Under-segmentation Fixed (15 points)
    # ================================================================
    initial_fn = metrics.get('initial_false_negatives', metrics.get('broken_false_negatives', 0))
    corrected_fn = metrics.get('corrected_false_negatives', 0)
    
    details['initial_false_negatives'] = initial_fn
    details['corrected_false_negatives'] = corrected_fn
    
    fn_fixed = False
    if initial_fn > 0:
        fn_reduction = (initial_fn - corrected_fn) / initial_fn
        details['fn_reduction_ratio'] = fn_reduction
        
        if fn_reduction >= error_fix_threshold:
            score += w_under_seg
            feedback_parts.append(f"✓ Under-segmentation fixed: {fn_reduction*100:.0f}% of missing voxels recovered")
            fn_fixed = True
        elif fn_reduction > 0:
            partial = w_under_seg * (fn_reduction / error_fix_threshold)
            score += partial
            feedback_parts.append(f"~ Under-segmentation partially fixed: {fn_reduction*100:.0f}% ({partial:.1f}/{w_under_seg})")
            fn_fixed = fn_reduction > 0.3
        else:
            feedback_parts.append("✗ Under-segmentation not addressed")
    else:
        feedback_parts.append("- No under-segmentation in original (N/A)")
        fn_fixed = True
    
    # ================================================================
    # CRITERION 4: Over-segmentation Fixed (15 points)
    # ================================================================
    initial_fp = metrics.get('initial_false_positives', metrics.get('broken_false_positives', 0))
    corrected_fp = metrics.get('corrected_false_positives', 0)
    
    details['initial_false_positives'] = initial_fp
    details['corrected_false_positives'] = corrected_fp
    
    fp_fixed = False
    if initial_fp > 0:
        fp_reduction = (initial_fp - corrected_fp) / initial_fp
        details['fp_reduction_ratio'] = fp_reduction
        
        if fp_reduction >= error_fix_threshold:
            score += w_over_seg
            feedback_parts.append(f"✓ Over-segmentation fixed: {fp_reduction*100:.0f}% of false positives removed")
            fp_fixed = True
        elif fp_reduction > 0:
            partial = w_over_seg * (fp_reduction / error_fix_threshold)
            score += partial
            feedback_parts.append(f"~ Over-segmentation partially fixed: {fp_reduction*100:.0f}% ({partial:.1f}/{w_over_seg})")
            fp_fixed = fp_reduction > 0.3
        else:
            feedback_parts.append("✗ Over-segmentation not addressed")
    else:
        feedback_parts.append("- No over-segmentation in original (N/A)")
        fp_fixed = True
    
    # ================================================================
    # CRITERION 5: Boundary Improvement (10 points)
    # ================================================================
    # Approximated by overall quality improvement
    if corrected_dice >= 0.92 and dice_improvement >= 0.08:
        score += w_boundary
        feedback_parts.append("✓ Boundary quality improved significantly")
    elif corrected_dice >= 0.88 and dice_improvement >= 0.03:
        score += w_boundary * 0.5
        feedback_parts.append("~ Boundary quality partially improved")
    else:
        feedback_parts.append("- Boundary improvement unclear")
    
    # ================================================================
    # CRITERION 6: QC Report Complete (10 points)
    # ================================================================
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    qc_report = {}
    report_valid = False
    
    try:
        copy_from_env("/tmp/qc_report.json", temp_report.name)
        with open(temp_report.name, 'r') as f:
            qc_report = json.load(f)
        report_valid = True
    except Exception as e:
        logger.warning(f"Failed to read QC report: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
    
    if result.get('qc_report_exists', False) and report_valid:
        # Check required fields
        has_error_count = 'error_count' in qc_report or 'num_errors' in qc_report
        has_error_types = 'error_types' in qc_report or 'errors' in qc_report
        has_corrections = 'corrections_made' in qc_report or 'corrections' in qc_report
        
        if has_error_count and has_error_types and has_corrections:
            score += w_report
            feedback_parts.append("✓ QC report complete with required fields")
        elif has_error_count or has_error_types:
            score += w_report * 0.5
            feedback_parts.append("~ QC report exists but missing some fields")
        else:
            feedback_parts.append("~ QC report exists but lacks required structure")
    elif result.get('qc_report_exists', False):
        feedback_parts.append("✗ QC report exists but is invalid JSON")
    else:
        feedback_parts.append("✗ QC report not created")
    
    # ================================================================
    # CRITERION 7: Error Types Identified (5 points)
    # ================================================================
    error_types = qc_report.get('error_types', qc_report.get('errors', []))
    error_types_str = str(error_types).lower()
    
    identified_under = 'under' in error_types_str or 'missing' in error_types_str
    identified_over = 'over' in error_types_str or 'false positive' in error_types_str or 'extra' in error_types_str
    
    details['identified_under_seg'] = identified_under
    details['identified_over_seg'] = identified_over
    
    if identified_under and identified_over:
        score += w_error_types
        feedback_parts.append("✓ Both error types correctly identified in report")
    elif identified_under or identified_over:
        score += w_error_types * 0.5
        feedback_parts.append("~ Only one error type identified in report")
    else:
        feedback_parts.append("- Error types not clearly identified in report")
    
    # ================================================================
    # Final Assessment
    # ================================================================
    # Pass criteria: >= 60 points AND (dice improved AND at least one error type fixed)
    key_criteria_met = dice_improvement > 0 and (fn_fixed or fp_fixed)
    passed = score >= 60 and key_criteria_met
    
    # Build feedback string
    feedback = f"Score: {score:.1f}/100\n"
    feedback += f"Initial Dice: {initial_dice:.3f} → Final Dice: {corrected_dice:.3f}\n"
    feedback += f"Dice Improvement: {dice_improvement:+.3f}\n"
    feedback += "\n".join(feedback_parts)
    
    if passed:
        feedback += "\n\n✓ TASK PASSED"
    else:
        feedback += "\n\n✗ TASK FAILED"
        if dice_improvement <= 0:
            feedback += " - Segmentation quality did not improve"
        elif not (fn_fixed or fp_fixed):
            feedback += " - Neither under-segmentation nor over-segmentation was adequately fixed"
        elif score < 60:
            feedback += f" - Score {score:.1f} below 60 threshold"
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": feedback,
        "details": to_python_type(details)
    }


if __name__ == "__main__":
    # Test run
    result = verify_segmentation_qc({}, {'copy_from_env': None}, {})
    print(result['feedback'])
    sys.exit(0 if result['passed'] else 1)