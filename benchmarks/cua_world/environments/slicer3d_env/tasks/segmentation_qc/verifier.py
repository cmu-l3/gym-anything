#!/usr/bin/env python3
"""
Verifier for segmentation quality control (QC) task.

VERIFICATION METRICS:
1. Dice improvement - corrected segmentation should be closer to ground truth
2. Final Dice quality - absolute quality of the corrected segmentation
3. Under-segmentation fixed - did agent add back missing regions
4. Over-segmentation fixed - did agent remove false positive regions
5. Preservation - did agent avoid breaking correct regions
6. Report completeness - did agent document findings

Ground Truth: BraTS 2021 expert segmentation
Input: Deliberately broken segmentation with known errors
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import optional dependencies
nib = None
NIBABEL_AVAILABLE = False

try:
    import nibabel as nib
    NIBABEL_AVAILABLE = True
except ImportError:
    logger.warning("nibabel not available - will try to install")


def ensure_dependencies():
    """Ensure required packages are available."""
    global NIBABEL_AVAILABLE, nib
    if not NIBABEL_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel"])
            import nibabel as nib_module
            nib = nib_module
            NIBABEL_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False
    return True


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


def dice_coefficient(pred, gt):
    """Calculate Dice coefficient between prediction and ground truth."""
    pred = pred.astype(bool)
    gt = gt.astype(bool)
    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)
    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0
    return float(2.0 * intersection / sum_volumes)


def verify_segmentation_qc(traj, env_info, task_info):
    """
    Verify segmentation QC task completion.

    Scoring (100 points total):
    - Dice improvement: 25 points (corrected > broken)
    - Final Dice quality: 20 points (>= 0.80)
    - Under-segmentation fixed: 15 points (>= 50% of missing regions added back)
    - Over-segmentation fixed: 15 points (>= 50% of false positives removed)
    - Preservation: 10 points (>= 95% of correct regions preserved)
    - Report completeness: 15 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }

    # Ensure dependencies
    if not ensure_dependencies():
        return {
            "passed": False,
            "score": 0,
            "feedback": "Required packages (nibabel) could not be installed"
        }

    import nibabel as nib

    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})

    dice_after_min = thresholds.get('dice_after_min', 0.80)
    preservation_min = thresholds.get('preservation_min', 0.95)
    over_seg_recall_min = thresholds.get('over_seg_recall_min', 0.50)

    w_improvement = weights.get('dice_improvement', 25)
    w_final_dice = weights.get('final_dice_quality', 20)
    w_under_seg = weights.get('under_seg_fixed', 15)
    w_over_seg = weights.get('over_seg_fixed', 15)
    w_preservation = weights.get('preservation', 10)
    w_report = weights.get('report_completeness', 15)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/qc_task_result.json", temp_result.name)
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

    # Check if agent saved corrected segmentation
    if not result.get('corrected_segmentation_exists', False):
        feedback_parts.append("No corrected segmentation file created")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }

    # ============================================================
    # LOAD ALL THREE SEGMENTATIONS
    # ============================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    temp_broken = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    temp_corrected = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    temp_errors = tempfile.NamedTemporaryFile(delete=False, suffix='.json')

    try:
        copy_from_env("/tmp/qc_ground_truth_seg.nii.gz", temp_gt.name)
        copy_from_env("/tmp/qc_broken_segmentation.nii.gz", temp_broken.name)
        copy_from_env("/tmp/qc_corrected_segmentation.nii.gz", temp_corrected.name)

        # Load error info
        error_info = {}
        try:
            copy_from_env("/tmp/qc_broken_errors.json", temp_errors.name)
            with open(temp_errors.name, 'r') as f:
                error_info = json.load(f)
        except Exception:
            logger.warning("Could not load error info")

        # Load NIfTI files
        gt_nii = nib.load(temp_gt.name)
        broken_nii = nib.load(temp_broken.name)
        corrected_nii = nib.load(temp_corrected.name)

        gt_data = gt_nii.get_fdata().astype(np.int32)
        broken_data = broken_nii.get_fdata().astype(np.int32)
        corrected_data = corrected_nii.get_fdata().astype(np.int32)

        details['gt_shape'] = list(gt_data.shape)
        details['broken_shape'] = list(broken_data.shape)
        details['corrected_shape'] = list(corrected_data.shape)

        # Check shape compatibility
        if gt_data.shape != corrected_data.shape:
            feedback_parts.append(f"Shape mismatch: GT {gt_data.shape} vs Corrected {corrected_data.shape}")
            if np.prod(gt_data.shape) != np.prod(corrected_data.shape):
                return {
                    "passed": False,
                    "score": 5,
                    "feedback": " | ".join(feedback_parts),
                    "details": to_python_type(details)
                }

        # Binarize all segmentations (tumor = any label > 0)
        gt_binary = (gt_data > 0).astype(bool)
        broken_binary = (broken_data > 0).astype(bool)
        corrected_binary = (corrected_data > 0).astype(bool)

        details['gt_tumor_voxels'] = int(np.sum(gt_binary))
        details['broken_tumor_voxels'] = int(np.sum(broken_binary))
        details['corrected_tumor_voxels'] = int(np.sum(corrected_binary))

        # ============================================================
        # DICE SCORES
        # ============================================================
        dice_before = dice_coefficient(broken_binary, gt_binary)
        dice_after = dice_coefficient(corrected_binary, gt_binary)
        dice_improvement = dice_after - dice_before

        details['dice_before'] = round(dice_before, 4)
        details['dice_after'] = round(dice_after, 4)
        details['dice_improvement'] = round(dice_improvement, 4)

        # ============================================================
        # DICE IMPROVEMENT (25 points)
        # ============================================================
        if dice_improvement > 0.05:
            improvement_score = w_improvement
            feedback_parts.append(f"Dice improved: {dice_before:.3f} -> {dice_after:.3f} (+{dice_improvement:.3f})")
        elif dice_improvement > 0:
            improvement_score = int(w_improvement * 0.5)
            feedback_parts.append(f"Dice slightly improved: {dice_before:.3f} -> {dice_after:.3f}")
        elif dice_improvement == 0:
            improvement_score = 0
            feedback_parts.append(f"Dice unchanged: {dice_before:.3f}")
        else:
            improvement_score = 0
            feedback_parts.append(f"Dice WORSENED: {dice_before:.3f} -> {dice_after:.3f}")
        score += improvement_score
        details['score_improvement'] = improvement_score

        # ============================================================
        # FINAL DICE QUALITY (20 points)
        # ============================================================
        if dice_after >= dice_after_min:
            final_dice_score = w_final_dice
            feedback_parts.append(f"Final Dice: {dice_after:.3f} >= {dice_after_min}")
        elif dice_after >= 0.70:
            final_dice_score = int(w_final_dice * 0.6)
            feedback_parts.append(f"Final Dice: {dice_after:.3f} (fair)")
        elif dice_after >= 0.50:
            final_dice_score = int(w_final_dice * 0.3)
            feedback_parts.append(f"Final Dice: {dice_after:.3f} (poor)")
        else:
            final_dice_score = 0
            feedback_parts.append(f"Final Dice: {dice_after:.3f} (very poor)")
        score += final_dice_score
        details['score_final_dice'] = final_dice_score

        # ============================================================
        # UNDER-SEGMENTATION FIXED (15 points)
        # Did agent add back missing regions?
        # ============================================================
        under_seg_region = gt_binary & ~broken_binary  # Regions missing in broken
        under_seg_total = int(np.sum(under_seg_region))

        if under_seg_total > 0:
            fixed_under = corrected_binary & under_seg_region  # Agent added back
            under_seg_recall = float(np.sum(fixed_under)) / under_seg_total
            details['under_seg_total_voxels'] = under_seg_total
            details['under_seg_fixed_voxels'] = int(np.sum(fixed_under))
            details['under_seg_recall'] = round(under_seg_recall, 4)

            if under_seg_recall >= 0.50:
                under_score = w_under_seg
                feedback_parts.append(f"Under-seg fixed: {under_seg_recall:.0%}")
            elif under_seg_recall >= 0.20:
                under_score = int(w_under_seg * 0.5)
                feedback_parts.append(f"Under-seg partially fixed: {under_seg_recall:.0%}")
            else:
                under_score = 0
                feedback_parts.append(f"Under-seg NOT fixed: {under_seg_recall:.0%}")
        else:
            under_score = w_under_seg  # No under-segmentation to fix
            under_seg_recall = 1.0
            feedback_parts.append("Under-seg: none to fix")
        score += under_score
        details['score_under_seg'] = under_score

        # ============================================================
        # OVER-SEGMENTATION FIXED (15 points)
        # Did agent remove false positive regions?
        # ============================================================
        over_seg_region = broken_binary & ~gt_binary  # False positives in broken
        over_seg_total = int(np.sum(over_seg_region))

        if over_seg_total > 0:
            fixed_over = ~corrected_binary & over_seg_region  # Agent removed
            over_seg_recall = float(np.sum(fixed_over)) / over_seg_total
            details['over_seg_total_voxels'] = over_seg_total
            details['over_seg_fixed_voxels'] = int(np.sum(fixed_over))
            details['over_seg_recall'] = round(over_seg_recall, 4)

            if over_seg_recall >= over_seg_recall_min:
                over_score = w_over_seg
                feedback_parts.append(f"Over-seg fixed: {over_seg_recall:.0%}")
            elif over_seg_recall >= 0.20:
                over_score = int(w_over_seg * 0.5)
                feedback_parts.append(f"Over-seg partially fixed: {over_seg_recall:.0%}")
            else:
                over_score = 0
                feedback_parts.append(f"Over-seg NOT fixed: {over_seg_recall:.0%}")
        else:
            over_score = w_over_seg  # No over-segmentation to fix
            over_seg_recall = 1.0
            feedback_parts.append("Over-seg: none to fix")
        score += over_score
        details['score_over_seg'] = over_score

        # ============================================================
        # PRESERVATION (10 points)
        # Did agent preserve correct regions?
        # ============================================================
        correctly_segmented = broken_binary & gt_binary  # Was correct in broken
        correctly_seg_total = int(np.sum(correctly_segmented))

        if correctly_seg_total > 0:
            still_correct = corrected_binary & correctly_segmented
            preservation = float(np.sum(still_correct)) / correctly_seg_total
            details['correct_region_voxels'] = correctly_seg_total
            details['preserved_voxels'] = int(np.sum(still_correct))
            details['preservation'] = round(preservation, 4)

            if preservation >= preservation_min:
                pres_score = w_preservation
                feedback_parts.append(f"Preserved: {preservation:.0%}")
            elif preservation >= 0.85:
                pres_score = int(w_preservation * 0.5)
                feedback_parts.append(f"Preservation fair: {preservation:.0%}")
            else:
                pres_score = 0
                feedback_parts.append(f"Preservation POOR: {preservation:.0%}")
        else:
            pres_score = w_preservation
            preservation = 1.0
            feedback_parts.append("Preservation: N/A")
        score += pres_score
        details['score_preservation'] = pres_score

    except FileNotFoundError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Could not load segmentation files: {e}",
            "details": to_python_type(details)
        }
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Verification error: {e}",
            "details": to_python_type(details)
        }
    finally:
        for f in [temp_gt.name, temp_broken.name, temp_corrected.name, temp_errors.name]:
            if os.path.exists(f):
                os.unlink(f)

    # ============================================================
    # REPORT COMPLETENESS (15 points)
    # ============================================================
    if result.get('report_exists', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/qc_agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report = json.load(f)

            # Check for error descriptions
            has_errors_found = any(k in report for k in [
                'errors_found', 'errors', 'findings', 'issues'])
            has_corrections = any(k in report for k in [
                'corrections', 'corrections_made', 'changes', 'fixes'])
            has_under_seg = False
            has_over_seg = False

            # Check content for mentions of under/over segmentation
            report_str = json.dumps(report).lower()
            has_under_seg = any(term in report_str for term in [
                'under-segm', 'undersegm', 'missing', 'not segmented', 'gap'])
            has_over_seg = any(term in report_str for term in [
                'over-segm', 'oversegm', 'false positive', 'incorrectly marked',
                'not tumor', 'extra'])

            completeness = sum([has_errors_found, has_corrections,
                                has_under_seg, has_over_seg]) / 4.0
            report_score = int(w_report * completeness)

            found_items = []
            if has_under_seg:
                found_items.append("under-seg")
            if has_over_seg:
                found_items.append("over-seg")
            if has_corrections:
                found_items.append("corrections")

            if found_items:
                feedback_parts.append(f"Report: mentions {', '.join(found_items)}")
            else:
                feedback_parts.append("Report: exists but lacks detail")

        except json.JSONDecodeError:
            report_score = int(w_report * 0.2)
            feedback_parts.append("Report: invalid JSON")
        except Exception as e:
            report_score = int(w_report * 0.1)
            feedback_parts.append(f"Report: error reading ({e})")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        report_score = 0
        feedback_parts.append("Report: NOT created")

    score += report_score
    details['score_report'] = report_score

    # ============================================================
    # FINAL SCORING
    # ============================================================
    passed = (dice_improvement > 0 and
              dice_after >= dice_after_min and
              preservation >= preservation_min and
              over_seg_recall >= over_seg_recall_min and
              score >= 50)

    if passed:
        if score >= 85:
            feedback_parts.append("Excellent QC corrections!")
        elif score >= 70:
            feedback_parts.append("Good QC corrections")
        else:
            feedback_parts.append("Acceptable QC corrections")
    else:
        reasons = []
        if dice_improvement <= 0:
            reasons.append("Dice not improved")
        if dice_after < dice_after_min:
            reasons.append(f"final Dice < {dice_after_min}")
        if preservation < preservation_min:
            reasons.append("too many correct regions damaged")
        if over_seg_recall < over_seg_recall_min:
            reasons.append("false positives not removed")
        feedback_parts.append(f"Task NOT completed - {'; '.join(reasons)}")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }
