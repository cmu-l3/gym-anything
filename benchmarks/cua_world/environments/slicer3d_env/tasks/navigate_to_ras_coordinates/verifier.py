#!/usr/bin/env python3
"""
Verifier for navigate_to_ras_coordinates task.

VERIFICATION STRATEGY:
1. R-coordinate correct (25 points) - within ±2mm of target R=12
2. A-coordinate correct (25 points) - within ±2mm of target A=-8
3. S-coordinate correct (25 points) - within ±2mm of target S=35
4. Position changed from initial (15 points) - crosshair moved during task
5. VLM verification (10 points) - slice views show brain content changed

Pass threshold: 75 points (all three coordinates correct)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_navigate_to_ras_coordinates(traj, env_info, task_info):
    """
    Verify that the agent navigated to the correct RAS coordinates.
    
    Uses multi-criteria scoring:
    - Checks each coordinate axis independently
    - Verifies position actually changed (anti-gaming)
    - Uses VLM to verify slice views updated
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
    target_r = metadata.get('target_r', 12.0)
    target_a = metadata.get('target_a', -8.0)
    target_s = metadata.get('target_s', 35.0)
    tolerance = metadata.get('tolerance_mm', 2.0)
    
    weights = metadata.get('scoring_weights', {})
    w_r = weights.get('r_coordinate_correct', 25)
    w_a = weights.get('a_coordinate_correct', 25)
    w_s = weights.get('s_coordinate_correct', 25)
    w_changed = weights.get('position_changed', 15)
    w_vlm = weights.get('vlm_verification', 10)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/navigation_result.json", temp_result.name)
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
    # CHECK BASIC REQUIREMENTS
    # ================================================================
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify navigation"
        }
    
    # Check if crosshair query succeeded
    if not result.get('crosshair_query_success', False):
        feedback_parts.append("Crosshair position query failed")
        # Continue with partial scoring based on available data
    
    # Check if data was loaded
    if not result.get('data_loaded', False):
        feedback_parts.append("MRHead data not loaded")
    
    # ================================================================
    # CRITERION 1: R-coordinate correct (25 points)
    # ================================================================
    final_r = result.get('final_r', 0.0)
    dist_r = abs(final_r - target_r)
    details['final_r'] = final_r
    details['dist_r'] = dist_r
    
    if dist_r <= tolerance:
        score += w_r
        feedback_parts.append(f"R={final_r:.1f}mm ✓")
    elif dist_r <= tolerance * 2:
        # Partial credit for close
        score += w_r // 2
        feedback_parts.append(f"R={final_r:.1f}mm (close)")
    else:
        feedback_parts.append(f"R={final_r:.1f}mm (target: {target_r})")
    
    # ================================================================
    # CRITERION 2: A-coordinate correct (25 points)
    # ================================================================
    final_a = result.get('final_a', 0.0)
    dist_a = abs(final_a - target_a)
    details['final_a'] = final_a
    details['dist_a'] = dist_a
    
    if dist_a <= tolerance:
        score += w_a
        feedback_parts.append(f"A={final_a:.1f}mm ✓")
    elif dist_a <= tolerance * 2:
        score += w_a // 2
        feedback_parts.append(f"A={final_a:.1f}mm (close)")
    else:
        feedback_parts.append(f"A={final_a:.1f}mm (target: {target_a})")
    
    # ================================================================
    # CRITERION 3: S-coordinate correct (25 points)
    # ================================================================
    final_s = result.get('final_s', 0.0)
    dist_s = abs(final_s - target_s)
    details['final_s'] = final_s
    details['dist_s'] = dist_s
    
    if dist_s <= tolerance:
        score += w_s
        feedback_parts.append(f"S={final_s:.1f}mm ✓")
    elif dist_s <= tolerance * 2:
        score += w_s // 2
        feedback_parts.append(f"S={final_s:.1f}mm (close)")
    else:
        feedback_parts.append(f"S={final_s:.1f}mm (target: {target_s})")
    
    # ================================================================
    # CRITERION 4: Position changed from initial (15 points)
    # Anti-gaming: ensure agent actually did something
    # ================================================================
    position_changed = result.get('position_changed', False)
    details['position_changed'] = position_changed
    
    # Also verify by comparing initial vs final
    initial_r = result.get('initial_r', 0.0)
    initial_a = result.get('initial_a', 0.0)
    initial_s = result.get('initial_s', 0.0)
    
    movement_dist = math.sqrt(
        (final_r - initial_r)**2 + 
        (final_a - initial_a)**2 + 
        (final_s - initial_s)**2
    )
    details['movement_distance'] = movement_dist
    
    if position_changed or movement_dist > 1.0:
        score += w_changed
        feedback_parts.append(f"Position changed ({movement_dist:.1f}mm)")
    else:
        feedback_parts.append("Position did not change (no action taken)")
    
    # ================================================================
    # CRITERION 5: VLM verification (10 points)
    # Check if slice views show expected content
    # ================================================================
    vlm_score = 0
    
    try:
        # Import VLM utilities if available
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            # Use trajectory frames for verification (more trustworthy than final screenshot)
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames from trajectory to verify workflow
            frames = sample_trajectory_frames(traj, n=3) if traj else []
            final_frame = get_final_screenshot(traj) if traj else None
            
            if final_frame or frames:
                vlm_prompt = """Analyze this screenshot from 3D Slicer medical imaging software.

Look at the slice views (typically showing Axial, Sagittal, and Coronal cross-sections of a brain MRI).

Questions:
1. Is there a brain MRI visible in the slice views?
2. Are the crosshairs visible (yellow lines crossing at a specific point)?
3. Do the slice views show brain tissue (gray matter structures)?
4. Does it appear the views are centered on an internal brain region (not the edge/surface)?

Respond in JSON:
{
    "brain_mri_visible": true/false,
    "crosshairs_visible": true/false,
    "brain_tissue_shown": true/false,
    "internal_region": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                images_to_check = frames + ([final_frame] if final_frame else [])
                if images_to_check:
                    vlm_result = query_vlm(prompt=vlm_prompt, images=images_to_check[-2:])
                    
                    if vlm_result and vlm_result.get('success'):
                        parsed = vlm_result.get('parsed', {})
                        details['vlm_result'] = parsed
                        
                        # Score based on VLM findings
                        if parsed.get('brain_mri_visible', False):
                            vlm_score += 4
                        if parsed.get('crosshairs_visible', False):
                            vlm_score += 3
                        if parsed.get('internal_region', False):
                            vlm_score += 3
                        
                        if vlm_score > 0:
                            feedback_parts.append(f"VLM: brain visible ({vlm_score}pts)")
                        else:
                            feedback_parts.append("VLM: unclear visualization")
                    else:
                        feedback_parts.append("VLM query failed")
            else:
                feedback_parts.append("No frames for VLM")
        else:
            # No VLM available, give partial credit if coordinates are correct
            if dist_r <= tolerance and dist_a <= tolerance and dist_s <= tolerance:
                vlm_score = w_vlm // 2
                feedback_parts.append("VLM unavailable (partial credit)")
            else:
                feedback_parts.append("VLM unavailable")
                
    except ImportError:
        # VLM utilities not available
        if dist_r <= tolerance and dist_a <= tolerance and dist_s <= tolerance:
            vlm_score = w_vlm // 2
        feedback_parts.append("VLM module unavailable")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM error")
    
    score += vlm_score
    
    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    
    # Calculate euclidean distance from target
    euclidean_dist = math.sqrt(dist_r**2 + dist_a**2 + dist_s**2)
    details['euclidean_distance'] = euclidean_dist
    
    # Coordinates correct within tolerance
    r_correct = dist_r <= tolerance
    a_correct = dist_a <= tolerance
    s_correct = dist_s <= tolerance
    all_correct = r_correct and a_correct and s_correct
    
    details['r_correct'] = r_correct
    details['a_correct'] = a_correct
    details['s_correct'] = s_correct
    details['all_coordinates_correct'] = all_correct
    
    # Pass threshold: 75 points (all three coordinates correct)
    # Key criterion: all coordinates must be within tolerance
    passed = score >= 75 and all_correct
    
    # Build feedback string
    feedback = " | ".join(feedback_parts)
    if all_correct:
        feedback = f"Navigation successful! Euclidean dist: {euclidean_dist:.1f}mm | {feedback}"
    else:
        feedback = f"Navigation incomplete. Euclidean dist: {euclidean_dist:.1f}mm | {feedback}"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }