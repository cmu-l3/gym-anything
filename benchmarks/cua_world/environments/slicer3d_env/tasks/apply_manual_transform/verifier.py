#!/usr/bin/env python3
"""
Verifier for Apply Manual Transform task in 3D Slicer.

VERIFICATION STRATEGY:
Multi-criteria scoring with anti-gaming measures.

CRITERIA:
1. Transform Node Exists (25 pts) - A LinearTransform exists in the scene
2. Transform Non-Identity (15 pts) - Transform has non-zero rotation/translation
3. Rotation Approximately 15° (25 pts) - Dominant rotation is within 10-20° range
4. Correct Axis (10 pts) - Primary rotation is around S (superior-inferior) axis
5. Volume Transformed (20 pts) - MRHead volume has the transform as parent
6. VLM Confirmation (5 pts) - Visual verification of rotated brain

Anti-gaming measures:
- Check transform was created during task (not pre-existing)
- Verify rotation is non-trivial
- Check volume association exists

Pass threshold: 70 points with "Transform Node Exists" AND "Volume Transformed"
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_apply_manual_transform(traj, env_info, task_info):
    """
    Verify that a rotation transform was correctly applied to the MRHead volume.
    
    Uses multi-criteria scoring with multiple independent verification signals.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_rotation = metadata.get('expected_rotation_degrees', 15)
    rotation_tolerance = metadata.get('rotation_tolerance_degrees', 5)
    
    weights = metadata.get('scoring_weights', {})
    w_transform_exists = weights.get('transform_exists', 25)
    w_non_identity = weights.get('transform_non_identity', 15)
    w_rotation_correct = weights.get('rotation_approximately_correct', 25)
    w_correct_axis = weights.get('correct_axis', 10)
    w_volume_transformed = weights.get('volume_transformed', 20)
    w_vlm = weights.get('vlm_confirmation', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/transform_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - export may have failed"
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
            "feedback": "Slicer was not running - cannot verify task"
        }
    
    # ================================================================
    # CRITERION 1: Transform Node Exists (25 points)
    # ================================================================
    transform_exists = result.get('transform_exists', False)
    transform_count = result.get('transform_count', 0)
    transform_name = result.get('transform_name', '')
    
    details['transform_exists'] = transform_exists
    details['transform_count'] = transform_count
    details['transform_name'] = transform_name
    
    if transform_exists and transform_count > 0:
        score += w_transform_exists
        feedback_parts.append(f"Transform exists: '{transform_name}'")
    else:
        feedback_parts.append("No transform found in scene")
        # Early exit - fundamental requirement not met
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Transform Non-Identity (15 points)
    # Anti-gaming: Ensure transform actually does something
    # ================================================================
    is_identity = result.get('transform_is_identity', True)
    details['is_identity'] = is_identity
    
    if not is_identity:
        score += w_non_identity
        feedback_parts.append("Transform is non-identity")
    else:
        feedback_parts.append("Transform is identity (no change)")
    
    # ================================================================
    # CRITERION 3: Rotation Approximately Correct (25 points)
    # Check if dominant rotation is in expected range (10-20 degrees)
    # ================================================================
    dominant_rotation = result.get('dominant_rotation_degrees', 0)
    rotation_x = result.get('rotation_degrees_x', 0)
    rotation_y = result.get('rotation_degrees_y', 0)
    rotation_z = result.get('rotation_degrees_z', 0)
    
    details['rotation_x'] = rotation_x
    details['rotation_y'] = rotation_y
    details['rotation_z'] = rotation_z
    details['dominant_rotation'] = dominant_rotation
    
    min_rotation = expected_rotation - rotation_tolerance
    max_rotation = expected_rotation + rotation_tolerance
    
    # Check if any rotation is in expected range
    rotation_in_range = False
    best_rotation = 0
    
    for rot, axis in [(abs(rotation_x), 'X'), (abs(rotation_y), 'Y'), (abs(rotation_z), 'Z')]:
        if min_rotation <= rot <= max_rotation:
            rotation_in_range = True
            best_rotation = rot
            break
        # Also check the signed value
        if min_rotation <= abs(rot) <= max_rotation:
            best_rotation = max(best_rotation, abs(rot))
    
    # Also accept if dominant rotation is close
    if min_rotation <= dominant_rotation <= max_rotation:
        rotation_in_range = True
        best_rotation = dominant_rotation
    
    # Be more lenient - accept 5-25 degree range
    lenient_min = 5
    lenient_max = 30
    lenient_in_range = lenient_min <= dominant_rotation <= lenient_max
    
    if rotation_in_range:
        score += w_rotation_correct
        feedback_parts.append(f"Rotation correct: {best_rotation:.1f}° (expected ~{expected_rotation}°)")
    elif lenient_in_range:
        # Partial credit for rotation in lenient range
        partial_score = int(w_rotation_correct * 0.6)
        score += partial_score
        feedback_parts.append(f"Rotation partially correct: {dominant_rotation:.1f}° (expected ~{expected_rotation}°)")
    elif dominant_rotation > 2:  # Some rotation applied
        partial_score = int(w_rotation_correct * 0.3)
        score += partial_score
        feedback_parts.append(f"Some rotation applied: {dominant_rotation:.1f}°")
    else:
        feedback_parts.append(f"Rotation too small: {dominant_rotation:.1f}°")
    
    # ================================================================
    # CRITERION 4: Correct Axis (10 points)
    # Rotation should be around S (superior-inferior) axis, which is Z in RAS
    # ================================================================
    rotation_axis = result.get('rotation_axis', '')
    details['rotation_axis'] = rotation_axis
    
    # IS = Inferior-Superior = Z axis in RAS = S axis
    if rotation_axis == 'IS':
        score += w_correct_axis
        feedback_parts.append("Correct axis: IS (S)")
    elif rotation_axis in ['LR', 'PA']:
        # Different axis - partial credit if rotation is significant
        if dominant_rotation >= min_rotation:
            partial_score = int(w_correct_axis * 0.5)
            score += partial_score
            feedback_parts.append(f"Different axis: {rotation_axis} (expected IS/S)")
        else:
            feedback_parts.append(f"Wrong axis: {rotation_axis}")
    else:
        feedback_parts.append("Unable to determine rotation axis")
    
    # ================================================================
    # CRITERION 5: Volume Transformed (20 points)
    # MRHead must have the transform applied
    # ================================================================
    volume_transformed = result.get('volume_transformed', False)
    volume_name = result.get('volume_name', '')
    parent_transform = result.get('parent_transform_name', '')
    
    details['volume_transformed'] = volume_transformed
    details['volume_name'] = volume_name
    details['parent_transform'] = parent_transform
    
    if volume_transformed:
        score += w_volume_transformed
        feedback_parts.append(f"Volume '{volume_name}' transformed")
    else:
        # Check if volume is at least loaded
        volume_loaded = result.get('volume_loaded', False)
        if volume_loaded:
            feedback_parts.append(f"Volume loaded but not transformed")
        else:
            feedback_parts.append("Volume not found or transformed")
    
    # ================================================================
    # CRITERION 6: VLM Confirmation (5 points)
    # Use trajectory frames to verify visual change
    # ================================================================
    vlm_score = 0
    
    try:
        # Try to import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames for process verification
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        
        if frames or final:
            # Query VLM to verify rotation is visible
            vlm_prompt = """You are verifying a medical imaging task in 3D Slicer.

The task was to apply a rotation transform to a brain MRI volume.

Looking at these screenshots from the session:
1. Is 3D Slicer visible with brain MRI data?
2. Can you see the Transforms module or transform-related controls?
3. Does the brain in the slice views appear rotated compared to a standard orientation?

Respond in JSON format:
{
    "slicer_visible": true/false,
    "brain_data_visible": true/false,
    "transforms_module_used": true/false,
    "brain_appears_rotated": true/false,
    "confidence": "low"/"medium"/"high"
}"""
            
            images = (frames if frames else []) + ([final] if final else [])
            if images:
                vlm_result = query_vlm(prompt=vlm_prompt, images=images[:4])
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    if parsed.get('slicer_visible') and parsed.get('brain_data_visible'):
                        vlm_score = w_vlm
                        if parsed.get('brain_appears_rotated'):
                            feedback_parts.append("VLM: Rotation visible")
                        else:
                            feedback_parts.append("VLM: Brain visible, rotation unclear")
                    else:
                        feedback_parts.append("VLM: Unable to verify")
    except ImportError:
        logger.info("VLM utilities not available - skipping visual verification")
        details['vlm_available'] = False
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)
    
    score += vlm_score
    
    # ================================================================
    # ANTI-GAMING CHECK
    # Verify transform was created during the task
    # ================================================================
    transform_created_during_task = result.get('transform_created_during_task', False)
    initial_count = result.get('initial_transform_count', 0)
    final_count = result.get('final_transform_count', 0)
    
    details['transform_created_during_task'] = transform_created_during_task
    details['initial_transform_count'] = initial_count
    details['final_transform_count'] = final_count
    
    if not transform_created_during_task and transform_exists:
        # Transform existed before task - suspicious
        logger.warning("Transform may have existed before task started")
        details['anti_gaming_warning'] = "Transform may be pre-existing"
    
    # ================================================================
    # FINAL SCORE CALCULATION
    # ================================================================
    max_score = w_transform_exists + w_non_identity + w_rotation_correct + w_correct_axis + w_volume_transformed + w_vlm
    
    # Key criteria for passing
    key_criteria_met = transform_exists and volume_transformed
    
    # Pass threshold: 70% with key criteria
    passed = (score >= 70) and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }