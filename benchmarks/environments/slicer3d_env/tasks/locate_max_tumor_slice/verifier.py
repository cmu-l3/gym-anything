#!/usr/bin/env python3
"""
Verifier for Locate Maximum Tumor Cross-Section Slice task.

VERIFICATION STRATEGY:
This task tests the agent's ability to navigate through a 3D brain MRI volume
and identify the axial slice with maximum tumor cross-sectional area.

SCORING CRITERIA (100 points total):
1. Fiducial Exists (20 pts) - A fiducial marker was placed in the scene
2. Within Brain Volume (10 pts) - Fiducial coordinates are within image bounds
3. Slice Accuracy:
   - Exact (±1 slice): 40 pts
   - Close (±3 slices): 25 pts  
   - Acceptable (±5 slices): 15 pts
4. XY Near Tumor (15 pts) - Fiducial XY is within the tumor region
5. VLM Tumor Visible (10 pts) - Screenshot shows tumor on displayed slice

ANTI-GAMING:
- Placing no fiducial scores 0
- Random placement will likely miss the ±5 slice tolerance
- XY coordinates must be near actual tumor

Pass threshold: 60 points with fiducial placed and at least acceptable slice accuracy
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_locate_max_tumor_slice(traj, env_info, task_info):
    """
    Verify that the agent found the maximum tumor cross-section slice.
    
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
    tolerance_exact = metadata.get('exact_tolerance_slices', 1)
    tolerance_close = metadata.get('tolerance_slices', 3)
    tolerance_acceptable = metadata.get('acceptable_tolerance_slices', 5)
    
    weights = metadata.get('scoring_weights', {})
    w_fiducial_exists = weights.get('fiducial_exists', 20)
    w_within_volume = weights.get('within_brain_volume', 10)
    w_slice_exact = weights.get('slice_exact', 40)
    w_slice_close = weights.get('slice_close', 25)
    w_slice_acceptable = weights.get('slice_acceptable', 15)
    w_xy_near_tumor = weights.get('xy_near_tumor', 15)
    w_vlm_tumor = weights.get('vlm_tumor_visible', 10)

    # Initialize
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # COPY RESULT FILES FROM CONTAINER
    # ================================================================
    
    # Copy main result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/max_slice_task_result.json", temp_result.name)
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

    # Copy ground truth JSON
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/max_slice_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Copy fiducial data if exists
    temp_fid = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    fiducial_data = {"fiducial_count": 0, "fiducials": []}
    try:
        copy_from_env("/tmp/fiducial_positions.json", temp_fid.name)
        with open(temp_fid.name, 'r') as f:
            fiducial_data = json.load(f)
    except Exception as e:
        logger.debug(f"No fiducial data file: {e}")
    finally:
        if os.path.exists(temp_fid.name):
            os.unlink(temp_fid.name)

    # Store details
    details['result'] = result
    details['ground_truth'] = gt_data

    # ================================================================
    # CHECK BASIC REQUIREMENTS
    # ================================================================
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - task could not be completed",
            "details": details
        }

    # Get ground truth values
    gt_max_z = gt_data.get('max_slice_z_ras')
    gt_max_idx = gt_data.get('max_slice_index')
    gt_centroid = gt_data.get('centroid_ras', [0, 0, 0])
    volume_shape = gt_data.get('volume_shape', [0, 0, 0])
    spacing = gt_data.get('spacing_mm', [1, 1, 1])

    if gt_max_z is None or gt_max_idx is None:
        feedback_parts.append("Ground truth not available for comparison")
        details['gt_error'] = "Missing ground truth data"

    details['gt_max_slice_z'] = gt_max_z
    details['gt_max_slice_index'] = gt_max_idx
    details['gt_centroid_ras'] = gt_centroid

    # ================================================================
    # CRITERION 1: FIDUCIAL EXISTS (20 points)
    # ================================================================
    fiducial_count = fiducial_data.get('fiducial_count', 0)
    fiducials = fiducial_data.get('fiducials', [])

    if fiducial_count > 0 and len(fiducials) > 0:
        score += w_fiducial_exists
        feedback_parts.append(f"Fiducial placed ({fiducial_count} point(s))")
        details['fiducial_exists'] = True
    else:
        feedback_parts.append("No fiducial placed")
        details['fiducial_exists'] = False
        # Cannot proceed without a fiducial
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " - Task requires placing a fiducial marker",
            "details": details
        }

    # Get the first (or primary) fiducial's position
    agent_fiducial = fiducials[0]
    agent_x = agent_fiducial.get('x', 0)
    agent_y = agent_fiducial.get('y', 0)
    agent_z = agent_fiducial.get('z', 0)
    
    details['agent_fiducial_ras'] = [agent_x, agent_y, agent_z]

    # ================================================================
    # CRITERION 2: WITHIN BRAIN VOLUME (10 points)
    # ================================================================
    # Check if fiducial is within reasonable bounds
    # RAS coordinates can be negative, so check against volume extent
    if volume_shape and len(volume_shape) >= 3 and spacing:
        # Approximate volume extent in RAS
        extent_x = volume_shape[0] * spacing[0]
        extent_y = volume_shape[1] * spacing[1]
        extent_z = volume_shape[2] * spacing[2]
        
        # Allow generous bounds (fiducial should be roughly within volume)
        within_bounds = (
            abs(agent_x) < extent_x and
            abs(agent_y) < extent_y and
            abs(agent_z) < extent_z * 2  # Z can vary more due to positioning
        )
        
        if within_bounds:
            score += w_within_volume
            feedback_parts.append("Fiducial within volume bounds")
            details['within_bounds'] = True
        else:
            feedback_parts.append("Fiducial outside expected volume bounds")
            details['within_bounds'] = False
    else:
        # Can't check bounds, give partial credit
        score += w_within_volume // 2
        feedback_parts.append("Volume bounds unknown")
        details['within_bounds'] = "unknown"

    # ================================================================
    # CRITERION 3: SLICE ACCURACY (40/25/15 points)
    # ================================================================
    slice_score = 0
    slice_accuracy = "outside_tolerance"
    
    if gt_max_z is not None:
        # Calculate Z offset in mm
        z_offset_mm = abs(agent_z - gt_max_z)
        
        # Convert to approximate slice offset
        slice_spacing_z = spacing[2] if spacing and len(spacing) > 2 else 1.0
        z_offset_slices = z_offset_mm / slice_spacing_z if slice_spacing_z > 0 else float('inf')
        
        details['z_offset_mm'] = z_offset_mm
        details['z_offset_slices'] = z_offset_slices
        details['agent_z'] = agent_z
        details['gt_z'] = gt_max_z

        if z_offset_slices <= tolerance_exact:
            slice_score = w_slice_exact
            slice_accuracy = "exact"
            feedback_parts.append(f"Slice accuracy: EXACT (within ±{tolerance_exact})")
        elif z_offset_slices <= tolerance_close:
            slice_score = w_slice_close
            slice_accuracy = "close"
            feedback_parts.append(f"Slice accuracy: CLOSE (within ±{tolerance_close})")
        elif z_offset_slices <= tolerance_acceptable:
            slice_score = w_slice_acceptable
            slice_accuracy = "acceptable"
            feedback_parts.append(f"Slice accuracy: ACCEPTABLE (within ±{tolerance_acceptable})")
        else:
            feedback_parts.append(f"Slice accuracy: OUTSIDE tolerance ({z_offset_slices:.1f} slices off)")
        
        score += slice_score
        details['slice_accuracy'] = slice_accuracy
    else:
        feedback_parts.append("Cannot verify slice accuracy (no ground truth)")
        details['slice_accuracy'] = "unknown"

    # ================================================================
    # CRITERION 4: XY NEAR TUMOR CENTER (15 points)
    # ================================================================
    if gt_centroid and len(gt_centroid) >= 2:
        # Calculate XY distance from tumor centroid
        xy_dist = math.sqrt(
            (agent_x - gt_centroid[0])**2 + 
            (agent_y - gt_centroid[1])**2
        )
        
        details['xy_distance_mm'] = xy_dist
        
        # Tumor radius is roughly 20-50mm, allow up to 30mm deviation
        if xy_dist < 15:
            score += w_xy_near_tumor
            feedback_parts.append(f"XY position: near tumor center ({xy_dist:.1f}mm)")
            details['xy_near_tumor'] = True
        elif xy_dist < 30:
            score += w_xy_near_tumor // 2
            feedback_parts.append(f"XY position: within tumor region ({xy_dist:.1f}mm)")
            details['xy_near_tumor'] = "partial"
        else:
            feedback_parts.append(f"XY position: far from tumor ({xy_dist:.1f}mm)")
            details['xy_near_tumor'] = False
    else:
        feedback_parts.append("Cannot verify XY position (no centroid data)")
        details['xy_near_tumor'] = "unknown"

    # ================================================================
    # CRITERION 5: VLM TRAJECTORY VERIFICATION (10 points)
    # ================================================================
    vlm_score = 0
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        
        # Sample trajectory frames to verify work was done
        frames = sample_trajectory_frames(traj, n=5)
        
        if frames and len(frames) > 0:
            vlm_prompt = """You are analyzing screenshots from a medical imaging task in 3D Slicer.

The task was to navigate through a brain MRI to find the slice with maximum tumor cross-section.

Looking at these trajectory screenshots, assess:
1. Is brain MRI data visible in the slice views?
2. Is there a visible tumor (bright region in the brain)?
3. Did the user navigate through different slices (evidence of scrolling/slice changes)?
4. Is there a fiducial marker (small dot/point) visible on the image?

Respond in JSON format:
{
    "brain_mri_visible": true/false,
    "tumor_visible": true/false,
    "slice_navigation_evident": true/false,
    "fiducial_marker_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                tumor_visible = parsed.get('tumor_visible', False)
                fiducial_visible = parsed.get('fiducial_marker_visible', False)
                navigation = parsed.get('slice_navigation_evident', False)
                
                if tumor_visible and fiducial_visible:
                    vlm_score = w_vlm_tumor
                    feedback_parts.append("VLM: Tumor and fiducial visible")
                elif tumor_visible or fiducial_visible:
                    vlm_score = w_vlm_tumor // 2
                    feedback_parts.append("VLM: Partial visual confirmation")
                else:
                    feedback_parts.append("VLM: Could not confirm visual evidence")
                
                details['vlm_observations'] = parsed.get('observations', '')
            else:
                feedback_parts.append("VLM: Analysis unavailable")
                details['vlm_error'] = "VLM query failed"
        else:
            feedback_parts.append("VLM: No trajectory frames available")
            details['vlm_error'] = "No frames"
            
    except ImportError:
        feedback_parts.append("VLM: Not available")
        details['vlm_error'] = "Import error"
    except Exception as e:
        feedback_parts.append(f"VLM: Error ({str(e)[:50]})")
        details['vlm_error'] = str(e)
    
    score += vlm_score

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    
    # Key criteria: fiducial must exist and slice must be at least acceptable
    fiducial_exists = details.get('fiducial_exists', False)
    slice_ok = slice_accuracy in ['exact', 'close', 'acceptable']
    
    passed = (score >= 60) and fiducial_exists and slice_ok
    
    details['final_score'] = score
    details['passed'] = passed
    details['key_criteria'] = {
        'fiducial_exists': fiducial_exists,
        'slice_accuracy_ok': slice_ok,
        'score_threshold_met': score >= 60
    }

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }