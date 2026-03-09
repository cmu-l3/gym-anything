#!/usr/bin/env python3
"""
Verifier for brain tumor segmentation task using BraTS metrics.

VERIFICATION METRICS:
1. Dice Coefficient - measures overlap between predicted and ground truth
   - Whole Tumor (WT): All tumor regions (labels 1, 2, 4)
   - Tumor Core (TC): Core regions excluding edema (labels 1, 4)
   - Enhancing Tumor (ET): Enhancing tumor only (label 4)

2. Hausdorff Distance (95th percentile) - measures boundary accuracy
   - More robust than max Hausdorff, ignores outliers

3. Volume Accuracy - compares predicted vs actual tumor volume

BraTS Labels:
- 0: Background
- 1: Necrotic/Non-enhancing tumor core
- 2: Peritumoral edema
- 4: GD-enhancing tumor (note: 3 is not used in BraTS)
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
    from scipy.spatial.distance import directed_hausdorff
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
    elif isinstance(val, dict):
        return {k: to_python_type(v) for k, v in val.items()}
    elif isinstance(val, list):
        return [to_python_type(v) for v in val]
    return val


def dice_coefficient(pred: np.ndarray, gt: np.ndarray) -> float:
    """
    Calculate Dice coefficient between prediction and ground truth.

    Dice = 2 * |pred ∩ gt| / (|pred| + |gt|)

    Returns:
        float: Dice coefficient in range [0, 1]
    """
    pred = pred.astype(bool)
    gt = gt.astype(bool)

    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)

    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0

    return float(2.0 * intersection / sum_volumes)


def hausdorff_distance_95(pred: np.ndarray, gt: np.ndarray, voxel_spacing=(1.0, 1.0, 1.0)) -> float:
    """
    Calculate 95th percentile Hausdorff distance.

    This is more robust than max Hausdorff as it ignores outliers.

    Args:
        pred: Binary prediction mask
        gt: Binary ground truth mask
        voxel_spacing: Physical size of voxels (mm)

    Returns:
        float: HD95 in mm
    """
    pred = pred.astype(bool)
    gt = gt.astype(bool)

    # Handle empty masks
    if not np.any(pred) and not np.any(gt):
        return 0.0
    if not np.any(pred) or not np.any(gt):
        return float('inf')

    # Get surface points (boundary voxels)
    pred_surface = get_surface_points(pred)
    gt_surface = get_surface_points(gt)

    if len(pred_surface) == 0 or len(gt_surface) == 0:
        return float('inf')

    # Scale by voxel spacing
    pred_surface = pred_surface * np.array(voxel_spacing)
    gt_surface = gt_surface * np.array(voxel_spacing)

    # Calculate all pairwise distances
    from scipy.spatial import distance_matrix
    dist_pred_to_gt = np.min(distance_matrix(pred_surface, gt_surface), axis=1)
    dist_gt_to_pred = np.min(distance_matrix(gt_surface, pred_surface), axis=1)

    # Combine and get 95th percentile
    all_distances = np.concatenate([dist_pred_to_gt, dist_gt_to_pred])
    hd95 = np.percentile(all_distances, 95)

    return float(hd95)


def get_surface_points(mask: np.ndarray) -> np.ndarray:
    """
    Extract surface (boundary) points from a binary mask.

    Returns:
        Array of shape (N, 3) with coordinates of surface voxels
    """
    # Erode the mask
    eroded = ndimage.binary_erosion(mask)
    # Surface is the difference
    surface = mask & ~eroded
    # Get coordinates
    coords = np.array(np.where(surface)).T
    return coords


def calculate_volume(mask: np.ndarray, voxel_volume_mm3: float = 1.0) -> float:
    """Calculate volume in mm^3."""
    return np.sum(mask.astype(bool)) * voxel_volume_mm3


def get_brats_regions(seg: np.ndarray) -> dict:
    """
    Extract BraTS tumor regions from segmentation.

    BraTS uses hierarchical regions:
    - Whole Tumor (WT): labels 1, 2, 4
    - Tumor Core (TC): labels 1, 4
    - Enhancing Tumor (ET): label 4

    Returns:
        dict with boolean masks for each region
    """
    return {
        'whole_tumor': (seg == 1) | (seg == 2) | (seg == 4),
        'tumor_core': (seg == 1) | (seg == 4),
        'enhancing': seg == 4,
        'necrotic': seg == 1,
        'edema': seg == 2,
    }


def verify_brats_segmentation(traj, env_info, task_info):
    """
    Verify brain tumor segmentation using BraTS evaluation metrics.

    Scoring (100 points total):
    - Dice WT: 25 points (>0.5 threshold)
    - Dice TC: 15 points (>0.3 threshold)
    - Dice ET: 15 points (>0.3 threshold)
    - HD95: 10 points (< 30mm threshold)
    - Volume accuracy: 15 points (within 50%)
    - Volume reported: 10 points (within 30% of ground truth)
    - 3D visualization: 10 points (screenshots created)
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

    # Import here after ensuring availability
    import nibabel as nib

    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})

    dice_wt_threshold = thresholds.get('dice_whole_tumor', 0.5)
    dice_tc_threshold = thresholds.get('dice_tumor_core', 0.3)
    dice_et_threshold = thresholds.get('dice_enhancing', 0.3)
    hd95_threshold = thresholds.get('hausdorff_95_max_mm', 30)

    wt_weight = weights.get('dice_whole_tumor', 25)
    tc_weight = weights.get('dice_tumor_core', 15)
    et_weight = weights.get('dice_enhancing', 15)
    hd_weight = weights.get('hausdorff_metric', 10)
    vol_weight = weights.get('volume_accuracy', 15)
    report_weight = weights.get('volume_reported', 10)
    viz_weight = weights.get('visualization_created', 10)
    vol_error_threshold = thresholds.get('volume_error_max_percent', 30)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/brats_task_result.json", temp_result.name)
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
        logger.error(f"Failed to read result: {e}")
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
            "feedback": " | ".join(feedback_parts) + " | Task requires saving segmentation to ~/Documents/SlicerData/BraTS/agent_segmentation.nii.gz",
            "details": to_python_type(details)
        }

    # Load ground truth and agent segmentation
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    temp_pred = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')

    try:
        # Copy files from container
        copy_from_env("/tmp/ground_truth_seg.nii.gz", temp_gt.name)
        copy_from_env("/tmp/agent_segmentation.nii.gz", temp_pred.name)

        # Load NIfTI files
        gt_nii = nib.load(temp_gt.name)
        pred_nii = nib.load(temp_pred.name)

        gt_data = gt_nii.get_fdata().astype(np.int32)
        pred_data = pred_nii.get_fdata().astype(np.int32)

        # Get voxel spacing for volume calculations
        voxel_spacing = gt_nii.header.get_zooms()[:3]
        voxel_volume = np.prod(voxel_spacing)

        details['gt_shape'] = list(gt_data.shape)
        details['pred_shape'] = list(pred_data.shape)
        details['voxel_spacing'] = list(voxel_spacing)

        # Check shape match
        if gt_data.shape != pred_data.shape:
            feedback_parts.append(f"Shape mismatch: GT {gt_data.shape} vs Pred {pred_data.shape}")
            # Try to continue if shapes are similar
            if np.prod(gt_data.shape) != np.prod(pred_data.shape):
                return {
                    "passed": False,
                    "score": 5,
                    "feedback": " | ".join(feedback_parts),
                    "details": to_python_type(details)
                }

        # Get BraTS regions
        gt_regions = get_brats_regions(gt_data)
        pred_regions = get_brats_regions(pred_data)

        # ============================================================
        # DICE COEFFICIENTS
        # ============================================================

        # Dice Whole Tumor (30 points)
        dice_wt = dice_coefficient(pred_regions['whole_tumor'], gt_regions['whole_tumor'])
        details['dice_whole_tumor'] = round(dice_wt, 4)

        if dice_wt >= dice_wt_threshold:
            wt_score = wt_weight
            feedback_parts.append(f"Dice WT: {dice_wt:.3f} >= {dice_wt_threshold}")
        else:
            wt_score = int(wt_weight * (dice_wt / dice_wt_threshold))
            feedback_parts.append(f"Dice WT: {dice_wt:.3f} < {dice_wt_threshold}")
        score += wt_score
        details['score_dice_wt'] = wt_score

        # Dice Tumor Core (20 points)
        dice_tc = dice_coefficient(pred_regions['tumor_core'], gt_regions['tumor_core'])
        details['dice_tumor_core'] = round(dice_tc, 4)

        if dice_tc >= dice_tc_threshold:
            tc_score = tc_weight
            feedback_parts.append(f"Dice TC: {dice_tc:.3f} >= {dice_tc_threshold}")
        else:
            tc_score = int(tc_weight * (dice_tc / dice_tc_threshold))
            feedback_parts.append(f"Dice TC: {dice_tc:.3f} < {dice_tc_threshold}")
        score += tc_score
        details['score_dice_tc'] = tc_score

        # Dice Enhancing Tumor (20 points)
        # Handle case where there's no enhancing tumor in either
        gt_has_et = np.any(gt_regions['enhancing'])
        pred_has_et = np.any(pred_regions['enhancing'])

        if not gt_has_et and not pred_has_et:
            dice_et = 1.0  # Both correctly have no enhancing tumor
        elif not gt_has_et or not pred_has_et:
            dice_et = 0.0  # One has ET, other doesn't
        else:
            dice_et = dice_coefficient(pred_regions['enhancing'], gt_regions['enhancing'])

        details['dice_enhancing'] = round(dice_et, 4)

        if dice_et >= dice_et_threshold:
            et_score = et_weight
            feedback_parts.append(f"Dice ET: {dice_et:.3f} >= {dice_et_threshold}")
        else:
            et_score = int(et_weight * (dice_et / dice_et_threshold))
            feedback_parts.append(f"Dice ET: {dice_et:.3f} < {dice_et_threshold}")
        score += et_score
        details['score_dice_et'] = et_score

        # ============================================================
        # HAUSDORFF DISTANCE (15 points)
        # ============================================================

        # Calculate HD95 for whole tumor
        hd95 = hausdorff_distance_95(
            pred_regions['whole_tumor'],
            gt_regions['whole_tumor'],
            voxel_spacing
        )
        details['hausdorff_95'] = round(hd95, 2) if not np.isinf(hd95) else "inf"

        if hd95 <= hd95_threshold:
            hd_score = hd_weight
            feedback_parts.append(f"HD95: {hd95:.1f}mm <= {hd95_threshold}mm")
        elif np.isinf(hd95):
            hd_score = 0
            feedback_parts.append(f"HD95: inf (no overlap)")
        else:
            # Partial credit for being close
            hd_score = max(0, int(hd_weight * (1 - (hd95 - hd95_threshold) / hd95_threshold)))
            feedback_parts.append(f"HD95: {hd95:.1f}mm > {hd95_threshold}mm")
        score += hd_score
        details['score_hausdorff'] = hd_score

        # ============================================================
        # VOLUME ACCURACY (15 points)
        # ============================================================

        gt_volume = calculate_volume(gt_regions['whole_tumor'], voxel_volume)
        pred_volume = calculate_volume(pred_regions['whole_tumor'], voxel_volume)

        details['gt_volume_mm3'] = round(gt_volume, 1)
        details['pred_volume_mm3'] = round(pred_volume, 1)

        if gt_volume > 0:
            volume_ratio = pred_volume / gt_volume
            volume_error = abs(1 - volume_ratio)

            if volume_error <= 0.2:  # Within 20%
                vol_score = vol_weight
                feedback_parts.append(f"Vol: {volume_ratio:.2f}x (within 20%)")
            elif volume_error <= 0.5:  # Within 50%
                vol_score = int(vol_weight * 0.6)
                feedback_parts.append(f"Vol: {volume_ratio:.2f}x (within 50%)")
            else:
                vol_score = int(vol_weight * max(0, 1 - volume_error))
                feedback_parts.append(f"Vol: {volume_ratio:.2f}x (>50% error)")
        else:
            vol_score = vol_weight if pred_volume == 0 else 0
            feedback_parts.append(f"Vol: GT=0, Pred={pred_volume:.0f}mm³")

        score += vol_score
        details['score_volume'] = vol_score
        details['volume_ratio'] = round(volume_ratio, 3) if gt_volume > 0 else None

        # Store ground truth volume for report verification
        gt_volume_ml = gt_volume / 1000  # Convert mm³ to mL
        details['gt_volume_ml'] = round(gt_volume_ml, 2)

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
        for f in [temp_gt.name, temp_pred.name]:
            if os.path.exists(f):
                os.unlink(f)

    # ============================================================
    # VLM VISUAL CHECK (bonus, not required for passing)
    # ============================================================

    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            copy_from_env("/tmp/brats_final.png", temp_screenshot.name)

            vlm_result = query_vlm(
                prompt="""Examine this 3D Slicer screenshot showing brain tumor segmentation.

Check for:
1. Is a tumor segmentation visible? (colored overlay on brain MRI)
2. Does the segmentation appear to cover the tumor region?
3. Is the segmentation reasonable quality (not just noise)?

Respond in JSON:
{
    "segmentation_visible": true/false,
    "appears_reasonable": true/false,
    "observations": "what you see"
}""",
                image=temp_screenshot.name
            )

            if vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_check'] = parsed
                if parsed.get('segmentation_visible') and parsed.get('appears_reasonable'):
                    feedback_parts.append("VLM: segmentation visible")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
        finally:
            if os.path.exists(temp_screenshot.name):
                os.unlink(temp_screenshot.name)

    # ============================================================
    # VOLUME REPORT CHECK (10 points)
    # ============================================================

    volume_reported = result.get('volume_report_exists', False)
    reported_volume_str = result.get('reported_volume_ml', '')
    details['volume_report_exists'] = volume_reported

    if volume_reported and reported_volume_str:
        try:
            reported_volume_ml = float(reported_volume_str)
            details['reported_volume_ml'] = reported_volume_ml

            # Check accuracy of reported volume against ground truth
            gt_vol_ml = details.get('gt_volume_ml', 0)
            if gt_vol_ml > 0:
                report_error = abs(reported_volume_ml - gt_vol_ml) / gt_vol_ml * 100
                details['volume_report_error_percent'] = round(report_error, 1)

                if report_error <= vol_error_threshold:
                    report_score = report_weight
                    feedback_parts.append(f"Report: {reported_volume_ml:.1f}mL (within {vol_error_threshold}%)")
                else:
                    report_score = int(report_weight * 0.5)  # Partial credit for trying
                    feedback_parts.append(f"Report: {reported_volume_ml:.1f}mL ({report_error:.0f}% error)")
            else:
                report_score = report_weight  # Can't verify, give credit for reporting
                feedback_parts.append(f"Report: {reported_volume_ml:.1f}mL")
        except (ValueError, TypeError):
            report_score = int(report_weight * 0.5)  # Partial credit
            feedback_parts.append("Report: volume not parseable")
    elif volume_reported:
        report_score = int(report_weight * 0.3)  # Small credit for creating file
        feedback_parts.append("Report: file exists but no volume found")
    else:
        report_score = 0
        feedback_parts.append("Report: NOT created")

    score += report_score
    details['score_report'] = report_score

    # ============================================================
    # VISUALIZATION CHECK (10 points)
    # ============================================================

    visualization_created = result.get('visualization_created', False)
    agent_screenshots = result.get('agent_screenshots_count', 0)
    details['visualization_created'] = visualization_created
    details['agent_screenshots_count'] = agent_screenshots

    if visualization_created:
        viz_score = viz_weight
        feedback_parts.append(f"3D Viz: created ({agent_screenshots} screenshots)")
    else:
        viz_score = 0
        feedback_parts.append("3D Viz: NOT created")

    score += viz_score
    details['score_visualization'] = viz_score

    # ============================================================
    # FINAL SCORING
    # ============================================================

    # Passing requires:
    # - Dice WT >= threshold
    # - Total score >= 60
    passed = (dice_wt >= dice_wt_threshold) and (score >= 60)

    if passed:
        if score >= 90:
            feedback_parts.append("Excellent segmentation!")
        elif score >= 75:
            feedback_parts.append("Good segmentation")
        else:
            feedback_parts.append("Acceptable segmentation")
    else:
        feedback_parts.append("Task NOT completed - improve Dice scores")

    return {
        "passed": bool(passed),
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": to_python_type(details)
    }
