#!/usr/bin/env python3
"""
Verifier for Create Hemispheric Mirror task in 3D Slicer.

VERIFICATION CRITERIA:
1. Output file exists (15 points) - mirrored volume saved to expected path
2. File has valid size (10 points) - >1MB indicates real volume data
3. Two volumes in scene (15 points) - evidence of cloning
4. Correct flip axis (25 points) - L-R axis was inverted (not A-P or S-I)
5. Voxel data correctly mirrored (20 points) - sampled voxels match expected positions
6. Comparison view setup (15 points) - VLM confirms both volumes visible

ANTI-GAMING CHECKS:
- File must be created AFTER task start time
- Cannot just copy original file - orientation must differ
- Random flips or rotations (not L-R) fail verification

Pass threshold: 70 points with correct_flip_axis criterion met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_hemispheric_mirror(traj, env_info, task_info):
    """
    Verify that a left-right mirrored volume was created correctly.

    Uses multiple independent signals to prevent gaming.
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
    expected_output_path = metadata.get('expected_output_path', 
        '/home/ga/Documents/SlicerData/Exports/MRHead_mirrored.nrrd')
    min_file_size_kb = metadata.get('min_file_size_kb', 1000)
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_file_exists', 15)
    w_file_size = weights.get('file_valid_size', 10)
    w_two_volumes = weights.get('two_volumes_in_scene', 15)
    w_flip_axis = weights.get('correct_flip_axis', 25)
    w_voxels = weights.get('voxel_data_mirrored', 20)
    w_comparison = weights.get('comparison_view_setup', 15)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/mirror_task_result.json", temp_result.name)
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

    # ============================================================
    # CRITERION 1: Output file exists (15 points)
    # ============================================================
    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if output_exists and file_created_during_task:
        score += w_output_exists
        feedback_parts.append("Output file created during task")
        details['output_file'] = "created"
    elif output_exists:
        # File exists but wasn't created during task - possible cheating
        score += w_output_exists // 3
        feedback_parts.append("Output file exists (pre-existing)")
        details['output_file'] = "pre-existing"
    else:
        feedback_parts.append("Output file NOT found")
        details['output_file'] = "missing"
        # Early exit - no output means task not completed
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 2: File has valid size (10 points)
    # ============================================================
    output_size_kb = result.get('output_size_bytes', 0) / 1024
    details['file_size_kb'] = output_size_kb
    
    if output_size_kb >= min_file_size_kb:
        score += w_file_size
        feedback_parts.append(f"File size OK ({output_size_kb:.0f}KB)")
    elif output_size_kb >= min_file_size_kb / 2:
        score += w_file_size // 2
        feedback_parts.append(f"File size small ({output_size_kb:.0f}KB)")
    else:
        feedback_parts.append(f"File too small ({output_size_kb:.0f}KB)")

    # ============================================================
    # CRITERION 3: Two volumes in scene (15 points)
    # Evidence that volume was cloned
    # ============================================================
    num_volumes = result.get('num_volumes_in_scene', 0)
    num_transforms = result.get('num_transforms_in_scene', 0)
    transform_visible = result.get('transform_window_visible', False)
    
    details['num_volumes'] = num_volumes
    details['num_transforms'] = num_transforms
    
    if num_volumes >= 2:
        score += w_two_volumes
        feedback_parts.append(f"Multiple volumes detected ({num_volumes})")
    elif transform_visible or num_transforms > 0:
        # Transform was used even if we couldn't count volumes
        score += w_two_volumes // 2
        feedback_parts.append("Transform module used")
    else:
        feedback_parts.append("No volume cloning evidence")

    # ============================================================
    # CRITERION 4: Correct flip axis - L-R (25 points)
    # This is the KEY criterion
    # ============================================================
    flip_detected = result.get('flip_detected', False)
    flip_axis = result.get('flip_axis', '')
    direction_inverted = result.get('direction_inverted', False)
    
    details['flip_detected'] = flip_detected
    details['flip_axis'] = flip_axis
    details['direction_inverted'] = direction_inverted
    
    correct_axis = flip_axis == "LR"
    
    if flip_detected and correct_axis:
        score += w_flip_axis
        feedback_parts.append("L-R flip correctly applied")
    elif flip_detected and flip_axis:
        # Flipped but wrong axis
        score += w_flip_axis // 4
        feedback_parts.append(f"Wrong flip axis ({flip_axis} instead of LR)")
    elif direction_inverted:
        # Direction matrix changed but couldn't verify axis
        score += w_flip_axis // 3
        feedback_parts.append("Transform applied (axis uncertain)")
    else:
        feedback_parts.append("No flip detected")

    # ============================================================
    # CRITERION 5: Voxel data correctly mirrored (20 points)
    # ============================================================
    voxels_match = result.get('voxels_match', False)
    details['voxels_match'] = voxels_match
    
    if voxels_match and correct_axis:
        score += w_voxels
        feedback_parts.append("Voxel data verified mirrored")
    elif voxels_match:
        score += w_voxels // 2
        feedback_parts.append("Voxel data flipped (axis uncertain)")
    elif flip_detected:
        # Flip detected via direction but voxels not verified
        score += w_voxels // 3
        feedback_parts.append("Voxels not fully verified")
    else:
        feedback_parts.append("Voxel data not mirrored")

    # ============================================================
    # CRITERION 6: VLM comparison view verification (15 points)
    # Uses trajectory frames to verify work was done
    # ============================================================
    vlm_score = 0
    vlm_feedback = "VLM not available"
    
    try:
        # Try to import VLM utilities
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            # Get trajectory frames for process verification
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory
            trajectory_frames = sample_trajectory_frames(traj, n=5)
            final_screenshot = get_final_screenshot(traj)
            
            if trajectory_frames or final_screenshot:
                images = trajectory_frames + ([final_screenshot] if final_screenshot else [])
                
                # Process verification prompt
                vlm_prompt = """You are verifying if an agent created a mirrored brain MRI volume in 3D Slicer.

The task was to:
1. Clone/duplicate a brain MRI volume
2. Apply a left-right flip transform
3. Set up a comparison view

Examine these screenshots (chronological order, earliest to latest) and assess:

1. DATA_MODULE_USED: Was the Data module accessed (shows node hierarchy)?
2. TRANSFORMS_MODULE_USED: Was the Transforms module accessed?
3. VOLUME_CLONED: Is there evidence of multiple volumes (2+ items in hierarchy)?
4. TRANSFORM_APPLIED: Was a transform applied to a volume?
5. COMPARISON_VISIBLE: In later frames, are both original and mirrored volumes visible?
6. BRAIN_VISIBLE: Is brain MRI data visible in the slice views?

Respond in JSON format:
{
    "data_module_used": true/false,
    "transforms_module_used": true/false,
    "volume_cloned": true/false,
    "transform_applied": true/false,
    "comparison_visible": true/false,
    "brain_visible": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=images)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    
                    # Score based on VLM observations
                    vlm_checks = [
                        parsed.get('data_module_used', False),
                        parsed.get('transforms_module_used', False),
                        parsed.get('volume_cloned', False),
                        parsed.get('transform_applied', False),
                        parsed.get('comparison_visible', False),
                        parsed.get('brain_visible', False),
                    ]
                    
                    checks_passed = sum(vlm_checks)
                    
                    if checks_passed >= 4:
                        vlm_score = w_comparison
                        vlm_feedback = f"VLM verified workflow ({checks_passed}/6 checks)"
                    elif checks_passed >= 2:
                        vlm_score = w_comparison // 2
                        vlm_feedback = f"VLM partial verification ({checks_passed}/6 checks)"
                    else:
                        vlm_feedback = f"VLM verification failed ({checks_passed}/6 checks)"
                    
                    details['vlm_parsed'] = parsed
                else:
                    vlm_feedback = "VLM query failed"
            else:
                vlm_feedback = "No trajectory frames available"
        else:
            # VLM not available - use heuristic based on other evidence
            slicer_running = result.get('slicer_was_running', False)
            if slicer_running and flip_detected:
                vlm_score = w_comparison // 2
                vlm_feedback = "Slicer running with flip (no VLM)"
            elif slicer_running:
                vlm_score = w_comparison // 3
                vlm_feedback = "Slicer running (no VLM)"
                
    except ImportError:
        # VLM utilities not available
        slicer_running = result.get('slicer_was_running', False)
        if slicer_running and flip_detected:
            vlm_score = w_comparison // 2
            vlm_feedback = "Slicer running with flip (VLM unavailable)"
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        vlm_feedback = f"VLM error: {str(e)[:50]}"

    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ============================================================
    # FINAL SCORING
    # ============================================================
    max_score = w_output_exists + w_file_size + w_two_volumes + w_flip_axis + w_voxels + w_comparison
    
    # Key criterion: correct flip axis must be met
    key_criterion_met = flip_detected and correct_axis
    
    # Pass threshold from metadata (default 70)
    pass_threshold = metadata.get('pass_threshold', 70)
    
    # Calculate pass condition
    passed = score >= pass_threshold and key_criterion_met
    
    # If close to passing but missing key criterion, adjust feedback
    if score >= pass_threshold and not key_criterion_met:
        feedback_parts.append("(failed key criterion: L-R flip)")
    
    feedback = " | ".join(feedback_parts)
    
    details['max_score'] = max_score
    details['pass_threshold'] = pass_threshold
    details['key_criterion_met'] = key_criterion_met

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }