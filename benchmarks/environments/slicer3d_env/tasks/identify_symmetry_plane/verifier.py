#!/usr/bin/env python3
"""
Verifier for Identify Midsagittal Symmetry Plane task.

VERIFICATION CRITERIA:
1. Plane Markup Exists (20 points) - A plane markup node is present in scene
2. Correct Naming (10 points) - Plane name contains 'midsagittal' or similar
3. Sagittal Orientation (30 points) - Plane normal within 15° of L-R axis
4. Midline Position (25 points) - Plane origin within 10mm of volume L-R center
5. Screenshot Captured (10 points) - Valid screenshot showing plane in 3D
6. VLM Visual Confirmation (5 points) - VLM confirms plane divides brain visually

Pass threshold: 70 points with both Plane Exists (20) AND Sagittal Orientation (30) achieved
"""

import json
import math
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_identify_symmetry_plane(traj, env_info, task_info):
    """
    Verify that the midsagittal symmetry plane was correctly identified and placed.
    
    Uses multi-criteria scoring with geometric verification and VLM confirmation.
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
    orientation_tolerance = metadata.get('orientation_tolerance_degrees', 15)
    position_tolerance = metadata.get('position_tolerance_mm', 10)
    
    weights = metadata.get('scoring_weights', {})
    w_plane_exists = weights.get('plane_exists', 20)
    w_correct_naming = weights.get('correct_naming', 10)
    w_sagittal_orientation = weights.get('sagittal_orientation', 30)
    w_midline_position = weights.get('midline_position', 25)
    w_screenshot = weights.get('screenshot_captured', 10)
    w_vlm = weights.get('vlm_visual_confirmation', 5)
    
    pass_threshold = metadata.get('pass_threshold', 70)
    
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
        copy_from_env("/tmp/symmetry_plane_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        details['result_loaded'] = True
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # CRITERION 1: Plane Markup Exists (20 points)
    # ================================================================
    plane_found = result.get('plane_found', False)
    plane_name = result.get('plane_name', '')
    
    if plane_found:
        score += w_plane_exists
        feedback_parts.append(f"Plane markup found: '{plane_name}'")
        details['plane_exists'] = True
    else:
        feedback_parts.append("No plane markup found in scene")
        details['plane_exists'] = False
        # Without a plane, we can't verify much else
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Correct Naming (10 points)
    # ================================================================
    name_contains_midsagittal = result.get('name_contains_midsagittal', False)
    
    if name_contains_midsagittal:
        score += w_correct_naming
        feedback_parts.append("Plane correctly named with 'midsagittal'")
        details['correct_naming'] = True
    else:
        # Partial credit if plane exists but not named correctly
        name_lower = plane_name.lower()
        if any(term in name_lower for term in ['plane', 'mid', 'center', 'sagittal']):
            score += w_correct_naming // 2
            feedback_parts.append(f"Plane name partially correct: '{plane_name}'")
            details['correct_naming'] = 'partial'
        else:
            feedback_parts.append(f"Plane name missing 'midsagittal': '{plane_name}'")
            details['correct_naming'] = False
    
    # ================================================================
    # CRITERION 3: Sagittal Orientation (30 points)
    # ================================================================
    orientation_angle = result.get('orientation_angle_from_lr_deg', 999)
    plane_normal = result.get('plane_normal', [0, 0, 0])
    
    details['orientation_angle_deg'] = orientation_angle
    details['plane_normal'] = plane_normal
    
    # Check if orientation angle is valid (not default 999)
    if orientation_angle < 900:
        if orientation_angle <= orientation_tolerance:
            # Full points - well-aligned with L-R axis
            score += w_sagittal_orientation
            feedback_parts.append(f"Sagittal orientation correct ({orientation_angle:.1f}° from L-R)")
            details['sagittal_orientation'] = True
        elif orientation_angle <= orientation_tolerance * 2:
            # Partial points - somewhat aligned
            partial = int(w_sagittal_orientation * 0.5)
            score += partial
            feedback_parts.append(f"Sagittal orientation acceptable ({orientation_angle:.1f}°)")
            details['sagittal_orientation'] = 'partial'
        else:
            feedback_parts.append(f"Plane not sagittal-oriented ({orientation_angle:.1f}° from L-R axis)")
            details['sagittal_orientation'] = False
    else:
        feedback_parts.append("Could not determine plane orientation")
        details['sagittal_orientation'] = 'unknown'
    
    # ================================================================
    # CRITERION 4: Midline Position (25 points)
    # ================================================================
    plane_origin = result.get('plane_origin', [0, 0, 0])
    volume_center = result.get('volume_center', [0, 0, 0])
    volume_loaded = result.get('volume_loaded', False)
    
    details['plane_origin'] = plane_origin
    details['volume_center'] = volume_center
    
    if volume_loaded and plane_origin != [0, 0, 0]:
        # For midsagittal plane, the L-R (X in RAS) coordinate should match
        lr_difference = abs(plane_origin[0] - volume_center[0])
        details['lr_offset_mm'] = lr_difference
        
        if lr_difference <= position_tolerance:
            score += w_midline_position
            feedback_parts.append(f"Midline position correct ({lr_difference:.1f}mm from center)")
            details['midline_position'] = True
        elif lr_difference <= position_tolerance * 2:
            partial = int(w_midline_position * 0.5)
            score += partial
            feedback_parts.append(f"Midline position acceptable ({lr_difference:.1f}mm offset)")
            details['midline_position'] = 'partial'
        else:
            feedback_parts.append(f"Plane not at midline ({lr_difference:.1f}mm from center)")
            details['midline_position'] = False
    else:
        feedback_parts.append("Could not verify midline position")
        details['midline_position'] = 'unknown'
    
    # ================================================================
    # CRITERION 5: Screenshot Captured (10 points)
    # ================================================================
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size_kb = result.get('screenshot_size_kb', 0)
    screenshot_during_task = result.get('screenshot_created_during_task', False)
    
    details['screenshot_exists'] = screenshot_exists
    details['screenshot_size_kb'] = screenshot_size_kb
    
    if screenshot_exists and screenshot_size_kb > 50:
        if screenshot_during_task:
            score += w_screenshot
            feedback_parts.append(f"Screenshot captured ({screenshot_size_kb}KB)")
            details['screenshot_captured'] = True
        else:
            # Partial credit if screenshot exists but may be old
            score += w_screenshot // 2
            feedback_parts.append(f"Screenshot exists but may be pre-existing ({screenshot_size_kb}KB)")
            details['screenshot_captured'] = 'partial'
    elif screenshot_exists:
        score += w_screenshot // 3
        feedback_parts.append(f"Screenshot small ({screenshot_size_kb}KB)")
        details['screenshot_captured'] = 'small'
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_captured'] = False
    
    # ================================================================
    # CRITERION 6: VLM Visual Confirmation (5 points)
    # ================================================================
    vlm_score = 0
    vlm_feedback = "VLM verification skipped"
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
        
        # Get trajectory frames and final screenshot
        frames = sample_trajectory_frames(traj, n=3) if traj else []
        final_screenshot = get_final_screenshot(traj)
        
        # Combine frames for analysis
        all_images = frames + ([final_screenshot] if final_screenshot else [])
        
        if all_images:
            vlm_prompt = """You are analyzing screenshots from a medical imaging task in 3D Slicer.

The agent was asked to place a midsagittal symmetry plane on a brain MRI.

Look at these screenshots and assess:
1. Is there a brain MRI visible?
2. Can you see a plane markup (usually shown as a colored rectangle/disc in 3D view)?
3. Does the plane appear to divide the brain into left and right halves?
4. Is the plane oriented vertically (sagittal orientation)?

Respond in JSON format:
{
    "brain_visible": true/false,
    "plane_visible": true/false,
    "plane_divides_brain": true/false,
    "plane_appears_sagittal": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
            vlm_result = query_vlm(prompt=vlm_prompt, images=all_images)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                details['vlm_result'] = parsed
                
                plane_visible = parsed.get('plane_visible', False)
                plane_divides = parsed.get('plane_divides_brain', False)
                plane_sagittal = parsed.get('plane_appears_sagittal', False)
                confidence = parsed.get('confidence', 'low')
                
                # Score based on VLM findings
                if plane_visible and plane_divides and plane_sagittal:
                    vlm_score = w_vlm
                    vlm_feedback = f"VLM confirms plane divides brain ({confidence} confidence)"
                elif plane_visible and (plane_divides or plane_sagittal):
                    vlm_score = w_vlm // 2
                    vlm_feedback = f"VLM: plane visible, partial confirmation ({confidence})"
                elif plane_visible:
                    vlm_score = w_vlm // 3
                    vlm_feedback = f"VLM: plane visible but placement unclear"
                else:
                    vlm_feedback = "VLM: plane not clearly visible"
            else:
                vlm_feedback = "VLM query unsuccessful"
        else:
            vlm_feedback = "No trajectory frames available for VLM"
            
    except ImportError:
        vlm_feedback = "VLM utilities not available"
    except Exception as e:
        vlm_feedback = f"VLM verification failed: {str(e)[:50]}"
        logger.warning(f"VLM verification error: {e}")
    
    score += vlm_score
    feedback_parts.append(vlm_feedback)
    details['vlm_score'] = vlm_score
    details['vlm_feedback'] = vlm_feedback
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    
    # Check required criteria for passing
    plane_exists_ok = details.get('plane_exists', False)
    orientation_ok = details.get('sagittal_orientation', False) in [True, 'partial']
    
    key_criteria_met = plane_exists_ok and orientation_ok
    passed = (score >= pass_threshold) and key_criteria_met
    
    # Add summary
    details['total_score'] = score
    details['pass_threshold'] = pass_threshold
    details['key_criteria_met'] = key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    # Add pass/fail reason
    if passed:
        feedback = f"PASSED ({score}/100): " + feedback
    else:
        if not key_criteria_met:
            if not plane_exists_ok:
                feedback = f"FAILED (no plane created): " + feedback
            elif not orientation_ok:
                feedback = f"FAILED (plane not sagittal-oriented): " + feedback
        else:
            feedback = f"FAILED (score {score} < {pass_threshold}): " + feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }