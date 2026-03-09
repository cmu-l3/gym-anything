#!/usr/bin/env python3
"""
Verifier for enhancement subtraction map task.

VERIFICATION STRATEGY:
1. Enhancement map created - valid NIfTI file exists (15 pts)
2. Subtraction correct - correlation with ground truth subtraction >= 0.9 (25 pts)
3. Enhancement mask created - valid binary mask exists (15 pts)
4. Mask captures enhancing tumor - Dice with GT enhancing region >= 0.3 (20 pts)
5. Report exists - text file with required content (10 pts)
6. Volume accuracy - reported volume within 50% of ground truth (10 pts)
7. Max intensity reported - reasonable value included (5 pts)

Anti-gaming checks:
- Files must be created during task (timestamp check)
- Enhancement map must differ from source volumes
- Enhancement map values must correlate with T1ce - T1

Pass threshold: 60 points with both Enhancement Map Created and Subtraction Correct
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


def dice_coefficient(pred: np.ndarray, gt: np.ndarray) -> float:
    """Calculate Dice coefficient between two binary masks."""
    pred = pred.astype(bool)
    gt = gt.astype(bool)
    
    intersection = np.sum(pred & gt)
    sum_volumes = np.sum(pred) + np.sum(gt)
    
    if sum_volumes == 0:
        return 1.0 if np.sum(pred) == 0 and np.sum(gt) == 0 else 0.0
    
    return float(2.0 * intersection / sum_volumes)


def correlation_coefficient(a: np.ndarray, b: np.ndarray) -> float:
    """Calculate Pearson correlation coefficient between two arrays."""
    a_flat = a.flatten().astype(np.float64)
    b_flat = b.flatten().astype(np.float64)
    
    # Remove NaN/Inf
    valid = np.isfinite(a_flat) & np.isfinite(b_flat)
    a_flat = a_flat[valid]
    b_flat = b_flat[valid]
    
    if len(a_flat) == 0:
        return 0.0
    
    # Calculate correlation
    a_mean = np.mean(a_flat)
    b_mean = np.mean(b_flat)
    
    a_centered = a_flat - a_mean
    b_centered = b_flat - b_mean
    
    numerator = np.sum(a_centered * b_centered)
    denominator = np.sqrt(np.sum(a_centered**2) * np.sum(b_centered**2))
    
    if denominator == 0:
        return 0.0
    
    return float(numerator / denominator)


def verify_enhancement_subtraction(traj, env_info, task_info):
    """
    Verify enhancement subtraction map task completion.
    
    Scoring (100 points total):
    - Enhancement map created: 15 points
    - Subtraction correct: 25 points
    - Enhancement mask created: 15 points
    - Mask captures enhancing tumor: 20 points
    - Report exists: 10 points
    - Volume accuracy: 10 points
    - Max intensity reported: 5 points
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
            "feedback": "Failed to load required dependencies (nibabel)"
        }
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    thresholds = metadata.get('passing_thresholds', {})
    weights = metadata.get('scoring_weights', {})
    
    correlation_min = thresholds.get('subtraction_correlation_min', 0.9)
    dice_min = thresholds.get('mask_dice_min', 0.3)
    volume_error_max = thresholds.get('volume_error_max_percent', 50)
    
    w_map_created = weights.get('enhancement_map_created', 15)
    w_subtraction = weights.get('subtraction_correct', 25)
    w_mask_created = weights.get('enhancement_mask_created', 15)
    w_mask_dice = weights.get('mask_captures_enhancing', 20)
    w_report = weights.get('report_exists', 10)
    w_volume = weights.get('volume_accuracy', 10)
    w_max_intensity = weights.get('max_intensity_reported', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/enhancement_task_result.json", temp_result.name)
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
    
    # Check basic requirements
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # LOAD GROUND TRUTH METRICS
    # ============================================================
    temp_gt_metrics = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_metrics = {}
    try:
        copy_from_env("/tmp/gt_enhancement_metrics.json", temp_gt_metrics.name)
        with open(temp_gt_metrics.name, 'r') as f:
            gt_metrics = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth metrics: {e}")
    finally:
        if os.path.exists(temp_gt_metrics.name):
            os.unlink(temp_gt_metrics.name)
    
    details['gt_metrics'] = gt_metrics
    
    # ============================================================
    # CRITERION 1: Enhancement map created (15 points)
    # ============================================================
    enhancement_map_exists = result.get('enhancement_map_exists', False)
    map_created_during_task = result.get('enhancement_map_created_during_task', False)
    map_size = result.get('enhancement_map_size_bytes', 0)
    
    if enhancement_map_exists and map_size > 10000:  # At least 10KB
        if map_created_during_task:
            score += w_map_created
            feedback_parts.append(f"✓ Enhancement map created ({map_size/1024:.1f}KB)")
        else:
            score += w_map_created * 0.5
            feedback_parts.append("△ Enhancement map exists but may not be newly created")
    else:
        feedback_parts.append("✗ Enhancement map not found or too small")
        # Early return since nothing else to check
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": to_python_type(details)
        }
    
    # ============================================================
    # CRITERION 2: Subtraction correct (25 points)
    # ============================================================
    subtraction_correct = False
    correlation = 0.0
    
    temp_agent_map = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    temp_gt_sub = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
    
    try:
        # Load agent's enhancement map
        copy_from_env("/tmp/agent_enhancement_map.nii.gz", temp_agent_map.name)
        agent_map_nii = nib.load(temp_agent_map.name)
        agent_map_data = agent_map_nii.get_fdata().astype(np.float32)
        
        # Load ground truth subtraction
        copy_from_env("/tmp/gt_subtraction.nii.gz", temp_gt_sub.name)
        gt_sub_nii = nib.load(temp_gt_sub.name)
        gt_sub_data = gt_sub_nii.get_fdata().astype(np.float32)
        
        # Check shapes match
        if agent_map_data.shape == gt_sub_data.shape:
            # Calculate correlation
            correlation = correlation_coefficient(agent_map_data, gt_sub_data)
            details['subtraction_correlation'] = correlation
            
            if correlation >= correlation_min:
                score += w_subtraction
                subtraction_correct = True
                feedback_parts.append(f"✓ Subtraction correct (correlation={correlation:.3f})")
            elif correlation >= 0.7:
                score += w_subtraction * 0.6
                feedback_parts.append(f"△ Subtraction partially correct (correlation={correlation:.3f})")
            elif correlation >= 0.5:
                score += w_subtraction * 0.3
                feedback_parts.append(f"△ Subtraction weakly correlated (correlation={correlation:.3f})")
            else:
                feedback_parts.append(f"✗ Subtraction incorrect (correlation={correlation:.3f})")
        else:
            feedback_parts.append(f"✗ Enhancement map shape mismatch: {agent_map_data.shape} vs {gt_sub_data.shape}")
            details['shape_mismatch'] = True
            
    except Exception as e:
        logger.warning(f"Failed to verify subtraction: {e}")
        feedback_parts.append(f"△ Could not verify subtraction: {str(e)[:50]}")
    finally:
        for f in [temp_agent_map.name, temp_gt_sub.name]:
            if os.path.exists(f):
                os.unlink(f)
    
    # ============================================================
    # CRITERION 3: Enhancement mask created (15 points)
    # ============================================================
    enhancement_mask_exists = result.get('enhancement_mask_exists', False)
    mask_created_during_task = result.get('enhancement_mask_created_during_task', False)
    mask_size = result.get('enhancement_mask_size_bytes', 0)
    
    if enhancement_mask_exists and mask_size > 1000:  # At least 1KB
        if mask_created_during_task:
            score += w_mask_created
            feedback_parts.append(f"✓ Enhancement mask created ({mask_size/1024:.1f}KB)")
        else:
            score += w_mask_created * 0.5
            feedback_parts.append("△ Enhancement mask exists but may not be newly created")
    else:
        feedback_parts.append("✗ Enhancement mask not found or too small")
    
    # ============================================================
    # CRITERION 4: Mask captures enhancing tumor (20 points)
    # ============================================================
    mask_dice = 0.0
    
    if enhancement_mask_exists:
        temp_agent_mask = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        temp_gt_seg = tempfile.NamedTemporaryFile(delete=False, suffix='.nii.gz')
        
        try:
            # Load agent's mask
            copy_from_env("/tmp/agent_enhancement_mask.nii.gz", temp_agent_mask.name)
            agent_mask_nii = nib.load(temp_agent_mask.name)
            agent_mask_data = agent_mask_nii.get_fdata()
            
            # Binarize (in case it's not already binary)
            agent_binary = (agent_mask_data > 0).astype(bool)
            
            # Load ground truth segmentation
            copy_from_env("/tmp/gt_segmentation.nii.gz", temp_gt_seg.name)
            gt_seg_nii = nib.load(temp_gt_seg.name)
            gt_seg_data = gt_seg_nii.get_fdata().astype(np.int32)
            
            # Enhancing tumor is label 4 in BraTS
            gt_enhancing = (gt_seg_data == 4)
            
            if agent_binary.shape == gt_enhancing.shape:
                mask_dice = dice_coefficient(agent_binary, gt_enhancing)
                details['mask_dice_vs_enhancing'] = mask_dice
                details['agent_mask_voxels'] = int(np.sum(agent_binary))
                details['gt_enhancing_voxels'] = int(np.sum(gt_enhancing))
                
                if mask_dice >= dice_min:
                    score += w_mask_dice
                    feedback_parts.append(f"✓ Mask captures enhancing region (Dice={mask_dice:.3f})")
                elif mask_dice >= 0.15:
                    score += w_mask_dice * 0.5
                    feedback_parts.append(f"△ Mask partially captures enhancement (Dice={mask_dice:.3f})")
                else:
                    feedback_parts.append(f"✗ Mask poorly matches enhancing region (Dice={mask_dice:.3f})")
            else:
                feedback_parts.append("✗ Mask shape mismatch with ground truth")
                
        except Exception as e:
            logger.warning(f"Failed to verify mask: {e}")
            feedback_parts.append(f"△ Could not verify mask: {str(e)[:50]}")
        finally:
            for f in [temp_agent_mask.name, temp_gt_seg.name]:
                if os.path.exists(f):
                    os.unlink(f)
    
    # ============================================================
    # CRITERION 5: Report exists (10 points)
    # ============================================================
    report_exists = result.get('report_exists', False)
    
    if report_exists:
        score += w_report
        feedback_parts.append("✓ Report file created")
    else:
        feedback_parts.append("✗ Report file not found")
    
    # ============================================================
    # CRITERION 6: Volume accuracy (10 points)
    # ============================================================
    reported_volume_str = result.get('reported_volume_ml', '')
    gt_volume = gt_metrics.get('enhancement_volume_ml', 0)
    
    if reported_volume_str and gt_volume > 0:
        try:
            reported_volume = float(reported_volume_str)
            volume_error_percent = abs(reported_volume - gt_volume) / gt_volume * 100
            details['reported_volume_ml'] = reported_volume
            details['gt_volume_ml'] = gt_volume
            details['volume_error_percent'] = volume_error_percent
            
            if volume_error_percent <= volume_error_max:
                score += w_volume
                feedback_parts.append(f"✓ Volume accurate ({reported_volume:.2f} vs {gt_volume:.2f} mL)")
            elif volume_error_percent <= volume_error_max * 1.5:
                score += w_volume * 0.5
                feedback_parts.append(f"△ Volume somewhat accurate ({volume_error_percent:.1f}% error)")
            else:
                feedback_parts.append(f"✗ Volume inaccurate ({volume_error_percent:.1f}% error)")
        except ValueError:
            feedback_parts.append("△ Could not parse reported volume")
    elif report_exists:
        feedback_parts.append("△ Volume not extracted from report")
    
    # ============================================================
    # CRITERION 7: Max intensity reported (5 points)
    # ============================================================
    reported_max = result.get('reported_max_intensity', '')
    gt_max = gt_metrics.get('max_enhancement_intensity', 0)
    
    if reported_max:
        try:
            reported_max_val = float(reported_max)
            # Check if it's a reasonable value (positive, not too different from GT)
            if reported_max_val > 0:
                if gt_max > 0:
                    error = abs(reported_max_val - gt_max) / gt_max * 100
                    if error <= 50:
                        score += w_max_intensity
                        feedback_parts.append(f"✓ Max intensity reported ({reported_max_val:.1f})")
                    else:
                        score += w_max_intensity * 0.5
                        feedback_parts.append(f"△ Max intensity reported but differs from expected")
                else:
                    score += w_max_intensity * 0.7
                    feedback_parts.append(f"✓ Max intensity reported ({reported_max_val:.1f})")
        except ValueError:
            pass
    
    # ============================================================
    # DETERMINE PASS/FAIL
    # ============================================================
    # Key criteria: enhancement map created AND subtraction correct
    key_criteria_met = enhancement_map_exists and subtraction_correct
    passed = score >= 60 and key_criteria_met
    
    # Format final feedback
    final_feedback = " | ".join(feedback_parts)
    if passed:
        final_feedback = f"PASSED ({score}/100): {final_feedback}"
    else:
        reason = ""
        if not enhancement_map_exists:
            reason = "Enhancement map not created"
        elif not subtraction_correct:
            reason = "Subtraction not correct"
        elif score < 60:
            reason = f"Score below threshold ({score}/60 required)"
        final_feedback = f"FAILED ({score}/100 - {reason}): {final_feedback}"
    
    return {
        "passed": passed,
        "score": to_python_type(score),
        "feedback": final_feedback,
        "details": to_python_type(details)
    }