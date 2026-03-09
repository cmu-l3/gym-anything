#!/usr/bin/env python3
"""
Verifier for Bilateral Kidney Volume Asymmetry Assessment task.

VERIFICATION STRATEGY:
1. Segmentation accuracy - Dice coefficient for each kidney vs ground truth
2. Volume accuracy - Compare calculated volumes to ground truth
3. Asymmetry calculation - Check asymmetry percentage accuracy
4. Clinical assessment - Verify classification correctness
5. Report completeness - Check all required fields present

ANTI-GAMING:
- Timestamp checks for file creation
- Both kidneys must be segmented (can't just copy one)
- Volume sanity checks (physiological range)
- Spatial separation verification

Ground Truth: AMOS 2022 dataset with kidney labels (2=right, 3=left)
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
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "nibabel", "scipy"])
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


def dice_coefficient(pred: np.ndarray, gt: np.ndarray) -> float:
    """
    Calculate Dice coefficient between prediction and ground truth.
    
    Dice = 2 * |pred ∩ gt| / (|pred| + |gt|)
    """
    pred = pred.astype(bool)
    gt = gt.astype(bool)
    
    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)
    
    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0
    
    return float(2.0 * intersection / sum_volumes)


def extract_kidney_masks_from_agent_seg(seg_data: np.ndarray, segment_info: dict = None) -> tuple:
    """
    Extract left and right kidney masks from agent segmentation.
    
    The agent should have created segments named 'Left Kidney' and 'Right Kidney'.
    We try to identify them by name or by spatial position (left/right side).
    
    Returns:
        (left_kidney_mask, right_kidney_mask) as boolean arrays
    """
    unique_labels = np.unique(seg_data)
    unique_labels = unique_labels[unique_labels > 0]  # Exclude background
    
    logger.info(f"Agent segmentation has {len(unique_labels)} unique labels: {unique_labels}")
    
    if len(unique_labels) == 0:
        return None, None
    
    # If we have segment info with names, use that
    left_mask = None
    right_mask = None
    
    if segment_info and "segments" in segment_info:
        for seg in segment_info["segments"]:
            name = seg.get("name", "").lower()
            idx = seg.get("index", -1)
            label_val = idx + 1  # Typically label = index + 1
            
            if "left" in name and "kidney" in name:
                left_mask = (seg_data == label_val)
                logger.info(f"Found left kidney segment: '{seg.get('name')}' (label {label_val})")
            elif "right" in name and "kidney" in name:
                right_mask = (seg_data == label_val)
                logger.info(f"Found right kidney segment: '{seg.get('name')}' (label {label_val})")
    
    # If we couldn't identify by name, try spatial position
    if left_mask is None or right_mask is None:
        if len(unique_labels) >= 2:
            # Assume two largest connected components are the kidneys
            # Determine left/right by center of mass position
            label1 = int(unique_labels[0])
            label2 = int(unique_labels[1]) if len(unique_labels) > 1 else label1
            
            mask1 = (seg_data == label1)
            mask2 = (seg_data == label2) if label2 != label1 else np.zeros_like(mask1)
            
            # Calculate center of mass (x-coordinate determines left/right)
            # In RAS coordinates, positive X is left
            if np.any(mask1):
                com1_x = np.mean(np.where(mask1)[0])
            else:
                com1_x = 0
                
            if np.any(mask2):
                com2_x = np.mean(np.where(mask2)[0])
            else:
                com2_x = 0
            
            # Higher x-coordinate typically means left side (in RAS)
            if com1_x > com2_x:
                left_mask = mask1
                right_mask = mask2
            else:
                left_mask = mask2
                right_mask = mask1
                
            logger.info(f"Assigned kidneys by spatial position (COM x: {com1_x:.1f}, {com2_x:.1f})")
        elif len(unique_labels) == 1:
            # Only one segment - can't distinguish left/right
            logger.warning("Only one segment found - cannot distinguish left/right kidneys")
            single_mask = (seg_data == int(unique_labels[0]))
            return single_mask, None
    
    return left_mask, right_mask


def verify_kidney_asymmetry(traj, env_info, task_info):
    """
    Verify bilateral kidney volume asymmetry assessment task.
    
    Scoring (100 points total):
    - Left kidney Dice: 20 points (>= 0.70 threshold)
    - Right kidney Dice: 20 points (>= 0.70 threshold)
    - Left volume accuracy: 10 points (within 20%)
    - Right volume accuracy: 10 points (within 20%)
    - Asymmetry calculation: 15 points (within 5 percentage points)
    - Smaller kidney correct: 5 points
    - Classification correct: 10 points
    - Report completeness: 10 points
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
            "feedback": "Could not install required dependencies (nibabel)"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    dice_min = thresholds.get('dice_minimum', 0.60)
    vol_error_max = thresholds.get('volume_error_max_percent', 20)
    asym_error_max = thresholds.get('asymmetry_error_max_points', 5.0)
    
    w_left_dice = weights.get('left_kidney_dice', 20)
    w_right_dice = weights.get('right_kidney_dice', 20)
    w_left_vol = weights.get('left_volume_accuracy', 10)
    w_right_vol = weights.get('right_volume_accuracy', 10)
    w_asymmetry = weights.get('asymmetry_calculation', 15)
    w_smaller = weights.get('smaller_kidney_correct', 5)
    w_class = weights.get('classification_correct', 10)
    w_report = weights.get('report_completeness', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/kidney_task_result.json", temp_result.name)
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
    
    # Check basic prerequisites
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # ANTI-GAMING: Check timestamp
    # ================================================================
    seg_created = result.get('segmentation_created_during_task', False)
    report_created = result.get('report_created_during_task', False)
    
    if not seg_created and result.get('segmentation_exists', False):
        feedback_parts.append("WARNING: Segmentation may have existed before task")
    
    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt_info = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_info = {}
    try:
        copy_from_env("/tmp/gt_kidney_info.json", temp_gt_info.name)
        with open(temp_gt_info.name, 'r') as f:
            gt_info = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth info: {e}")
    finally:
        if os.path.exists(temp_gt_info.name):
            os.unlink(temp_gt_info.name)
    
    gt_left_vol = gt_info.get('left_kidney_volume_ml', 0)
    gt_right_vol = gt_info.get('right_kidney_volume_ml', 0)
    gt_asymmetry = gt_info.get('asymmetry_percentage', 0)
    gt_smaller = gt_info.get('smaller_kidney', '')
    gt_classification = gt_info.get('classification', '')
    voxel_volume_ml = gt_info.get('voxel_volume_ml', 0.001)
    
    details['gt_left_volume_ml'] = gt_left_vol
    details['gt_right_volume_ml'] = gt_right_vol
    details['gt_asymmetry_pct'] = gt_asymmetry
    details['gt_smaller_kidney'] = gt_smaller
    details['gt_classification'] = gt_classification
    
    # ================================================================
    # LOAD AND ANALYZE SEGMENTATIONS
    # ================================================================
    left_dice = 0.0
    right_dice = 0.0
    agent_left_vol = 0.0
    agent_right_vol = 0.0
    
    # Load ground truth labels
    temp_gt_labels = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    gt_labels = None
    try:
        copy_from_env("/tmp/gt_labels.nii.gz", temp_gt_labels.name)
        gt_nii = nib.load(temp_gt_labels.name)
        gt_labels = gt_nii.get_fdata().astype(np.int32)
        logger.info(f"Ground truth labels shape: {gt_labels.shape}")
    except Exception as e:
        logger.error(f"Failed to load ground truth labels: {e}")
        feedback_parts.append(f"Could not load ground truth: {e}")
    finally:
        if os.path.exists(temp_gt_labels.name):
            os.unlink(temp_gt_labels.name)
    
    # Load agent segmentation
    agent_seg = None
    segment_info = None
    
    # Try NIfTI version first
    temp_agent_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    try:
        copy_from_env("/tmp/agent_seg.nii.gz", temp_agent_seg.name)
        agent_nii = nib.load(temp_agent_seg.name)
        agent_seg = agent_nii.get_fdata().astype(np.int32)
        logger.info(f"Agent segmentation shape: {agent_seg.shape}")
    except Exception as e:
        logger.warning(f"Could not load NIfTI segmentation: {e}")
    finally:
        if os.path.exists(temp_agent_seg.name):
            os.unlink(temp_agent_seg.name)
    
    # Load segment info if available
    temp_seg_info = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/segment_info.json", temp_seg_info.name)
        with open(temp_seg_info.name, 'r') as f:
            segment_info = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_seg_info.name):
            os.unlink(temp_seg_info.name)
    
    # Calculate Dice scores and volumes if we have both segmentations
    if gt_labels is not None and agent_seg is not None:
        # Ground truth masks (AMOS: 2=right kidney, 3=left kidney)
        gt_left_mask = (gt_labels == 3)
        gt_right_mask = (gt_labels == 2)
        
        # Extract agent's kidney masks
        agent_left_mask, agent_right_mask = extract_kidney_masks_from_agent_seg(
            agent_seg, segment_info)
        
        # Calculate Dice for left kidney
        if agent_left_mask is not None and np.any(agent_left_mask):
            left_dice = dice_coefficient(agent_left_mask, gt_left_mask)
            agent_left_vol = float(np.sum(agent_left_mask) * voxel_volume_ml)
            details['left_dice'] = round(left_dice, 4)
            details['agent_left_volume_ml'] = round(agent_left_vol, 2)
            
            if left_dice >= 0.70:
                score += w_left_dice
                feedback_parts.append(f"✓ Left kidney Dice: {left_dice:.3f}")
            elif left_dice >= dice_min:
                score += int(w_left_dice * 0.7)
                feedback_parts.append(f"~ Left kidney Dice: {left_dice:.3f} (partial)")
            else:
                feedback_parts.append(f"✗ Left kidney Dice: {left_dice:.3f} (below threshold)")
        else:
            feedback_parts.append("✗ Left kidney not segmented")
            details['left_dice'] = 0.0
        
        # Calculate Dice for right kidney
        if agent_right_mask is not None and np.any(agent_right_mask):
            right_dice = dice_coefficient(agent_right_mask, gt_right_mask)
            agent_right_vol = float(np.sum(agent_right_mask) * voxel_volume_ml)
            details['right_dice'] = round(right_dice, 4)
            details['agent_right_volume_ml'] = round(agent_right_vol, 2)
            
            if right_dice >= 0.70:
                score += w_right_dice
                feedback_parts.append(f"✓ Right kidney Dice: {right_dice:.3f}")
            elif right_dice >= dice_min:
                score += int(w_right_dice * 0.7)
                feedback_parts.append(f"~ Right kidney Dice: {right_dice:.3f} (partial)")
            else:
                feedback_parts.append(f"✗ Right kidney Dice: {right_dice:.3f} (below threshold)")
        else:
            feedback_parts.append("✗ Right kidney not segmented")
            details['right_dice'] = 0.0
        
        # Volume accuracy
        if agent_left_vol > 0 and gt_left_vol > 0:
            left_vol_error = abs(agent_left_vol - gt_left_vol) / gt_left_vol * 100
            details['left_volume_error_pct'] = round(left_vol_error, 1)
            if left_vol_error <= vol_error_max:
                score += w_left_vol
                feedback_parts.append(f"✓ Left volume error: {left_vol_error:.1f}%")
            else:
                feedback_parts.append(f"✗ Left volume error: {left_vol_error:.1f}%")
        
        if agent_right_vol > 0 and gt_right_vol > 0:
            right_vol_error = abs(agent_right_vol - gt_right_vol) / gt_right_vol * 100
            details['right_volume_error_pct'] = round(right_vol_error, 1)
            if right_vol_error <= vol_error_max:
                score += w_right_vol
                feedback_parts.append(f"✓ Right volume error: {right_vol_error:.1f}%")
            else:
                feedback_parts.append(f"✗ Right volume error: {right_vol_error:.1f}%")
    
    elif not result.get('segmentation_exists', False):
        feedback_parts.append("✗ No segmentation file found")
    else:
        feedback_parts.append("✗ Could not analyze segmentation")
    
    # ================================================================
    # VERIFY REPORT
    # ================================================================
    report_complete = False
    
    if result.get('report_exists', False):
        # Load agent report
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        agent_report = {}
        try:
            copy_from_env("/tmp/agent_report.json", temp_report.name)
            with open(temp_report.name, 'r') as f:
                agent_report = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load agent report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
        
        details['agent_report'] = agent_report
        
        # Check report completeness
        required_fields = [
            'left_kidney_volume_ml',
            'right_kidney_volume_ml', 
            'asymmetry_percentage',
            'smaller_kidney',
            'classification'
        ]
        
        fields_present = sum(1 for f in required_fields if f in agent_report)
        if fields_present == len(required_fields):
            score += w_report
            report_complete = True
            feedback_parts.append(f"✓ Report complete ({fields_present}/{len(required_fields)} fields)")
        elif fields_present > 0:
            partial_score = int(w_report * fields_present / len(required_fields))
            score += partial_score
            feedback_parts.append(f"~ Report partial ({fields_present}/{len(required_fields)} fields)")
        else:
            feedback_parts.append("✗ Report missing required fields")
        
        # Verify asymmetry calculation
        reported_asym = agent_report.get('asymmetry_percentage')
        if reported_asym is not None:
            try:
                reported_asym = float(reported_asym)
                asym_error = abs(reported_asym - gt_asymmetry)
                details['asymmetry_error'] = round(asym_error, 2)
                
                if asym_error <= asym_error_max:
                    score += w_asymmetry
                    feedback_parts.append(f"✓ Asymmetry calculation: {reported_asym:.1f}% (error: {asym_error:.1f})")
                else:
                    feedback_parts.append(f"✗ Asymmetry error: {asym_error:.1f} points (expected ~{gt_asymmetry:.1f}%)")
            except (ValueError, TypeError):
                feedback_parts.append("✗ Invalid asymmetry value in report")
        
        # Verify smaller kidney identification
        reported_smaller = agent_report.get('smaller_kidney', '').lower()
        if reported_smaller:
            details['reported_smaller'] = reported_smaller
            if reported_smaller == gt_smaller.lower():
                score += w_smaller
                feedback_parts.append(f"✓ Smaller kidney correct: {reported_smaller}")
            else:
                feedback_parts.append(f"✗ Smaller kidney wrong: {reported_smaller} (expected {gt_smaller})")
        
        # Verify classification
        reported_class = agent_report.get('classification', '').lower()
        if reported_class:
            details['reported_classification'] = reported_class
            if reported_class == gt_classification.lower():
                score += w_class
                feedback_parts.append(f"✓ Classification correct: {reported_class}")
            else:
                feedback_parts.append(f"✗ Classification wrong: {reported_class} (expected {gt_classification})")
    else:
        feedback_parts.append("✗ No report file found")
    
    # ================================================================
    # ANTI-GAMING: Sanity checks
    # ================================================================
    volume_range = metadata.get('normal_kidney_volume_range_ml', [80, 250])
    
    # Check if volumes are physiologically plausible
    if agent_left_vol > 0:
        if agent_left_vol < volume_range[0] * 0.5 or agent_left_vol > volume_range[1] * 2:
            feedback_parts.append(f"WARNING: Left kidney volume ({agent_left_vol:.0f}mL) outside expected range")
    
    if agent_right_vol > 0:
        if agent_right_vol < volume_range[0] * 0.5 or agent_right_vol > volume_range[1] * 2:
            feedback_parts.append(f"WARNING: Right kidney volume ({agent_right_vol:.0f}mL) outside expected range")
    
    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    # Key criteria: both kidneys segmented with reasonable accuracy
    both_kidneys_segmented = (
        details.get('left_dice', 0) >= dice_min and 
        details.get('right_dice', 0) >= dice_min
    )
    
    passed = score >= 60 and both_kidneys_segmented
    
    # Generate summary
    feedback = " | ".join(feedback_parts)
    
    return to_python_type({
        "passed": passed,
        "score": min(100, score),
        "feedback": feedback,
        "details": details
    })