#!/usr/bin/env python3
"""
Verifier for Correct AI Segmentation Errors task.

VERIFICATION STRATEGY:
1. Corrected file exists (15 points)
2. File was created during task - anti-gaming (10 points)
3. Dice improvement >= 0.02 (15 points)
4. Dice improvement >= 0.05 (15 points)
5. False positive reduced by >= 50% (15 points)
6. Under-segmentation fixed by >= 50% (15 points)
7. VLM: Segment Editor was used (10 points)
8. VLM: Multi-slice navigation evident (5 points)

Pass threshold: 60 points with corrected file exists AND dice improvement >= 0.02
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_correct_ai_segmentation(traj, env_info, task_info):
    """
    Verify that AI segmentation errors were corrected.
    
    Uses multi-criteria scoring with:
    - Programmatic verification of segmentation metrics
    - VLM verification of workflow execution
    - Timestamp-based anti-gaming checks
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get VLM utilities if available
    query_vlm = env_info.get('query_vlm')
    
    # Try to import trajectory utilities
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        has_vlm_utils = True
    except ImportError:
        has_vlm_utils = False
        logger.warning("VLM utilities not available")
    
    # Get task metadata
    metadata = task_info.get('metadata', {})
    min_dice_improvement = metadata.get('min_dice_improvement', 0.05)
    min_dice_improvement_partial = metadata.get('min_dice_improvement_partial', 0.02)
    fp_reduction_threshold = metadata.get('false_positive_reduction_threshold', 0.50)
    fn_recovery_threshold = metadata.get('under_segmentation_recovery_threshold', 0.50)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('corrected_file_exists', 15)
    w_file_modified = weights.get('file_modified_after_start', 10)
    w_dice_partial = weights.get('dice_improvement_partial', 15)
    w_dice_full = weights.get('dice_improvement_full', 15)
    w_fp_reduced = weights.get('false_positive_reduced', 15)
    w_fn_fixed = weights.get('under_segmentation_fixed', 15)
    w_segment_editor = weights.get('segment_editor_used', 10)
    w_navigation = weights.get('multi_slice_navigation', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/seg_correction_result.json", temp_result.name)
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
    
    # ================================================================
    # CRITERION 1: Corrected file exists (15 points)
    # ================================================================
    corrected_exists = result.get('corrected_file_exists', False)
    corrected_loaded = result.get('corrected_loaded', False)
    
    if corrected_exists and corrected_loaded:
        score += w_file_exists
        feedback_parts.append("Corrected segmentation saved")
        details['file_exists'] = True
    elif corrected_exists:
        score += w_file_exists * 0.5
        feedback_parts.append("File exists but may be invalid")
        details['file_exists'] = True
    else:
        feedback_parts.append("NO corrected segmentation saved")
        details['file_exists'] = False
        # Early exit - essential criterion not met
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: File created during task - anti-gaming (10 points)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    corrected_different_from_ai = result.get('corrected_different_from_ai', False)
    corrected_different_from_gt = result.get('corrected_different_from_gt', True)
    
    if file_created_during_task:
        score += w_file_modified
        feedback_parts.append("File created during task")
        details['created_during_task'] = True
    else:
        feedback_parts.append("File timestamp suspicious")
        details['created_during_task'] = False
    
    # Check for gaming - file should be different from both AI seg and GT
    if not corrected_different_from_ai:
        feedback_parts.append("WARNING: Output same as AI seg")
        score -= 10  # Penalty for no changes
        details['gaming_detected'] = True
    
    # ================================================================
    # CRITERION 3: Dice improvement >= 0.02 (15 points)
    # ================================================================
    dice_improvement = result.get('dice_improvement', 0)
    initial_dice = result.get('initial_dice', 0)
    final_dice = result.get('final_dice', 0)
    
    details['initial_dice'] = initial_dice
    details['final_dice'] = final_dice
    details['dice_improvement'] = dice_improvement
    
    if dice_improvement >= min_dice_improvement_partial:
        score += w_dice_partial
        feedback_parts.append(f"Dice improved +{dice_improvement:.3f}")
    elif dice_improvement > 0:
        score += w_dice_partial * 0.5
        feedback_parts.append(f"Slight Dice improvement +{dice_improvement:.3f}")
    else:
        feedback_parts.append(f"No Dice improvement ({dice_improvement:.3f})")
    
    # ================================================================
    # CRITERION 4: Dice improvement >= 0.05 (15 points)
    # ================================================================
    if dice_improvement >= min_dice_improvement:
        score += w_dice_full
        feedback_parts.append(f"Target improvement achieved")
        details['target_improvement_met'] = True
    else:
        details['target_improvement_met'] = False
    
    # ================================================================
    # CRITERION 5: False positive reduced (15 points)
    # ================================================================
    fp_reduction = result.get('false_positive_reduction', 0)
    initial_fp = result.get('initial_false_positives', 0)
    final_fp = result.get('final_false_positives', 0)
    
    details['initial_fp'] = initial_fp
    details['final_fp'] = final_fp
    details['fp_reduction_rate'] = fp_reduction
    
    if fp_reduction >= fp_reduction_threshold:
        score += w_fp_reduced
        feedback_parts.append(f"FP reduced {fp_reduction*100:.0f}%")
    elif fp_reduction > 0.2:
        score += w_fp_reduced * 0.5
        feedback_parts.append(f"FP partially reduced {fp_reduction*100:.0f}%")
    elif fp_reduction > 0:
        score += w_fp_reduced * 0.25
        feedback_parts.append(f"FP slightly reduced")
    else:
        feedback_parts.append("FP not reduced")
    
    # ================================================================
    # CRITERION 6: Under-segmentation fixed (15 points)
    # ================================================================
    fn_recovery = result.get('false_negative_recovery', 0)
    initial_fn = result.get('initial_false_negatives', 0)
    final_fn = result.get('final_false_negatives', 0)
    
    details['initial_fn'] = initial_fn
    details['final_fn'] = final_fn
    details['fn_recovery_rate'] = fn_recovery
    
    if fn_recovery >= fn_recovery_threshold:
        score += w_fn_fixed
        feedback_parts.append(f"Under-seg fixed {fn_recovery*100:.0f}%")
    elif fn_recovery > 0.2:
        score += w_fn_fixed * 0.5
        feedback_parts.append(f"Under-seg partially fixed {fn_recovery*100:.0f}%")
    elif fn_recovery > 0:
        score += w_fn_fixed * 0.25
        feedback_parts.append("Under-seg slightly fixed")
    else:
        feedback_parts.append("Under-seg not fixed")
    
    # ================================================================
    # CRITERION 7 & 8: VLM verification of workflow (15 points total)
    # ================================================================
    vlm_score = 0
    
    if query_vlm and has_vlm_utils and traj:
        try:
            # Sample trajectory frames for process verification
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                # Verify Segment Editor usage
                segment_editor_prompt = """Analyze these screenshots from a 3D Slicer medical image segmentation task.

The user should be editing a brain tumor segmentation using the Segment Editor module.

Look for evidence of:
1. SEGMENT_EDITOR_VISIBLE: Is the Segment Editor panel/module visible in any frame?
   Look for: "Segment Editor" in module dropdown, segmentation tools panel, 
   Paint/Erase/Scissors tool icons, segment list
   
2. EDITING_ACTIVITY: Is there evidence of active editing?
   Look for: Tool selections, brush strokes visible, segment colors changing,
   different editing states across frames

3. SLICE_NAVIGATION: Did the user navigate through different slices?
   Look for: Different slice views (different anatomy visible), 
   slice slider positions changing, different orientations

Respond in JSON:
{
    "segment_editor_visible": true/false,
    "editing_activity_detected": true/false,
    "slice_navigation_detected": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                all_frames = frames + ([final_frame] if final_frame else [])
                if all_frames:
                    vlm_result = query_vlm(
                        prompt=segment_editor_prompt,
                        images=all_frames[:6]  # Limit to 6 frames
                    )
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        
                        # Criterion 7: Segment Editor used (10 points)
                        if parsed.get('segment_editor_visible') or parsed.get('editing_activity_detected'):
                            vlm_score += w_segment_editor
                            feedback_parts.append("VLM: Segment Editor used")
                        elif parsed.get('confidence') == 'low':
                            vlm_score += w_segment_editor * 0.5
                            feedback_parts.append("VLM: Possible Segment Editor use")
                        
                        # Criterion 8: Multi-slice navigation (5 points)
                        if parsed.get('slice_navigation_detected'):
                            vlm_score += w_navigation
                            feedback_parts.append("VLM: Slice navigation detected")
                        
                        details['vlm_observations'] = parsed.get('observations', '')
                        details['vlm_confidence'] = parsed.get('confidence', 'unknown')
                    else:
                        logger.warning("VLM query failed")
                        # Give partial credit if we can't verify via VLM
                        vlm_score += (w_segment_editor + w_navigation) * 0.3
                        feedback_parts.append("VLM: Unable to verify (partial credit)")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            # Give partial credit if VLM fails
            vlm_score += (w_segment_editor + w_navigation) * 0.3
            feedback_parts.append("VLM: Verification error (partial credit)")
    else:
        # No VLM available - give credit based on programmatic evidence
        if corrected_different_from_ai and dice_improvement > 0:
            vlm_score += (w_segment_editor + w_navigation) * 0.5
            feedback_parts.append("VLM: N/A (inferred from results)")
    
    score += vlm_score
    details['vlm_score'] = vlm_score
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Ensure score is within bounds
    score = max(0, min(100, int(score)))
    
    # Determine pass/fail
    # Key criteria: file exists AND dice improvement >= partial threshold
    key_criteria_met = (
        corrected_exists and 
        corrected_loaded and 
        dice_improvement >= min_dice_improvement_partial
    )
    
    passed = score >= 60 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    summary = f"Score: {score}/100, Dice: {initial_dice:.3f}->{final_dice:.3f} (+{dice_improvement:.3f})"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | {feedback}",
        "details": details
    }