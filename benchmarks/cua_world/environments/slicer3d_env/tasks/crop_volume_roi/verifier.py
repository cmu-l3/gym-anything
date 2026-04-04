#!/usr/bin/env python3
"""
Verifier for crop_volume_roi task.

VERIFICATION STRATEGY (Multi-Signal Anti-Gaming):

Programmatic checks (95 points):
1. Output file exists (25 points)
2. Volume is smaller than original (25 points) - key anti-gaming check
3. File saved correctly with valid size (20 points)
4. Brain preserved - not over-cropped (15 points)
5. Original volume preserved (10 points)

VLM checks (5 points):
6. Trajectory shows Crop Volume module usage (5 points)

Pass threshold: 70 points with BOTH "output exists" AND "volume is smaller" met
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_crop_volume_roi(traj, env_info, task_info):
    """
    Verify that the volume was cropped correctly.
    
    Uses multiple signals to prevent gaming:
    - File must exist
    - File must be created/modified during task (timestamp check)
    - Cropped dimensions must be smaller than original
    - Brain must still be preserved (not degenerate crop)
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
    expected_output = metadata.get('expected_output_path', '/home/ga/Documents/SlicerData/Exports/MRHead_cropped.nrrd')
    min_dimension = metadata.get('min_cropped_dimension', 50)
    min_file_size_kb = metadata.get('min_file_size_kb', 500)
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_exists', 25)
    w_volume_smaller = weights.get('volume_is_smaller', 25)
    w_file_saved = weights.get('file_saved_correctly', 20)
    w_brain_preserved = weights.get('brain_preserved', 15)
    w_original_preserved = weights.get('original_preserved', 10)
    w_vlm_evidence = weights.get('vlm_module_evidence', 5)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/crop_task_result.json", temp_result.name)
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
    key_criteria_met = True

    # ================================================================
    # CRITERION 1: Output file exists (25 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    
    if output_exists:
        score += w_output_exists
        feedback_parts.append("Output file exists")
        details['output_exists'] = True
    else:
        feedback_parts.append("OUTPUT FILE NOT FOUND")
        details['output_exists'] = False
        key_criteria_met = False
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Volume is smaller than original (25 points)
    # This is the KEY anti-gaming check - can't just copy the original
    # ================================================================
    dims_smaller = result.get('dimensions_smaller', False)
    original_dims = result.get('original_dimensions', [256, 256, 130])
    cropped_dims = result.get('cropped_dimensions', [])
    
    # Calculate dimension reduction
    dimension_reduction = []
    if original_dims and cropped_dims and len(original_dims) >= 3 and len(cropped_dims) >= 3:
        for i in range(3):
            if original_dims[i] > 0:
                reduction = (original_dims[i] - cropped_dims[i]) / original_dims[i] * 100
                dimension_reduction.append(round(reduction, 1))
            else:
                dimension_reduction.append(0)
    
    details['original_dimensions'] = original_dims
    details['cropped_dimensions'] = cropped_dims
    details['dimension_reduction_percent'] = dimension_reduction
    
    if dims_smaller:
        # Check if reduction is meaningful (at least 10% in at least one dimension)
        meaningful_reduction = any(r >= 10 for r in dimension_reduction) if dimension_reduction else False
        
        if meaningful_reduction:
            score += w_volume_smaller
            feedback_parts.append(f"Volume cropped (reduction: {dimension_reduction}%)")
        else:
            # Partial credit for any reduction
            score += int(w_volume_smaller * 0.6)
            feedback_parts.append(f"Volume slightly cropped (reduction: {dimension_reduction}%)")
    else:
        feedback_parts.append("VOLUME NOT SMALLER - may be same as original")
        key_criteria_met = False

    # ================================================================
    # CRITERION 3: File saved correctly (20 points)
    # Check timestamp and file size
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    file_modified = result.get('file_modified_during_task', False)
    output_size_bytes = result.get('output_size_bytes', 0)
    output_size_kb = output_size_bytes / 1024
    
    details['file_created_during_task'] = file_created
    details['file_modified_during_task'] = file_modified
    details['output_size_kb'] = round(output_size_kb, 1)
    
    # Timestamp check (anti-gaming)
    file_touched = file_created or file_modified
    
    # Size check
    size_valid = output_size_kb >= min_file_size_kb
    
    if file_touched and size_valid:
        score += w_file_saved
        feedback_parts.append(f"File saved correctly ({output_size_kb:.0f}KB)")
    elif file_touched:
        score += int(w_file_saved * 0.5)
        feedback_parts.append(f"File saved (small: {output_size_kb:.0f}KB)")
    elif size_valid:
        score += int(w_file_saved * 0.3)
        feedback_parts.append("File exists but may predate task")
    else:
        feedback_parts.append("File not properly saved")

    # ================================================================
    # CRITERION 4: Brain preserved - not over-cropped (15 points)
    # ================================================================
    brain_preserved = result.get('brain_preserved', False)
    cropped_voxels = result.get('cropped_voxel_count', 0)
    original_voxels = result.get('original_voxel_count', 1)
    
    # Check that we haven't removed too much (should keep at least 20% of voxels)
    if original_voxels > 0:
        voxel_retention = cropped_voxels / original_voxels * 100
    else:
        voxel_retention = 0
    
    details['voxel_retention_percent'] = round(voxel_retention, 1)
    
    if brain_preserved:
        # Check dimensions are reasonable
        min_dim_ok = all(d >= min_dimension for d in cropped_dims[:3]) if len(cropped_dims) >= 3 else False
        
        if min_dim_ok and voxel_retention >= 20:
            score += w_brain_preserved
            feedback_parts.append(f"Brain preserved ({voxel_retention:.0f}% voxels retained)")
        elif min_dim_ok:
            score += int(w_brain_preserved * 0.7)
            feedback_parts.append(f"Brain mostly preserved ({voxel_retention:.0f}% retained)")
        else:
            score += int(w_brain_preserved * 0.3)
            feedback_parts.append("Some cropping detected but dimensions low")
    else:
        if cropped_voxels > 0 and voxel_retention > 5:
            score += int(w_brain_preserved * 0.3)
            feedback_parts.append(f"Over-cropped ({voxel_retention:.0f}% voxels)")
        else:
            feedback_parts.append("Brain may be over-cropped")

    # ================================================================
    # CRITERION 5: Original volume preserved (10 points)
    # ================================================================
    original_preserved = result.get('original_preserved', False)
    num_volumes = result.get('num_volumes_in_scene', 0)
    cropped_in_scene = result.get('cropped_in_scene', False)
    
    details['original_preserved'] = original_preserved
    details['num_volumes_in_scene'] = num_volumes
    
    if original_preserved:
        score += w_original_preserved
        feedback_parts.append("Original volume preserved")
    elif num_volumes >= 2:
        # If we have 2+ volumes, likely both exist
        score += int(w_original_preserved * 0.8)
        feedback_parts.append(f"{num_volumes} volumes in scene")
    elif cropped_in_scene:
        score += int(w_original_preserved * 0.5)
        feedback_parts.append("Cropped volume in scene")
    else:
        feedback_parts.append("Original status unknown")

    # ================================================================
    # CRITERION 6: VLM trajectory verification (5 points)
    # Check if Crop Volume module was used
    # ================================================================
    try:
        # Import VLM utilities if available
        vlm_score = 0
        vlm_feedback = ""
        
        # Try to use trajectory-based VLM verification
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm and traj:
            # Sample trajectory frames
            try:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, n=4)
            except ImportError:
                frames = []
            
            if frames:
                vlm_prompt = """Analyze these screenshots from a 3D Slicer session.

The task was to use the Crop Volume module to crop a brain MRI.

Look for evidence of:
1. The Crop Volume module interface visible (module panel with ROI settings)
2. A red/colored ROI bounding box visible in the slice views
3. Volume cropping operation being performed

Respond in JSON format:
{
    "crop_module_visible": true/false,
    "roi_visible": true/false,
    "workflow_evidence": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
                try:
                    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                    if vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        if parsed.get('crop_module_visible') or parsed.get('roi_visible'):
                            vlm_score = w_vlm_evidence
                            vlm_feedback = "VLM confirms Crop Volume usage"
                        elif parsed.get('workflow_evidence'):
                            vlm_score = int(w_vlm_evidence * 0.5)
                            vlm_feedback = "VLM sees some evidence"
                        details['vlm_result'] = parsed
                except Exception as e:
                    logger.warning(f"VLM query failed: {e}")
                    vlm_feedback = "VLM unavailable"
            else:
                vlm_feedback = "No trajectory frames"
        else:
            # Check programmatic evidence instead
            crop_visible = result.get('crop_module_visible', False)
            if crop_visible:
                vlm_score = w_vlm_evidence
                vlm_feedback = "Crop module detected in windows"
        
        score += vlm_score
        if vlm_feedback:
            feedback_parts.append(vlm_feedback)
            
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        details['vlm_error'] = str(e)

    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Determine pass/fail
    # Must have: output exists AND volume is smaller (key criteria)
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary to feedback
    feedback += f" | Score: {score}/100"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }