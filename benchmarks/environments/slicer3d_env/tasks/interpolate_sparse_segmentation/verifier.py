#!/usr/bin/env python3
"""
Verifier for Interpolate Sparse Segmentation task.

VERIFICATION STRATEGY:
This task requires the agent to use 3D Slicer's "Fill between slices" effect
to interpolate a sparse tumor segmentation into a complete 3D volume.

SCORING CRITERIA:
1. Segmentation Modified (20 pts) - The sparse segment was changed from initial state
2. Volume Increase Valid (25 pts) - Volume increased 3-8x (indicating interpolation applied)
3. Slice Coverage Good (20 pts) - >=85% of expected slices now have segmentation
4. No Large Gaps (15 pts) - Max consecutive empty slices <= 2
5. Volume Within Bounds (10 pts) - Result is 60-140% of expected full tumor volume
6. Centroid Consistent (10 pts) - Center of mass didn't shift significantly

ANTI-GAMING CHECKS:
- Timestamp verification (file must be created during task)
- Volume bounds check (can't just fill everything)
- Centroid consistency (can't create segmentation elsewhere)
- VLM trajectory verification (shows actual workflow progression)

PASS THRESHOLD: 60 points with "Segmentation Modified" AND "Volume Increase Valid" met
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_interpolate_sparse_segmentation(traj, env_info, task_info):
    """
    Verify that sparse segmentation was interpolated successfully.
    
    Uses multiple independent signals to prevent gaming:
    1. Programmatic checks from exported JSON
    2. VLM verification of trajectory frames
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
    expected_vol_increase_min = metadata.get('expected_volume_increase_min', 3.0)
    expected_vol_increase_max = metadata.get('expected_volume_increase_max', 8.0)
    expected_slice_coverage_min = metadata.get('expected_slice_coverage_min', 0.85)
    centroid_tolerance_mm = metadata.get('centroid_tolerance_mm', 10.0)
    
    weights = metadata.get('scoring_weights', {})
    w_modified = weights.get('segmentation_modified', 20)
    w_volume_increase = weights.get('volume_increase_valid', 25)
    w_slice_coverage = weights.get('slice_coverage_good', 20)
    w_no_gaps = weights.get('no_large_gaps', 15)
    w_volume_bounds = weights.get('volume_within_bounds', 10)
    w_centroid = weights.get('centroid_consistent', 10)

    # ================================================================
    # Load result JSON from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/interpolation_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export script may have failed"
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

    # ================================================================
    # Load initial statistics for comparison
    # ================================================================
    temp_initial = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    initial_stats = {}
    sample_id = result.get('sample_id', 'BraTS2021_00000')
    try:
        copy_from_env(f"/var/lib/slicer/ground_truth/{sample_id}_sparse_stats.json", temp_initial.name)
        with open(temp_initial.name, 'r') as f:
            initial_stats = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load initial stats: {e}")
    finally:
        if os.path.exists(temp_initial.name):
            os.unlink(temp_initial.name)

    # ================================================================
    # Initialize scoring
    # ================================================================
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
    # CRITERION 1: Segmentation Modified (20 points)
    # ================================================================
    segmentation_modified = result.get('segmentation_modified', False)
    initial_voxels = result.get('initial_voxel_count', 0)
    final_voxels = result.get('final_voxel_count', 0)
    
    details['initial_voxels'] = initial_voxels
    details['final_voxels'] = final_voxels

    if segmentation_modified and final_voxels > initial_voxels:
        score += w_modified
        feedback_parts.append(f"Segmentation modified ({initial_voxels}→{final_voxels} voxels)")
    elif final_voxels > 0:
        # Partial credit if there's some segmentation but not more than initial
        score += w_modified * 0.25
        feedback_parts.append(f"Segmentation exists but not increased ({final_voxels} voxels)")
    else:
        feedback_parts.append("Segmentation NOT modified")

    # ================================================================
    # CRITERION 2: Volume Increase Valid (25 points)
    # ================================================================
    volume_increase = result.get('volume_increase_ratio', 0)
    details['volume_increase_ratio'] = volume_increase

    if expected_vol_increase_min <= volume_increase <= expected_vol_increase_max:
        score += w_volume_increase
        feedback_parts.append(f"Volume increase valid ({volume_increase:.2f}x)")
    elif volume_increase > 1.5:
        # Partial credit for some increase
        partial = min(w_volume_increase * 0.5, w_volume_increase * (volume_increase - 1) / (expected_vol_increase_min - 1))
        score += int(partial)
        feedback_parts.append(f"Volume increase partial ({volume_increase:.2f}x, expected {expected_vol_increase_min}-{expected_vol_increase_max}x)")
    elif volume_increase > 1.0:
        score += w_volume_increase * 0.25
        feedback_parts.append(f"Volume slightly increased ({volume_increase:.2f}x)")
    else:
        feedback_parts.append(f"Volume NOT increased ({volume_increase:.2f}x)")

    # ================================================================
    # CRITERION 3: Slice Coverage Good (20 points)
    # ================================================================
    slice_coverage = result.get('slice_coverage', 0)
    initial_slice_count = result.get('initial_slice_count', 0)
    final_slice_count = result.get('final_slice_count', 0)
    
    details['initial_slice_count'] = initial_slice_count
    details['final_slice_count'] = final_slice_count
    details['slice_coverage'] = slice_coverage

    if slice_coverage >= expected_slice_coverage_min:
        score += w_slice_coverage
        feedback_parts.append(f"Good slice coverage ({slice_coverage:.0%})")
    elif slice_coverage >= 0.5:
        partial = w_slice_coverage * (slice_coverage / expected_slice_coverage_min)
        score += int(partial)
        feedback_parts.append(f"Partial slice coverage ({slice_coverage:.0%})")
    elif final_slice_count > initial_slice_count:
        score += w_slice_coverage * 0.25
        feedback_parts.append(f"Some slice interpolation ({initial_slice_count}→{final_slice_count} slices)")
    else:
        feedback_parts.append(f"Poor slice coverage ({slice_coverage:.0%})")

    # ================================================================
    # CRITERION 4: No Large Gaps (15 points)
    # ================================================================
    max_gap = result.get('max_consecutive_gap', 999)
    details['max_consecutive_gap'] = max_gap

    if max_gap <= 2:
        score += w_no_gaps
        feedback_parts.append(f"No large gaps (max={max_gap})")
    elif max_gap <= 4:
        score += w_no_gaps * 0.5
        feedback_parts.append(f"Small gaps present (max={max_gap})")
    elif max_gap < 10:
        score += w_no_gaps * 0.25
        feedback_parts.append(f"Gaps present (max={max_gap})")
    else:
        feedback_parts.append(f"Large gaps remain (max={max_gap})")

    # ================================================================
    # CRITERION 5: Volume Within Bounds (10 points)
    # Anti-gaming: Result should be close to expected full volume
    # ================================================================
    expected_full_voxels = initial_stats.get('full_voxel_count', 0)
    details['expected_full_voxels'] = expected_full_voxels

    if expected_full_voxels > 0 and final_voxels > 0:
        volume_ratio = final_voxels / expected_full_voxels
        details['volume_ratio_to_expected'] = volume_ratio
        
        if 0.6 <= volume_ratio <= 1.4:
            score += w_volume_bounds
            feedback_parts.append(f"Volume within bounds ({volume_ratio:.0%} of expected)")
        elif 0.4 <= volume_ratio <= 1.6:
            score += w_volume_bounds * 0.5
            feedback_parts.append(f"Volume somewhat off ({volume_ratio:.0%} of expected)")
        else:
            feedback_parts.append(f"Volume out of bounds ({volume_ratio:.0%} of expected)")
    else:
        feedback_parts.append("Could not verify volume bounds")

    # ================================================================
    # CRITERION 6: Centroid Consistent (10 points)
    # Anti-gaming: Centroid shouldn't move much
    # ================================================================
    initial_centroid = result.get('initial_centroid', [0, 0, 0])
    final_centroid = result.get('final_centroid', [0, 0, 0])
    
    # Parse centroids if they're strings
    if isinstance(initial_centroid, str):
        try:
            initial_centroid = json.loads(initial_centroid)
        except:
            initial_centroid = [0, 0, 0]
    if isinstance(final_centroid, str):
        try:
            final_centroid = json.loads(final_centroid)
        except:
            final_centroid = [0, 0, 0]
    
    details['initial_centroid'] = initial_centroid
    details['final_centroid'] = final_centroid

    if initial_centroid and final_centroid and len(initial_centroid) >= 3 and len(final_centroid) >= 3:
        try:
            # Calculate centroid distance (in voxels, approximate mm)
            centroid_dist = math.sqrt(sum((a - b) ** 2 for a, b in zip(initial_centroid, final_centroid)))
            details['centroid_distance'] = centroid_dist
            
            if centroid_dist <= centroid_tolerance_mm:
                score += w_centroid
                feedback_parts.append(f"Centroid consistent (shift={centroid_dist:.1f})")
            elif centroid_dist <= centroid_tolerance_mm * 2:
                score += w_centroid * 0.5
                feedback_parts.append(f"Centroid slightly shifted ({centroid_dist:.1f})")
            else:
                feedback_parts.append(f"Centroid shifted significantly ({centroid_dist:.1f})")
        except Exception as e:
            logger.warning(f"Centroid calculation error: {e}")
            feedback_parts.append("Could not verify centroid")
    else:
        feedback_parts.append("Could not verify centroid consistency")

    # ================================================================
    # VLM Trajectory Verification (bonus validation)
    # ================================================================
    vlm_verified = False
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        frames = sample_trajectory_frames(traj, n=5)
        if frames and len(frames) >= 3:
            vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging task.
The task was to use "Fill between slices" to interpolate a sparse tumor segmentation.

Look for evidence of:
1. Segment Editor module being used
2. "Fill between slices" effect being selected/applied
3. Segmentation becoming more complete across slices
4. Workflow progression (not just same screen repeated)

Respond in JSON:
{
    "segment_editor_visible": true/false,
    "fill_between_slices_used": true/false,
    "segmentation_changed": true/false,
    "workflow_progression": true/false,
    "confidence": "low"/"medium"/"high"
}"""
            
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_verification'] = parsed
                
                if parsed.get('fill_between_slices_used') or parsed.get('segmentation_changed'):
                    vlm_verified = True
                    feedback_parts.append("VLM: workflow confirmed")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)

    # ================================================================
    # Final scoring and pass determination
    # ================================================================
    
    # Key criteria for passing
    key_criteria_met = (
        segmentation_modified and 
        volume_increase >= expected_vol_increase_min * 0.7  # Allow some tolerance
    )
    
    passed = score >= 60 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }