#!/usr/bin/env python3
"""
Verifier for create_masked_brain_volume task.

VERIFICATION STRATEGY:
1. Output file exists at expected location (25 points)
2. Output has correct dimensions matching input (15 points)
3. Effective masking - >30% voxels are near-zero (25 points)
4. Brain signal preserved - central region has data (20 points)
5. File was created during task execution (10 points)
6. Visual/trajectory confirmation (5 points)

Pass threshold: 70 points with output_exists AND effective_masking

Uses copy_from_env (NOT exec_in_env) to read container files.
Uses trajectory frames for VLM verification.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_masked_brain_volume(traj, env_info, task_info):
    """
    Verify that a skull-stripped brain volume was created successfully.
    
    Multi-criteria verification:
    1. File existence and location
    2. Volume dimensions
    3. Masking effectiveness (% of voxels zeroed)
    4. Brain tissue preservation
    5. Anti-gaming timestamp checks
    6. Optional VLM trajectory verification
    """
    
    # Get copy function from env_info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - framework error"
        }
    
    # Get task metadata for expected values
    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', 
        '/home/ga/Documents/SlicerData/Exports/MRHead_brain_only.nrrd')
    expected_dimensions = metadata.get('expected_dimensions', [256, 256, 130])
    min_near_zero_pct = metadata.get('min_near_zero_percentage', 30)
    
    weights = metadata.get('scoring_weights', {})
    w_output_exists = weights.get('output_file_exists', 25)
    w_dimensions = weights.get('correct_dimensions', 15)
    w_masking = weights.get('effective_masking', 25)
    w_brain_preserved = weights.get('brain_preserved', 20)
    w_timestamp = weights.get('file_created_during_task', 10)
    w_visual = weights.get('visual_confirmation', 5)
    
    # Initialize scoring
    score = 0
    max_score = 100
    feedback_parts = []
    details = {}
    
    # ================================================================
    # STEP 1: Copy and parse result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info("Successfully loaded task result JSON")
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Task result file not found - export script may have failed",
            "details": {"error": "result_file_not_found"}
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Invalid JSON in result file: {e}",
            "details": {"error": "json_decode_error"}
        }
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}",
            "details": {"error": str(e)}
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
    
    details['result_data'] = result
    
    # ================================================================
    # CRITERION 1: Output file exists (25 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    output_path = result.get('output_path', '')
    
    if output_exists and output_size > 100000:  # At least 100KB
        score += w_output_exists
        feedback_parts.append(f"✓ Output file exists ({output_size // 1024}KB)")
        details['output_exists'] = True
        details['output_size_kb'] = output_size // 1024
    elif output_exists:
        # Partial credit for small file
        score += w_output_exists // 2
        feedback_parts.append(f"△ Output file exists but small ({output_size // 1024}KB)")
        details['output_exists'] = True
        details['output_size_kb'] = output_size // 1024
    else:
        feedback_parts.append("✗ Output file NOT found")
        details['output_exists'] = False
        # Cannot continue verification without output file
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Correct dimensions (15 points)
    # ================================================================
    analysis = result.get('volume_analysis', {})
    
    if isinstance(analysis, str):
        try:
            analysis = json.loads(analysis)
        except:
            analysis = {}
    
    shape = analysis.get('shape', [])
    shape_matches = analysis.get('shape_matches', False)
    
    if shape_matches:
        score += w_dimensions
        feedback_parts.append(f"✓ Dimensions match expected ({shape})")
        details['dimensions_match'] = True
    elif shape and len(shape) == 3:
        # Check if dimensions are close enough (within 10%)
        expected_sorted = sorted(expected_dimensions)
        shape_sorted = sorted(shape)
        dims_close = all(
            0.9 * e <= s <= 1.1 * e 
            for e, s in zip(expected_sorted, shape_sorted)
        )
        if dims_close:
            score += w_dimensions * 0.7
            feedback_parts.append(f"△ Dimensions close to expected ({shape})")
            details['dimensions_match'] = 'partial'
        else:
            feedback_parts.append(f"✗ Dimensions mismatch ({shape} vs {expected_dimensions})")
            details['dimensions_match'] = False
    else:
        feedback_parts.append("✗ Could not determine dimensions")
        details['dimensions_match'] = False
    
    details['output_shape'] = shape
    
    # ================================================================
    # CRITERION 3: Effective masking (25 points)
    # ================================================================
    near_zero_pct = analysis.get('near_zero_percentage', 0)
    effective_masking = analysis.get('effective_masking', False)
    
    # Also check if masking increased zeros compared to input
    input_comparison = analysis.get('input_comparison', {})
    masking_increased_zeros = input_comparison.get('masking_increased_zeros', False)
    
    if effective_masking or near_zero_pct >= min_near_zero_pct:
        score += w_masking
        feedback_parts.append(f"✓ Effective masking ({near_zero_pct:.1f}% near-zero)")
        details['effective_masking'] = True
    elif near_zero_pct >= min_near_zero_pct * 0.7:
        # Partial credit
        score += w_masking * 0.6
        feedback_parts.append(f"△ Partial masking ({near_zero_pct:.1f}% near-zero)")
        details['effective_masking'] = 'partial'
    elif masking_increased_zeros:
        # Some evidence of masking
        score += w_masking * 0.4
        feedback_parts.append(f"△ Some masking detected ({near_zero_pct:.1f}% near-zero)")
        details['effective_masking'] = 'partial'
    else:
        feedback_parts.append(f"✗ Masking not effective ({near_zero_pct:.1f}% near-zero, need >{min_near_zero_pct}%)")
        details['effective_masking'] = False
    
    details['near_zero_percentage'] = near_zero_pct
    
    # ================================================================
    # CRITERION 4: Brain signal preserved (20 points)
    # ================================================================
    brain_preserved = analysis.get('brain_preserved', False)
    center_mean = analysis.get('center_mean', 0)
    center_nonzero_pct = analysis.get('center_nonzero_pct', 0)
    
    if brain_preserved:
        score += w_brain_preserved
        feedback_parts.append(f"✓ Brain signal preserved (center mean: {center_mean:.1f})")
        details['brain_preserved'] = True
    elif center_mean > 10 and center_nonzero_pct > 30:
        # Partial preservation
        score += w_brain_preserved * 0.6
        feedback_parts.append(f"△ Partial brain signal (center mean: {center_mean:.1f})")
        details['brain_preserved'] = 'partial'
    elif center_mean > 5:
        # Minimal preservation
        score += w_brain_preserved * 0.3
        feedback_parts.append(f"△ Weak brain signal (center mean: {center_mean:.1f})")
        details['brain_preserved'] = 'weak'
    else:
        feedback_parts.append(f"✗ Brain signal may be lost (center mean: {center_mean:.1f})")
        details['brain_preserved'] = False
    
    details['center_mean'] = center_mean
    details['center_nonzero_pct'] = center_nonzero_pct
    
    # ================================================================
    # CRITERION 5: File created during task (10 points) - Anti-gaming
    # ================================================================
    file_created_during_task = result.get('file_created_during_task', False)
    task_duration = result.get('task_duration_seconds', 0)
    
    if file_created_during_task:
        score += w_timestamp
        feedback_parts.append("✓ File created during task")
        details['created_during_task'] = True
    else:
        # Check timestamps manually
        task_start = result.get('task_start', 0)
        output_mtime = result.get('output_modified_timestamp', 0)
        
        if output_mtime > task_start:
            score += w_timestamp
            feedback_parts.append("✓ File modified during task")
            details['created_during_task'] = True
        else:
            feedback_parts.append("✗ File may have existed before task")
            details['created_during_task'] = False
    
    details['task_duration_seconds'] = task_duration
    
    # ================================================================
    # CRITERION 6: Visual/Trajectory confirmation (5 points)
    # ================================================================
    slicer_was_running = result.get('slicer_was_running', False)
    segmentation_found = result.get('segmentation_found', False)
    
    visual_score = 0
    
    if slicer_was_running:
        visual_score += 2
    
    if segmentation_found:
        visual_score += 3
    elif output_exists and effective_masking:
        # If output is good, assume workflow was followed
        visual_score += 2
    
    score += min(visual_score, w_visual)
    
    if visual_score >= 4:
        feedback_parts.append("✓ Workflow evidence found")
        details['workflow_evidence'] = True
    elif visual_score >= 2:
        feedback_parts.append("△ Partial workflow evidence")
        details['workflow_evidence'] = 'partial'
    else:
        feedback_parts.append("✗ Limited workflow evidence")
        details['workflow_evidence'] = False
    
    # ================================================================
    # OPTIONAL: VLM trajectory verification
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames
            
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                vlm_prompt = """Analyze these screenshots from a 3D Slicer session.
The task was to create a skull-stripped brain volume using the Mask volume effect.

Look for evidence of:
1. Brain MRI data loaded (grayscale brain scan visible)
2. Segment Editor module open
3. A segmentation being created (colored overlay on brain)
4. Mask volume effect being used

Respond in JSON:
{
    "brain_data_visible": true/false,
    "segment_editor_used": true/false,
    "segmentation_visible": true/false,
    "workflow_completed": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_analysis'] = parsed
                    
                    # Could add bonus points for strong VLM confirmation
                    if parsed.get('workflow_completed') and parsed.get('confidence') == 'high':
                        logger.info("VLM confirms workflow completion")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Key criteria that must be met for passing
    key_criteria_met = (
        output_exists and 
        (effective_masking or near_zero_pct >= min_near_zero_pct * 0.7)
    )
    
    # Pass if score >= 70 AND key criteria met
    passed = score >= 70 and key_criteria_met
    
    # Build final feedback
    feedback_parts.append(f"\nTotal Score: {score}/{max_score}")
    feedback_parts.append(f"Pass Threshold: 70 points + output exists + effective masking")
    feedback_parts.append(f"Result: {'PASSED' if passed else 'FAILED'}")
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }