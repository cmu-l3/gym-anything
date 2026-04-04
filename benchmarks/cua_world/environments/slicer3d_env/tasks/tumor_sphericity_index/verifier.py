#!/usr/bin/env python3
"""
Verifier for Brain Tumor Shape Analysis - Sphericity Index task.

VERIFICATION METRICS:
1. Segmentation Quality (Dice coefficient)
2. Volume Accuracy
3. Surface Area Accuracy  
4. Sphericity Accuracy
5. Morphology Classification
6. Report Completeness
7. 3D Visualization

Sphericity = (π^(1/3) × (6V)^(2/3)) / A
Where V = volume, A = surface area
"""

import json
import os
import sys
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Optional dependencies
nib = None
ndimage = None
measure = None
DEPS_AVAILABLE = False


def ensure_dependencies():
    """Ensure required packages are available."""
    global DEPS_AVAILABLE, nib, ndimage, measure
    if DEPS_AVAILABLE:
        return True
    try:
        import nibabel as nib_mod
        from scipy import ndimage as ndimage_mod
        from skimage import measure as measure_mod
        nib = nib_mod
        ndimage = ndimage_mod
        measure = measure_mod
        DEPS_AVAILABLE = True
        return True
    except ImportError:
        try:
            import subprocess
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", 
                                   "nibabel", "scipy", "scikit-image"])
            import nibabel as nib_mod
            from scipy import ndimage as ndimage_mod
            from skimage import measure as measure_mod
            nib = nib_mod
            ndimage = ndimage_mod
            measure = measure_mod
            DEPS_AVAILABLE = True
            return True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False


def to_python_type(val):
    """Convert numpy types to Python native types."""
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


def dice_coefficient(pred: np.ndarray, gt: np.ndarray) -> float:
    """Calculate Dice coefficient between prediction and ground truth."""
    pred = pred.astype(bool)
    gt = gt.astype(bool)
    
    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)
    
    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0
    
    return float(2.0 * intersection / sum_volumes)


def calculate_shape_metrics(binary_mask: np.ndarray, voxel_dims: tuple) -> dict:
    """
    Calculate shape metrics for a binary mask.
    
    Returns:
        dict with volume_ml, surface_area_mm2, sphericity
    """
    if not np.any(binary_mask):
        return {
            "volume_ml": 0.0,
            "surface_area_mm2": 0.0,
            "sphericity": 0.0,
        }
    
    voxel_volume_mm3 = float(np.prod(voxel_dims))
    
    # Volume
    tumor_voxels = int(np.sum(binary_mask))
    volume_mm3 = tumor_voxels * voxel_volume_mm3
    volume_ml = volume_mm3 / 1000.0
    
    # Surface area using marching cubes
    try:
        padded = np.pad(binary_mask, pad_width=1, mode='constant', constant_values=0)
        verts, faces, _, _ = measure.marching_cubes(padded, level=0.5, spacing=voxel_dims)
        surface_area_mm2 = measure.mesh_surface_area(verts, faces)
    except Exception as e:
        logger.warning(f"Marching cubes failed: {e}, using approximation")
        eroded = ndimage.binary_erosion(binary_mask)
        boundary = binary_mask.astype(bool) & ~eroded
        boundary_voxels = np.sum(boundary)
        avg_face_area = (voxel_dims[0] * voxel_dims[1] + 
                         voxel_dims[1] * voxel_dims[2] + 
                         voxel_dims[0] * voxel_dims[2]) / 3
        surface_area_mm2 = boundary_voxels * avg_face_area
    
    # Sphericity
    if surface_area_mm2 > 0:
        sphericity = (np.pi ** (1/3)) * ((6 * volume_mm3) ** (2/3)) / surface_area_mm2
        sphericity = min(1.0, max(0.0, sphericity))
    else:
        sphericity = 0.0
    
    return {
        "volume_ml": float(volume_ml),
        "surface_area_mm2": float(surface_area_mm2),
        "sphericity": float(sphericity),
    }


def get_morphology_class(sphericity: float) -> str:
    """Classify morphology based on sphericity."""
    if sphericity > 0.7:
        return "Regular"
    elif sphericity >= 0.5:
        return "Intermediate"
    else:
        return "Irregular"


def verify_tumor_sphericity(traj, env_info, task_info):
    """
    Verify tumor sphericity index task completion.
    
    Scoring (100 points total):
    - Segmentation Dice >= 0.5: 30 points
    - Dice >= 0.65 bonus: 5 points
    - Volume within 30%: 15 points
    - Surface area within 40%: 10 points
    - Sphericity within ±0.15: 20 points
    - Morphology class correct: 10 points
    - Report completeness: 10 points
    - 3D visualization: 5 points (bonus)
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
            "feedback": "Failed to load required dependencies (nibabel, scipy, scikit-image)"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    dice_threshold = thresholds.get('dice_whole_tumor', 0.5)
    sphericity_error_max = thresholds.get('sphericity_error_max', 0.15)
    volume_error_max = thresholds.get('volume_error_max_percent', 30) / 100.0
    surface_error_max = thresholds.get('surface_area_error_max_percent', 40) / 100.0
    
    w_dice = weights.get('segmentation_dice', 30)
    w_dice_bonus = weights.get('segmentation_dice_bonus', 5)
    w_volume = weights.get('volume_accuracy', 15)
    w_surface = weights.get('surface_area_accuracy', 10)
    w_sphericity = weights.get('sphericity_accuracy', 20)
    w_class = weights.get('morphology_class', 10)
    w_report = weights.get('report_completeness', 10)
    w_viz = weights.get('visualization_3d', 5)
    
    # Load result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/sphericity_task_result.json", temp_result.name)
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
    
    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    # Check anti-gaming: segmentation created during task
    if not result.get('segmentation_created_during_task', False) and result.get('agent_segmentation_exists', False):
        feedback_parts.append("⚠️ Segmentation may have existed before task")
    
    # ================================================================
    # LOAD GROUND TRUTH SHAPE METRICS
    # ================================================================
    temp_gt_shape = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_shape = {}
    try:
        copy_from_env("/tmp/gt_shape.json", temp_gt_shape.name)
        with open(temp_gt_shape.name, 'r') as f:
            gt_shape = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load GT shape metrics: {e}")
    finally:
        if os.path.exists(temp_gt_shape.name):
            os.unlink(temp_gt_shape.name)
    
    gt_volume = gt_shape.get('volume_ml', 0)
    gt_surface = gt_shape.get('surface_area_mm2', 0)
    gt_sphericity = gt_shape.get('sphericity', 0)
    gt_class = gt_shape.get('morphology_class', '')
    
    details['gt_volume_ml'] = gt_volume
    details['gt_surface_area_mm2'] = gt_surface
    details['gt_sphericity'] = gt_sphericity
    details['gt_morphology_class'] = gt_class
    
    # ================================================================
    # LOAD AND EVALUATE SEGMENTATION
    # ================================================================
    dice_wt = 0.0
    agent_shape = {"volume_ml": 0, "surface_area_mm2": 0, "sphericity": 0}
    
    if result.get('agent_segmentation_exists', False):
        # Load ground truth segmentation
        temp_gt_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        temp_agent_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        
        try:
            copy_from_env("/tmp/gt_seg.nii.gz", temp_gt_seg.name)
            copy_from_env("/tmp/agent_seg.nii.gz", temp_agent_seg.name)
            
            gt_nii = nib.load(temp_gt_seg.name)
            gt_data = gt_nii.get_fdata().astype(np.int32)
            voxel_dims = gt_nii.header.get_zooms()[:3]
            
            agent_nii = nib.load(temp_agent_seg.name)
            agent_data = agent_nii.get_fdata().astype(np.int32)
            
            # Create whole tumor masks (all non-zero labels)
            gt_wt = (gt_data > 0).astype(np.uint8)
            agent_wt = (agent_data > 0).astype(np.uint8)
            
            # Calculate Dice
            dice_wt = dice_coefficient(agent_wt, gt_wt)
            details['dice_whole_tumor'] = round(dice_wt, 4)
            
            # Calculate agent's shape metrics
            agent_shape = calculate_shape_metrics(agent_wt, voxel_dims)
            details['agent_volume_ml'] = round(agent_shape['volume_ml'], 2)
            details['agent_surface_area_mm2'] = round(agent_shape['surface_area_mm2'], 2)
            details['agent_sphericity_computed'] = round(agent_shape['sphericity'], 4)
            
        except Exception as e:
            logger.error(f"Error processing segmentation: {e}")
            feedback_parts.append(f"⚠️ Error processing segmentation: {e}")
        finally:
            for tf in [temp_gt_seg, temp_agent_seg]:
                if os.path.exists(tf.name):
                    os.unlink(tf.name)
    else:
        feedback_parts.append("❌ No segmentation file found")
    
    # ================================================================
    # CRITERION 1: Segmentation Dice (30 + 5 bonus points)
    # ================================================================
    if dice_wt >= dice_threshold:
        score += w_dice
        feedback_parts.append(f"✅ Segmentation Dice: {dice_wt:.3f} (>= {dice_threshold})")
        
        # Bonus for better segmentation
        if dice_wt >= 0.65:
            score += w_dice_bonus
            feedback_parts.append(f"🌟 Dice bonus for excellent segmentation")
    elif dice_wt > 0:
        partial = int(w_dice * (dice_wt / dice_threshold))
        score += partial
        feedback_parts.append(f"⚠️ Segmentation Dice: {dice_wt:.3f} (threshold: {dice_threshold})")
    else:
        feedback_parts.append(f"❌ Segmentation Dice: {dice_wt:.3f}")
    
    # ================================================================
    # CRITERION 2: Volume Accuracy (15 points)
    # ================================================================
    if gt_volume > 0 and agent_shape['volume_ml'] > 0:
        volume_error = abs(agent_shape['volume_ml'] - gt_volume) / gt_volume
        details['volume_error_percent'] = round(volume_error * 100, 1)
        
        if volume_error <= volume_error_max:
            score += w_volume
            feedback_parts.append(f"✅ Volume within {volume_error*100:.1f}% (threshold: {volume_error_max*100}%)")
        else:
            partial = max(0, int(w_volume * (1 - (volume_error - volume_error_max) / volume_error_max)))
            score += partial
            feedback_parts.append(f"⚠️ Volume error: {volume_error*100:.1f}%")
    else:
        feedback_parts.append("❌ Could not verify volume accuracy")
    
    # ================================================================
    # CRITERION 3: Surface Area Accuracy (10 points)
    # ================================================================
    if gt_surface > 0 and agent_shape['surface_area_mm2'] > 0:
        surface_error = abs(agent_shape['surface_area_mm2'] - gt_surface) / gt_surface
        details['surface_error_percent'] = round(surface_error * 100, 1)
        
        if surface_error <= surface_error_max:
            score += w_surface
            feedback_parts.append(f"✅ Surface area within {surface_error*100:.1f}%")
        else:
            partial = max(0, int(w_surface * (1 - (surface_error - surface_error_max) / surface_error_max)))
            score += partial
            feedback_parts.append(f"⚠️ Surface area error: {surface_error*100:.1f}%")
    else:
        feedback_parts.append("❌ Could not verify surface area accuracy")
    
    # ================================================================
    # CRITERION 4: Sphericity Accuracy (20 points)
    # ================================================================
    # Use reported sphericity if available, otherwise computed from segmentation
    reported_sph_str = result.get('reported_sphericity', '')
    reported_sphericity = None
    if reported_sph_str:
        try:
            reported_sphericity = float(reported_sph_str)
        except (ValueError, TypeError):
            pass
    
    agent_sphericity = reported_sphericity if reported_sphericity is not None else agent_shape['sphericity']
    details['agent_sphericity_used'] = round(agent_sphericity, 4) if agent_sphericity else 0
    
    if gt_sphericity > 0 and agent_sphericity:
        sphericity_error = abs(agent_sphericity - gt_sphericity)
        details['sphericity_error'] = round(sphericity_error, 4)
        
        if sphericity_error <= sphericity_error_max:
            score += w_sphericity
            feedback_parts.append(f"✅ Sphericity {agent_sphericity:.3f} within ±{sphericity_error_max} of GT ({gt_sphericity:.3f})")
        else:
            partial = max(0, int(w_sphericity * (1 - (sphericity_error - sphericity_error_max) / 0.3)))
            score += partial
            feedback_parts.append(f"⚠️ Sphericity {agent_sphericity:.3f} vs GT {gt_sphericity:.3f} (error: {sphericity_error:.3f})")
    else:
        feedback_parts.append("❌ Could not verify sphericity accuracy")
    
    # ================================================================
    # CRITERION 5: Morphology Classification (10 points)
    # ================================================================
    reported_class = result.get('reported_classification', '').strip()
    details['agent_classification'] = reported_class
    
    # Determine expected class from agent's sphericity
    if agent_sphericity:
        expected_agent_class = get_morphology_class(agent_sphericity)
    else:
        expected_agent_class = gt_class
    
    if reported_class:
        # Normalize comparison
        reported_class_norm = reported_class.lower()
        gt_class_norm = gt_class.lower() if gt_class else ''
        expected_norm = expected_agent_class.lower() if expected_agent_class else ''
        
        if reported_class_norm == gt_class_norm or reported_class_norm == expected_norm:
            score += w_class
            feedback_parts.append(f"✅ Morphology class correct: {reported_class}")
        elif reported_class_norm in ['regular', 'intermediate', 'irregular']:
            # Partial credit for valid classification
            score += w_class // 2
            feedback_parts.append(f"⚠️ Morphology class '{reported_class}' (expected: {gt_class})")
        else:
            feedback_parts.append(f"❌ Invalid morphology class: {reported_class}")
    else:
        feedback_parts.append("❌ No morphology classification reported")
    
    # ================================================================
    # CRITERION 6: Report Completeness (10 points)
    # ================================================================
    if result.get('report_complete', False):
        score += w_report
        feedback_parts.append("✅ Report complete with all required fields")
    elif result.get('report_exists', False):
        score += w_report // 2
        feedback_parts.append("⚠️ Report exists but incomplete")
    else:
        feedback_parts.append("❌ No shape report found")
    
    # ================================================================
    # CRITERION 7: 3D Visualization (5 bonus points)
    # ================================================================
    if result.get('visualization_created', False):
        score += w_viz
        feedback_parts.append("✅ 3D visualization created")
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    key_criteria_met = dice_wt >= dice_threshold
    passed = score >= 60 and key_criteria_met
    
    # Cap score at 100
    score = min(100, score)
    
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details,
        "subscores": {
            "dice_whole_tumor": round(dice_wt, 4),
            "volume_ml": round(agent_shape['volume_ml'], 2),
            "surface_area_mm2": round(agent_shape['surface_area_mm2'], 2),
            "sphericity": round(agent_sphericity, 4) if agent_sphericity else 0,
            "classification": reported_class,
        }
    })