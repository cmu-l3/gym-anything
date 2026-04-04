#!/usr/bin/env python3
"""
Verifier for liver surgical planning task.

VERIFICATION METRICS:
1. Dice Coefficient for each structure (liver, tumor, portal vein)
2. Tumor volume accuracy
3. Tumor count accuracy
4. Tumor-to-portal-vein distance accuracy
5. Vascular invasion assessment (binary: correct/incorrect)

Ground Truth: 3D-IRCADb dataset masks
- Label 1: Liver parenchyma
- Label 2: Liver tumor(s)
- Label 3: Portal vein
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
ndimage = None
NIBABEL_AVAILABLE = False

try:
    import nibabel as nib
    from scipy import ndimage
    from scipy.ndimage import distance_transform_edt, label as scipy_label
    NIBABEL_AVAILABLE = True
except ImportError:
    logger.warning("nibabel/scipy not available - will try to install")


def ensure_dependencies():
    """Ensure required packages are available."""
    global NIBABEL_AVAILABLE, nib, ndimage
    if not NIBABEL_AVAILABLE:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
            import nibabel as nib_module
            from scipy import ndimage as ndimage_module
            nib = nib_module
            ndimage = ndimage_module
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


def verify_liver_surgical_planning(traj, env_info, task_info):
    """
    Verify liver surgical planning task completion.

    Scoring (100 points total):
    - Dice liver: 20 points (>= 0.85 threshold)
    - Dice tumor: 20 points (>= 0.50 threshold)
    - Dice portal vein: 10 points (>= 0.30 threshold)
    - Tumor volume accuracy: 10 points (within 30%)
    - Tumor count correct: 10 points
    - Distance accuracy: 15 points (within 5mm)
    - Invasion assessment correct: 10 points
    - Report completeness: 5 points
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
            "feedback": "Required packages (nibabel, scipy) could not be installed"
        }

    import nibabel as nib
    from scipy.ndimage import distance_transform_edt, label as scipy_label

    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})

    dice_liver_threshold = thresholds.get('dice_liver', 0.85)
    dice_tumor_threshold = thresholds.get('dice_tumor', 0.50)
    distance_error_threshold = thresholds.get('distance_error_max_mm', 5.0)
    vol_error_threshold = thresholds.get('volume_error_max_percent', 30)

    w_dice_liver = weights.get('dice_liver', 20)
    w_dice_tumor = weights.get('dice_tumor', 20)
    w_dice_portal = weights.get('dice_portal_vein', 10)
    w_tumor_vol = weights.get('tumor_volume_accuracy', 10)
    w_tumor_count = weights.get('tumor_count_correct', 10)
    w_distance = weights.get('distance_accuracy', 15)
    w_invasion = weights.get('invasion_correct', 10)
    w_report = weights.get('report_completeness', 5)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/liver_task_result.json", temp_result.name)
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

    # Check if agent created a segmentation
    if not result.get('agent_segmentation_exists', False):
        feedback_parts.append("No segmentation file created by agent")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }

    # ============================================================
    # LOAD GROUND TRUTH AND AGENT SEGMENTATION
    # ============================================================
    temp_gt_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    temp_gt_stats = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_pred = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')

    try:
        copy_from_env("/tmp/liver_ground_truth_seg.nii.gz", temp_gt_seg.name)
        copy_from_env("/tmp/liver_ground_truth_stats.json", temp_gt_stats.name)
        copy_from_env("/tmp/liver_agent_segmentation.nii.gz", temp_pred.name)

        # Load NIfTI files
        gt_nii = nib.load(temp_gt_seg.name)
        pred_nii = nib.load(temp_pred.name)
        gt_data = gt_nii.get_fdata().astype(np.int32)
        pred_data = pred_nii.get_fdata().astype(np.int32)

        # Load ground truth stats
        with open(temp_gt_stats.name, 'r') as f:
            gt_stats = json.load(f)

        voxel_spacing = gt_nii.header.get_zooms()[:3]
        voxel_volume_mm3 = float(np.prod(voxel_spacing))
        voxel_volume_ml = voxel_volume_mm3 / 1000.0

        details['gt_shape'] = list(gt_data.shape)
        details['pred_shape'] = list(pred_data.shape)
        details['voxel_spacing'] = [float(s) for s in voxel_spacing]

        # Check shape compatibility
        if gt_data.shape != pred_data.shape:
            feedback_parts.append(f"Shape mismatch: GT {gt_data.shape} vs Pred {pred_data.shape}")
            if np.prod(gt_data.shape) != np.prod(pred_data.shape):
                return {
                    "passed": False,
                    "score": 5,
                    "feedback": " | ".join(feedback_parts),
                    "details": to_python_type(details)
                }

        # Extract structures
        # Ground truth: 1=liver, 2=tumor, 3=portal_vein
        gt_liver = (gt_data == 1) | (gt_data == 2)  # Liver includes tumor area
        gt_tumor = (gt_data == 2)
        gt_portal = (gt_data == 3)

        # Agent prediction
        pred_liver = (pred_data == 1) | (pred_data == 2)
        pred_tumor = (pred_data == 2)
        pred_portal = (pred_data == 3)

        # ============================================================
        # DICE COEFFICIENTS
        # ============================================================

        # Dice Liver
        dice_liver = dice_coefficient(pred_liver, gt_liver)
        details['dice_liver'] = round(dice_liver, 4)
        if dice_liver >= dice_liver_threshold:
            liver_score = w_dice_liver
            feedback_parts.append(f"Dice Liver: {dice_liver:.3f} >= {dice_liver_threshold}")
        else:
            liver_score = int(w_dice_liver * (dice_liver / dice_liver_threshold))
            feedback_parts.append(f"Dice Liver: {dice_liver:.3f} < {dice_liver_threshold}")
        score += liver_score
        details['score_dice_liver'] = liver_score

        # Dice Tumor
        if np.any(gt_tumor):
            dice_tumor = dice_coefficient(pred_tumor, gt_tumor)
        else:
            dice_tumor = 1.0 if not np.any(pred_tumor) else 0.0
        details['dice_tumor'] = round(dice_tumor, 4)
        if dice_tumor >= dice_tumor_threshold:
            tumor_dice_score = w_dice_tumor
            feedback_parts.append(f"Dice Tumor: {dice_tumor:.3f} >= {dice_tumor_threshold}")
        else:
            tumor_dice_score = int(w_dice_tumor * (dice_tumor / dice_tumor_threshold))
            feedback_parts.append(f"Dice Tumor: {dice_tumor:.3f} < {dice_tumor_threshold}")
        score += tumor_dice_score
        details['score_dice_tumor'] = tumor_dice_score

        # Dice Portal Vein
        if np.any(gt_portal):
            dice_portal = dice_coefficient(pred_portal, gt_portal)
        else:
            dice_portal = 1.0 if not np.any(pred_portal) else 0.0
        details['dice_portal_vein'] = round(dice_portal, 4)
        if dice_portal >= 0.30:
            portal_score = w_dice_portal
            feedback_parts.append(f"Dice Portal: {dice_portal:.3f} >= 0.30")
        else:
            portal_score = int(w_dice_portal * (dice_portal / 0.30))
            feedback_parts.append(f"Dice Portal: {dice_portal:.3f} < 0.30")
        score += portal_score
        details['score_dice_portal'] = portal_score

        # ============================================================
        # TUMOR VOLUME ACCURACY
        # ============================================================
        gt_tumor_vol_ml = float(np.sum(gt_tumor) * voxel_volume_ml)
        pred_tumor_vol_ml = float(np.sum(pred_tumor) * voxel_volume_ml)
        details['gt_tumor_volume_ml'] = round(gt_tumor_vol_ml, 2)
        details['pred_tumor_volume_ml'] = round(pred_tumor_vol_ml, 2)

        if gt_tumor_vol_ml > 0:
            vol_error_pct = abs(pred_tumor_vol_ml - gt_tumor_vol_ml) / gt_tumor_vol_ml * 100
            details['tumor_volume_error_pct'] = round(vol_error_pct, 1)
            if vol_error_pct <= vol_error_threshold:
                vol_score = w_tumor_vol
                feedback_parts.append(f"Tumor Vol: {vol_error_pct:.0f}% error (within {vol_error_threshold}%)")
            elif vol_error_pct <= 50:
                vol_score = int(w_tumor_vol * 0.5)
                feedback_parts.append(f"Tumor Vol: {vol_error_pct:.0f}% error")
            else:
                vol_score = 0
                feedback_parts.append(f"Tumor Vol: {vol_error_pct:.0f}% error (too large)")
        else:
            vol_score = w_tumor_vol if pred_tumor_vol_ml == 0 else 0
            feedback_parts.append(f"Tumor Vol: GT=0, Pred={pred_tumor_vol_ml:.1f}mL")
        score += vol_score
        details['score_tumor_volume'] = vol_score

        # ============================================================
        # TUMOR COUNT
        # ============================================================
        gt_tumor_count = gt_stats.get('tumor_count', 0)
        if gt_tumor_count == 0 and np.any(gt_tumor):
            _, gt_tumor_count = scipy_label(gt_tumor)

        if np.any(pred_tumor):
            _, pred_tumor_count = scipy_label(pred_tumor)
        else:
            pred_tumor_count = 0

        details['gt_tumor_count'] = int(gt_tumor_count)
        details['pred_tumor_count'] = int(pred_tumor_count)

        if pred_tumor_count == gt_tumor_count:
            count_score = w_tumor_count
            feedback_parts.append(f"Tumor Count: {pred_tumor_count} (correct)")
        elif abs(pred_tumor_count - gt_tumor_count) <= 1:
            count_score = int(w_tumor_count * 0.5)
            feedback_parts.append(f"Tumor Count: {pred_tumor_count} (GT: {gt_tumor_count}, off by 1)")
        else:
            count_score = 0
            feedback_parts.append(f"Tumor Count: {pred_tumor_count} (GT: {gt_tumor_count})")
        score += count_score
        details['score_tumor_count'] = count_score

        # ============================================================
        # TUMOR-TO-PORTAL DISTANCE
        # ============================================================
        gt_min_distance = gt_stats.get('min_tumor_portal_distance_mm', -1)

        if np.any(pred_tumor) and np.any(pred_portal):
            pred_portal_dt = distance_transform_edt(~pred_portal, sampling=voxel_spacing)
            pred_min_distance = float(pred_portal_dt[pred_tumor].min())
        else:
            pred_min_distance = -1.0

        details['gt_min_distance_mm'] = gt_min_distance
        details['pred_min_distance_mm'] = round(pred_min_distance, 2) if pred_min_distance >= 0 else -1

        if gt_min_distance >= 0 and pred_min_distance >= 0:
            distance_error = abs(pred_min_distance - gt_min_distance)
            details['distance_error_mm'] = round(distance_error, 2)
            if distance_error <= distance_error_threshold:
                dist_score = w_distance
                feedback_parts.append(f"Distance: {distance_error:.1f}mm error (within {distance_error_threshold}mm)")
            elif distance_error <= 10:
                dist_score = int(w_distance * 0.5)
                feedback_parts.append(f"Distance: {distance_error:.1f}mm error")
            else:
                dist_score = 0
                feedback_parts.append(f"Distance: {distance_error:.1f}mm error (too large)")
        else:
            dist_score = 0
            feedback_parts.append("Distance: could not compute")
        score += dist_score
        details['score_distance'] = dist_score

        # ============================================================
        # VASCULAR INVASION ASSESSMENT
        # ============================================================
        gt_invasion = gt_stats.get('vascular_invasion', False)
        pred_invasion = pred_min_distance < 1.0 if pred_min_distance >= 0 else False
        details['gt_vascular_invasion'] = gt_invasion
        details['pred_vascular_invasion'] = pred_invasion

        if pred_invasion == gt_invasion:
            invasion_score = w_invasion
            feedback_parts.append(f"Invasion: {'Yes' if pred_invasion else 'No'} (correct)")
        else:
            invasion_score = 0
            feedback_parts.append(f"Invasion: {'Yes' if pred_invasion else 'No'} (GT: {'Yes' if gt_invasion else 'No'})")
        score += invasion_score
        details['score_invasion'] = invasion_score

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
        for f in [temp_gt_seg.name, temp_gt_stats.name, temp_pred.name]:
            if os.path.exists(f):
                os.unlink(f)

    # ============================================================
    # REPORT COMPLETENESS
    # ============================================================
    if result.get('report_exists', False):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/liver_agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                report = json.load(f)

            required_fields = ['tumor_volume', 'tumor_count', 'min_distance', 'vascular_invasion']
            # Check with flexible key names
            found = 0
            for field in required_fields:
                for key in report.keys():
                    if field.replace('_', '') in key.lower().replace('_', ''):
                        found += 1
                        break

            report_score = int(w_report * (found / len(required_fields)))
            feedback_parts.append(f"Report: {found}/{len(required_fields)} fields")
        except Exception as e:
            report_score = int(w_report * 0.2)
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
    passed = (dice_liver >= dice_liver_threshold and
              dice_tumor >= dice_tumor_threshold and
              score >= 55)

    if passed:
        if score >= 85:
            feedback_parts.append("Excellent surgical planning!")
        elif score >= 70:
            feedback_parts.append("Good surgical planning")
        else:
            feedback_parts.append("Acceptable surgical planning")
    else:
        feedback_parts.append("Task NOT completed - improve segmentation accuracy")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }
