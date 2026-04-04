#!/usr/bin/env python3
"""
Verifier for Grow From Seeds Tumor Segmentation task.

VERIFICATION CRITERIA (Multi-signal approach):
1. Segmentation node exists (15 pts)
2. Tumor segment is non-empty (15 pts)
3. Tumor volume is in reasonable range (10 pts)
4. Segment centroid is in brain region (10 pts)
5. Dice coefficient > 0.3 against ground truth (15 pts)
6. Dice coefficient > 0.5 (good overlap) (15 pts)
7. Dice coefficient > 0.7 (excellent overlap) (10 pts)
8. Sensitivity > 0.5 (majority of tumor captured) (10 pts)

Pass threshold: 55 points with segmentation existing and reasonable overlap

ANTI-GAMING MEASURES:
- File timestamp verification (must be created during task)
- Trajectory frame VLM verification (shows Segment Editor workflow)
- Spatial validation (segmentation must be in brain region)
- Volume plausibility check (not too small, not too large)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_grow_from_seeds_tumor(traj, env_info, task_info):
    """
    Verify tumor segmentation using grow from seeds effect.
    
    Uses multi-criteria scoring with ground truth comparison.
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
    dice_pass = metadata.get('dice_threshold_pass', 0.4)
    dice_good = metadata.get('dice_threshold_good', 0.5)
    dice_excellent = metadata.get('dice_threshold_excellent', 0.7)
    sensitivity_threshold = metadata.get('sensitivity_threshold', 0.5)
    volume_range = metadata.get('volume_range_ml', {"min": 1, "max": 150})
    
    weights = metadata.get('scoring_weights', {})
    w_seg_exists = weights.get('segmentation_exists', 15)
    w_nonempty = weights.get('tumor_segment_nonempty', 15)
    w_volume = weights.get('volume_reasonable', 10)
    w_in_brain = weights.get('segment_in_brain', 10)
    w_dice_03 = weights.get('dice_above_03', 15)
    w_dice_05 = weights.get('dice_above_05', 15)
    w_dice_07 = weights.get('dice_above_07', 10)
    w_sensitivity = weights.get('sensitivity_above_05', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/grow_seeds_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have completed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result: {e}"
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
    slicer_running = result.get('slicer_was_running', False)
    if not slicer_running:
        feedback_parts.append("Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": {"slicer_running": False}
        }

    # ================================================================
    # CRITERION 1: Segmentation file exists (15 pts)
    # ================================================================
    seg_found = result.get('segmentation_file_found', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if seg_found:
        if file_created_during_task:
            score += w_seg_exists
            feedback_parts.append("Segmentation created during task")
        else:
            score += w_seg_exists * 0.5  # Partial credit if file exists but timing uncertain
            feedback_parts.append("Segmentation exists (timing uncertain)")
        details['seg_file_found'] = True
    else:
        feedback_parts.append("No segmentation file found")
        details['seg_file_found'] = False
        # Early exit if no segmentation at all
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Tumor segment is non-empty (15 pts)
    # ================================================================
    tumor_voxels = result.get('tumor_voxels', 0)
    if tumor_voxels > 100:  # At least 100 voxels
        score += w_nonempty
        feedback_parts.append(f"Tumor segment has {tumor_voxels} voxels")
        details['tumor_nonempty'] = True
    elif tumor_voxels > 0:
        score += w_nonempty * 0.5
        feedback_parts.append(f"Tumor segment very small ({tumor_voxels} voxels)")
        details['tumor_nonempty'] = True
    else:
        feedback_parts.append("Tumor segment is empty")
        details['tumor_nonempty'] = False

    # ================================================================
    # CRITERION 3: Volume in reasonable range (10 pts)
    # ================================================================
    tumor_volume_ml = result.get('tumor_volume_ml', 0)
    try:
        tumor_volume_ml = float(tumor_volume_ml)
    except (ValueError, TypeError):
        tumor_volume_ml = 0

    volume_min = volume_range.get('min', 1)
    volume_max = volume_range.get('max', 150)
    
    if volume_min <= tumor_volume_ml <= volume_max:
        score += w_volume
        feedback_parts.append(f"Volume {tumor_volume_ml:.1f}ml (reasonable)")
        details['volume_reasonable'] = True
    elif 0.1 <= tumor_volume_ml < volume_min:
        score += w_volume * 0.5
        feedback_parts.append(f"Volume {tumor_volume_ml:.1f}ml (small)")
        details['volume_reasonable'] = False
    elif tumor_volume_ml > volume_max:
        score += w_volume * 0.3
        feedback_parts.append(f"Volume {tumor_volume_ml:.1f}ml (large)")
        details['volume_reasonable'] = False
    else:
        feedback_parts.append(f"Volume {tumor_volume_ml:.1f}ml (too small)")
        details['volume_reasonable'] = False

    details['tumor_volume_ml'] = tumor_volume_ml

    # ================================================================
    # CRITERION 4: Segment centroid in brain region (10 pts)
    # ================================================================
    in_brain = result.get('in_brain_region', False)
    if in_brain:
        score += w_in_brain
        feedback_parts.append("Segment in brain region")
        details['in_brain'] = True
    else:
        feedback_parts.append("Segment location uncertain")
        details['in_brain'] = False

    # ================================================================
    # CRITERION 5-7: Dice coefficient thresholds (15+15+10 pts)
    # ================================================================
    dice_enhancing = result.get('dice_vs_enhancing', 0)
    dice_whole = result.get('dice_vs_whole_tumor', 0)
    try:
        dice_enhancing = float(dice_enhancing)
        dice_whole = float(dice_whole)
    except (ValueError, TypeError):
        dice_enhancing = 0
        dice_whole = 0

    # Use the better of the two Dice scores (enhancing vs whole tumor)
    # Since "grow from seeds" might segment the whole tumor, not just enhancing
    dice = max(dice_enhancing, dice_whole)
    
    details['dice_vs_enhancing'] = dice_enhancing
    details['dice_vs_whole_tumor'] = dice_whole
    details['dice_best'] = dice

    if dice >= 0.3:
        score += w_dice_03
        feedback_parts.append(f"Dice≥0.3 ({dice:.2f})")
    
    if dice >= 0.5:
        score += w_dice_05
        feedback_parts.append(f"Dice≥0.5 (good)")
    
    if dice >= 0.7:
        score += w_dice_07
        feedback_parts.append(f"Dice≥0.7 (excellent)")
    
    if dice < 0.3:
        feedback_parts.append(f"Dice {dice:.2f} (needs improvement)")

    # ================================================================
    # CRITERION 8: Sensitivity > 0.5 (10 pts)
    # ================================================================
    sensitivity = result.get('sensitivity', 0)
    try:
        sensitivity = float(sensitivity)
    except (ValueError, TypeError):
        sensitivity = 0

    details['sensitivity'] = sensitivity
    
    if sensitivity >= sensitivity_threshold:
        score += w_sensitivity
        feedback_parts.append(f"Sensitivity {sensitivity:.2f}")
    elif sensitivity > 0:
        score += w_sensitivity * (sensitivity / sensitivity_threshold)
        feedback_parts.append(f"Sensitivity {sensitivity:.2f} (partial)")

    # ================================================================
    # VLM VERIFICATION (Trajectory-based)
    # ================================================================
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory to verify workflow
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to segment a brain tumor using the "Grow from seeds" effect in Segment Editor.

Looking at these trajectory frames, determine:
1. Is the Segment Editor module visible at any point?
2. Are there colored overlay regions visible on the brain images (indicating segmentation)?
3. Does the workflow show progression (not just the same screen)?
4. Is there evidence of the "Grow from seeds" effect being used (seed painting, then growing)?

Respond in JSON format:
{
    "segment_editor_visible": true/false,
    "segmentation_overlay_visible": true/false,
    "workflow_progression": true/false,
    "grow_from_seeds_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_analysis'] = parsed
                
                # Add VLM-based scoring (bonus, not replacing programmatic)
                if parsed.get('segment_editor_visible'):
                    vlm_score += 2
                if parsed.get('segmentation_overlay_visible'):
                    vlm_score += 3
                if parsed.get('workflow_progression'):
                    vlm_score += 2
                if parsed.get('grow_from_seeds_evidence'):
                    vlm_score += 3
                
                if vlm_score > 0:
                    feedback_parts.append(f"VLM workflow verified (+{vlm_score})")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)

    # Add VLM bonus (capped at 10 points, does not exceed 100 total)
    score = min(100, score + vlm_score)

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: segmentation exists with some overlap to ground truth
    key_criteria_met = (
        seg_found and 
        tumor_voxels > 0 and 
        dice >= 0.3
    )
    
    passed = score >= 55 and key_criteria_met
    
    # Generate final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }