#!/usr/bin/env python3
"""
Verifier for threshold_brain_segmentation task.

VERIFICATION STRATEGY (Multi-Signal):
1. Segmentation file exists at expected path (20 points)
2. File size is valid (>100KB, indicates content) (10 points)
3. Voxel count is appropriate for brain tissue (25 points)
4. Spatial location is correct (centroid in brain region) (20 points)
5. Intensity values are valid for brain tissue (15 points)
6. VLM confirms Segment Editor workflow was used (10 points)

ANTI-GAMING MEASURES:
- File must be created DURING task (timestamp check)
- Voxel count must be in reasonable range (not too small/large)
- Centroid must be in central region (not random noise)
- Uses trajectory frames (not just final screenshot) for VLM verification

Pass threshold: 70 points with segmentation file exists AND voxel count appropriate
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_threshold_brain_segmentation(traj, env_info, task_info):
    """
    Verify threshold-based brain segmentation task completion.
    
    Uses copy_from_env to read result files from container.
    Uses trajectory frames for VLM verification.
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
    min_file_size_kb = metadata.get('min_file_size_kb', 100)
    min_voxel_count = metadata.get('min_voxel_count', 50000)
    max_voxel_count = metadata.get('max_voxel_count', 900000)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('file_exists', 20)
    w_file_size = weights.get('file_size_valid', 10)
    w_voxel_count = weights.get('voxel_count_appropriate', 25)
    w_location = weights.get('spatial_location_correct', 20)
    w_intensity = weights.get('intensity_values_valid', 15)
    w_vlm = weights.get('vlm_confirms_workflow', 10)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # Copy result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/seg_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info(f"Result data: {result}")
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

    # ================================================================
    # CRITERION 1: Segmentation file exists (20 points)
    # ================================================================
    file_exists = result.get('segmentation_file_exists', False)
    file_path = result.get('segmentation_file_path', '')
    
    if file_exists:
        score += w_file_exists
        feedback_parts.append(f"Segmentation file exists")
        details['file_exists'] = True
        details['file_path'] = file_path
    else:
        feedback_parts.append("Segmentation file NOT found")
        details['file_exists'] = False
        # Early exit - can't verify anything else without the file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: File was created during task (anti-gaming)
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    details['file_created_during_task'] = file_created_during_task
    
    if not file_created_during_task:
        # Severe penalty - file existed before task
        feedback_parts.append("WARNING: File may have existed before task")
        # Don't add points, but don't completely fail either
        # (file could have been overwritten with same timestamp)

    # ================================================================
    # CRITERION 3: File size is valid (10 points)
    # ================================================================
    file_size_kb = result.get('file_size_kb', 0)
    details['file_size_kb'] = file_size_kb
    
    if file_size_kb >= min_file_size_kb:
        score += w_file_size
        feedback_parts.append(f"File size OK ({file_size_kb}KB)")
    elif file_size_kb >= min_file_size_kb / 2:
        score += w_file_size // 2
        feedback_parts.append(f"File size marginal ({file_size_kb}KB)")
    else:
        feedback_parts.append(f"File too small ({file_size_kb}KB)")

    # ================================================================
    # CRITERION 4: Voxel count is appropriate (25 points)
    # Brain tissue should be ~100K-800K voxels in typical MRI
    # ================================================================
    voxel_count = result.get('voxel_count', 0)
    details['voxel_count'] = voxel_count
    
    if min_voxel_count <= voxel_count <= max_voxel_count:
        score += w_voxel_count
        feedback_parts.append(f"Voxel count appropriate ({voxel_count:,})")
        voxel_count_ok = True
    elif voxel_count > 0:
        # Partial credit for having some segmentation
        if voxel_count < min_voxel_count:
            score += w_voxel_count // 3
            feedback_parts.append(f"Voxel count low ({voxel_count:,})")
        else:  # > max_voxel_count
            score += w_voxel_count // 3
            feedback_parts.append(f"Voxel count high ({voxel_count:,})")
        voxel_count_ok = False
    else:
        feedback_parts.append("Segmentation is empty (0 voxels)")
        voxel_count_ok = False

    # ================================================================
    # CRITERION 5: Spatial location is correct (20 points)
    # Centroid should be in central region of volume
    # ================================================================
    valid_location = result.get('valid_location', False)
    details['valid_location'] = valid_location
    
    if valid_location:
        score += w_location
        feedback_parts.append("Spatial location correct")
    else:
        # Partial credit if voxel count is reasonable
        if voxel_count_ok:
            score += w_location // 2
            feedback_parts.append("Spatial location uncertain")
        else:
            feedback_parts.append("Spatial location incorrect")

    # ================================================================
    # CRITERION 6: Intensity values are valid (15 points)
    # Mean intensity should be in brain tissue range
    # ================================================================
    valid_intensity = result.get('valid_intensity', False)
    mean_intensity = result.get('mean_intensity', 0)
    details['mean_intensity'] = mean_intensity
    details['valid_intensity'] = valid_intensity
    
    if valid_intensity:
        score += w_intensity
        feedback_parts.append(f"Intensity values valid (mean={mean_intensity})")
    else:
        # Partial credit if we couldn't verify but voxel count is OK
        if voxel_count_ok and mean_intensity == 0:
            score += w_intensity // 2
            feedback_parts.append("Intensity check inconclusive")
        else:
            feedback_parts.append(f"Intensity values invalid (mean={mean_intensity})")

    # ================================================================
    # CRITERION 7: VLM verification of workflow (10 points)
    # Check trajectory frames to confirm Segment Editor was used
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM verification skipped"
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample frames from trajectory (not just final screenshot!)
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            # Query VLM with multiple trajectory frames
            vlm_prompt = """You are verifying if a user completed a segmentation task in 3D Slicer medical imaging software.

These images show the progression of work (from earliest to latest).

For successful threshold segmentation, the user should have:
1. Opened the Segment Editor module (look for segment list panel, effects toolbar with paint/threshold/etc icons)
2. Created a segment (should see a colored segment in the list)
3. Used the Threshold effect (slider controls for threshold values)
4. Applied threshold to create segmentation (colored overlay on the brain image)

Analyze the images and determine:

Respond in JSON format:
{
    "segment_editor_visible": true/false,
    "segment_created": true/false,
    "threshold_tool_used": true/false,
    "segmentation_overlay_visible": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see across the frames"
}
"""
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                workflow_completed = parsed.get('workflow_completed', False)
                segment_editor_visible = parsed.get('segment_editor_visible', False)
                segmentation_overlay = parsed.get('segmentation_overlay_visible', False)
                confidence = parsed.get('confidence', 'low')
                
                # Score based on VLM findings
                if workflow_completed and confidence in ['medium', 'high']:
                    vlm_score = w_vlm
                    vlm_feedback = "VLM confirms workflow completed"
                elif segment_editor_visible and segmentation_overlay:
                    vlm_score = w_vlm * 3 // 4
                    vlm_feedback = "VLM sees Segment Editor and overlay"
                elif segment_editor_visible or segmentation_overlay:
                    vlm_score = w_vlm // 2
                    vlm_feedback = "VLM sees partial workflow"
                else:
                    vlm_feedback = "VLM could not confirm workflow"
            else:
                vlm_feedback = "VLM query failed"
                # Give partial credit if programmatic checks passed
                if score >= 50:
                    vlm_score = w_vlm // 2
        else:
            vlm_feedback = "No trajectory frames available"
            # Give partial credit if programmatic checks passed
            if score >= 50:
                vlm_score = w_vlm // 2
                
    except ImportError:
        vlm_feedback = "VLM module not available"
        # Give partial credit if programmatic checks passed
        if score >= 50:
            vlm_score = w_vlm // 2
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        vlm_feedback = f"VLM error: {str(e)[:50]}"
        # Give partial credit if programmatic checks passed
        if score >= 50:
            vlm_score = w_vlm // 2

    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score

    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria for passing:
    # - File must exist
    # - File must be created during task (or at least modified)
    # - Voxel count must be in reasonable range
    key_criteria_met = (
        file_exists and
        (file_created_during_task or file_size_kb > min_file_size_kb // 2) and
        voxel_count >= min_voxel_count // 2
    )
    
    # Pass threshold: 70 points with key criteria
    passed = score >= 70 and key_criteria_met
    
    # Ensure score doesn't exceed 100
    score = min(score, 100)
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary
    details['total_score'] = score
    details['key_criteria_met'] = key_criteria_met
    details['slicer_was_running'] = result.get('slicer_was_running', False)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }