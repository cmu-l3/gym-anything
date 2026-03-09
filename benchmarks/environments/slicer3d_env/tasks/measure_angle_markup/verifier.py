#!/usr/bin/env python3
"""
Verifier for measure_angle_markup task.

VERIFICATION CRITERIA:
1. Angle markup exists (25 points) - vtkMRMLMarkupsAngleNode present in scene
2. Three points defined (20 points) - Angle node has exactly 3 control points
3. Valid angle value (15 points) - Angle between 10° and 170° (geometric validity)
4. Points in volume bounds (15 points) - Control points are within brain image extent
5. Export file exists (10 points) - angle_measurement.txt exists
6. Export file valid (10 points) - File contains numeric value matching scene
7. VLM confirmation (5 points) - Visual confirmation of angle annotation

Pass threshold: 70 points with angle_markup_exists and three_points_defined
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_angle_markup(traj, env_info, task_info):
    """
    Verify angle measurement task completion.
    
    Uses multi-criteria scoring with anti-gaming checks.
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
    valid_angle_min = metadata.get('valid_angle_min', 10.0)
    valid_angle_max = metadata.get('valid_angle_max', 170.0)
    
    weights = metadata.get('scoring_weights', {})
    w_markup_exists = weights.get('angle_markup_exists', 25)
    w_three_points = weights.get('three_points_defined', 20)
    w_valid_angle = weights.get('valid_angle_value', 15)
    w_points_in_vol = weights.get('points_in_volume', 15)
    w_file_exists = weights.get('export_file_exists', 10)
    w_file_valid = weights.get('export_file_valid', 10)
    w_vlm = weights.get('vlm_confirmation', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/angle_task_result.json", temp_result.name)
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
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion"
        }
    
    # ============================================================
    # CRITERION 1: Angle markup exists (25 points)
    # ============================================================
    angle_markup_exists = result.get('angle_markup_exists', False)
    details['angle_markup_exists'] = angle_markup_exists
    
    if angle_markup_exists:
        score += w_markup_exists
        feedback_parts.append("Angle markup created")
        logger.info("PASS: Angle markup exists")
    else:
        feedback_parts.append("NO angle markup found")
        logger.info("FAIL: No angle markup in scene")
        # Early exit - can't verify anything else without an angle
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ============================================================
    # CRITERION 2: Three points defined (20 points)
    # ============================================================
    num_control_points = result.get('num_control_points', 0)
    details['num_control_points'] = num_control_points
    
    if num_control_points == 3:
        score += w_three_points
        feedback_parts.append("3 control points placed")
        logger.info("PASS: Exactly 3 control points")
    elif num_control_points > 0:
        # Partial credit
        partial = int(w_three_points * num_control_points / 3)
        score += min(partial, w_three_points - 5)
        feedback_parts.append(f"Only {num_control_points} control point(s)")
        logger.info(f"PARTIAL: {num_control_points} control points (need 3)")
    else:
        feedback_parts.append("No control points placed")
        logger.info("FAIL: No control points")
    
    # ============================================================
    # CRITERION 3: Valid angle value (15 points)
    # ============================================================
    angle_in_scene_str = result.get('angle_in_scene_degrees', '')
    angle_in_scene = None
    
    if angle_in_scene_str:
        try:
            angle_in_scene = float(angle_in_scene_str)
            details['angle_in_scene'] = angle_in_scene
        except ValueError:
            pass
    
    if angle_in_scene is not None:
        if valid_angle_min <= angle_in_scene <= valid_angle_max:
            score += w_valid_angle
            feedback_parts.append(f"Valid angle: {angle_in_scene:.1f}°")
            logger.info(f"PASS: Angle {angle_in_scene:.1f}° is valid")
        elif angle_in_scene > 0:
            # Some points for having a measurement, even if unusual
            score += int(w_valid_angle * 0.3)
            feedback_parts.append(f"Unusual angle: {angle_in_scene:.1f}°")
            logger.info(f"PARTIAL: Angle {angle_in_scene:.1f}° outside expected range")
        else:
            feedback_parts.append(f"Invalid angle: {angle_in_scene:.1f}°")
            logger.info(f"FAIL: Angle {angle_in_scene:.1f}° is invalid")
    else:
        feedback_parts.append("No angle value measured")
        logger.info("FAIL: No angle value")
    
    # ============================================================
    # CRITERION 4: Points in volume bounds (15 points)
    # ============================================================
    control_points = result.get('control_points', [])
    volume_loaded = result.get('volume_loaded', False)
    details['volume_loaded'] = volume_loaded
    
    if volume_loaded and control_points and len(control_points) >= 3:
        # Check if points are within reasonable brain volume bounds
        # MRHead is approximately 256x256x130 with typical medical spacing
        # RAS coordinates might be approximately [-128, 128] in each dimension
        points_valid = 0
        for cp in control_points:
            pos = cp.get('position', [0, 0, 0])
            # Rough bounds check - brain MRI typically within +/- 150mm from center
            if all(-200 < p < 200 for p in pos):
                points_valid += 1
        
        if points_valid == 3:
            score += w_points_in_vol
            feedback_parts.append("Points within volume")
            logger.info("PASS: All points within volume bounds")
        elif points_valid > 0:
            partial = int(w_points_in_vol * points_valid / 3)
            score += partial
            feedback_parts.append(f"{points_valid}/3 points in bounds")
            logger.info(f"PARTIAL: {points_valid}/3 points in volume")
        else:
            feedback_parts.append("Points outside volume")
            logger.info("FAIL: Points outside volume bounds")
    elif not volume_loaded:
        feedback_parts.append("Volume not loaded")
        logger.info("FAIL: Volume not loaded - cannot check point bounds")
    
    # ============================================================
    # CRITERION 5: Export file exists (10 points)
    # ============================================================
    output_file_exists = result.get('output_file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    details['output_file_exists'] = output_file_exists
    details['file_created_during_task'] = file_created_during_task
    
    if output_file_exists:
        if file_created_during_task:
            score += w_file_exists
            feedback_parts.append("Output file created")
            logger.info("PASS: Output file created during task")
        else:
            # File exists but may have been pre-existing
            score += int(w_file_exists * 0.5)
            feedback_parts.append("Output file exists (pre-existing?)")
            logger.info("PARTIAL: Output file exists but timestamp unclear")
    else:
        feedback_parts.append("No output file")
        logger.info("FAIL: No output file created")
    
    # ============================================================
    # CRITERION 6: Export file valid (10 points)
    # ============================================================
    output_file_value = result.get('output_file_value', '')
    details['output_file_value'] = output_file_value
    
    if output_file_value:
        try:
            exported_angle = float(output_file_value)
            details['exported_angle'] = exported_angle
            
            # Check if exported value is valid
            if valid_angle_min <= exported_angle <= valid_angle_max:
                # Check if it matches scene value (within tolerance)
                if angle_in_scene is not None:
                    diff = abs(exported_angle - angle_in_scene)
                    if diff < 1.0:  # Within 1 degree
                        score += w_file_valid
                        feedback_parts.append(f"Export matches scene ({exported_angle:.1f}°)")
                        logger.info(f"PASS: Exported value {exported_angle:.1f}° matches scene")
                    elif diff < 5.0:  # Within 5 degrees
                        score += int(w_file_valid * 0.7)
                        feedback_parts.append(f"Export close to scene ({exported_angle:.1f}° vs {angle_in_scene:.1f}°)")
                        logger.info(f"PARTIAL: Exported value differs by {diff:.1f}°")
                    else:
                        score += int(w_file_valid * 0.3)
                        feedback_parts.append(f"Export differs from scene")
                        logger.info(f"PARTIAL: Exported value {exported_angle:.1f}° differs significantly")
                else:
                    # No scene value to compare, but file has valid angle
                    score += int(w_file_valid * 0.8)
                    feedback_parts.append(f"Valid export ({exported_angle:.1f}°)")
                    logger.info(f"PARTIAL: Valid exported angle but no scene comparison")
            else:
                feedback_parts.append(f"Export invalid ({exported_angle:.1f}°)")
                logger.info(f"FAIL: Exported angle {exported_angle:.1f}° out of range")
        except ValueError:
            feedback_parts.append(f"Export not numeric: '{output_file_value}'")
            logger.info(f"FAIL: Could not parse exported value")
    else:
        if output_file_exists:
            feedback_parts.append("Export file empty")
            logger.info("FAIL: Output file is empty")
    
    # ============================================================
    # CRITERION 7: VLM confirmation (5 points)
    # ============================================================
    # Use trajectory frames to verify the agent actually interacted with Slicer
    # and that angle annotation is visible
    
    query_vlm = env_info.get('query_vlm')
    vlm_passed = False
    
    if query_vlm:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Get trajectory frames for process verification
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            if frames or final_frame:
                all_frames = (frames or []) + ([final_frame] if final_frame else [])
                
                vlm_prompt = """Analyze these screenshots from a 3D Slicer medical imaging session.

The task was to create an ANGLE measurement using the Markups module.
An angle measurement in Slicer shows:
- Three connected points forming a V-shape or angle
- An angle value displayed (in degrees)
- Yellow/colored marker points

Look for evidence of:
1. Is 3D Slicer visible with a brain MRI scan loaded?
2. Are there any angle annotations visible (3 points connected by lines)?
3. Is there an angle measurement value shown anywhere?

Respond in JSON format:
{
    "slicer_visible": true/false,
    "brain_scan_loaded": true/false,
    "angle_annotation_visible": true/false,
    "angle_value_visible": true/false,
    "confidence": "low"/"medium"/"high"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=all_frames[-3:])  # Use last 3 frames
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    slicer_visible = parsed.get('slicer_visible', False)
                    angle_visible = parsed.get('angle_annotation_visible', False)
                    
                    if slicer_visible and angle_visible:
                        score += w_vlm
                        vlm_passed = True
                        feedback_parts.append("VLM: angle visible")
                        logger.info("PASS: VLM confirms angle annotation visible")
                    elif slicer_visible:
                        score += int(w_vlm * 0.5)
                        feedback_parts.append("VLM: Slicer visible, angle unclear")
                        logger.info("PARTIAL: VLM sees Slicer but angle unclear")
                    else:
                        feedback_parts.append("VLM: verification unclear")
                        logger.info("FAIL: VLM could not verify")
        except ImportError:
            logger.warning("VLM utilities not available")
            feedback_parts.append("VLM: unavailable")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            feedback_parts.append("VLM: error")
    else:
        feedback_parts.append("VLM: not available")
    
    # ============================================================
    # FINAL SCORING
    # ============================================================
    
    # Key criteria for passing
    key_criteria_met = (
        angle_markup_exists and
        num_control_points >= 3 and
        angle_in_scene is not None and
        valid_angle_min <= (angle_in_scene or 0) <= valid_angle_max
    )
    
    # Pass threshold: 70 points AND key criteria
    passed = score >= 70 and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    logger.info(f"Final score: {score}/100, passed: {passed}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }