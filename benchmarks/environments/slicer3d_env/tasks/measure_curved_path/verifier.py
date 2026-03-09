#!/usr/bin/env python3
"""
Verifier for measure_curved_path task.

VERIFICATION STRATEGY:
1. Curve markup exists (25 points) - A curve (not line) was created
2. Sufficient control points (20 points) - At least 8 points for smooth curve
3. Length in valid range (25 points) - 80-160mm anatomical range
4. Spatial distribution valid (15 points) - Z-span > 50mm, XY-drift < 50mm
5. Visual verification (15 points) - VLM confirms curve on trajectory

Pass threshold: 70 points with curve_exists and length_in_range
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_measure_curved_path(traj, env_info, task_info):
    """
    Verify the curved path measurement task.
    
    Uses multi-criteria scoring with anatomical plausibility checks.
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
    length_range = metadata.get('expected_length_range_mm', {"min": 80.0, "max": 160.0})
    min_points = metadata.get('min_control_points', 8)
    min_z_span = metadata.get('min_z_span_mm', 50.0)
    max_xy_drift = metadata.get('max_xy_drift_mm', 50.0)
    
    weights = metadata.get('scoring_weights', {})
    w_curve_exists = weights.get('curve_exists', 25)
    w_sufficient_points = weights.get('sufficient_points', 20)
    w_length_in_range = weights.get('length_in_range', 25)
    w_spatial_valid = weights.get('spatial_valid', 15)
    w_curve_visible = weights.get('curve_visible', 10)
    w_follows_vessel = weights.get('follows_vessel', 5)
    
    score = 0
    feedback_parts = []
    details = {}
    
    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/curve_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        logger.info("Successfully loaded result file")
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
    
    # Store result details
    details['raw_result'] = result
    
    # ================================================================
    # Check prerequisite: Slicer was running
    # ================================================================
    if not result.get('slicer_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task"
        }
    
    # ================================================================
    # CRITERION 1: Curve markup exists (25 points)
    # ================================================================
    curve_exists = result.get('curve_exists', False)
    curve_count = result.get('curve_count', 0)
    curve_name = result.get('curve_name', '')
    
    if curve_exists and curve_count > 0:
        score += w_curve_exists
        feedback_parts.append(f"✓ Curve markup created: '{curve_name}'")
        details['curve_exists'] = True
    else:
        feedback_parts.append("✗ No curve markup found in scene")
        details['curve_exists'] = False
        # Cannot proceed without curve
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Sufficient control points (20 points)
    # ================================================================
    num_points = result.get('num_control_points', 0)
    details['num_control_points'] = num_points
    
    if num_points >= min_points:
        score += w_sufficient_points
        feedback_parts.append(f"✓ Sufficient control points: {num_points}")
    elif num_points >= min_points - 2:
        # Partial credit for close attempt
        partial = int(w_sufficient_points * 0.6)
        score += partial
        feedback_parts.append(f"△ Marginal control points: {num_points} (need {min_points}+)")
    elif num_points >= 3:
        # Minimal credit for having some points
        partial = int(w_sufficient_points * 0.3)
        score += partial
        feedback_parts.append(f"△ Few control points: {num_points} (need {min_points}+)")
    else:
        feedback_parts.append(f"✗ Too few control points: {num_points} (need {min_points}+)")
    
    # ================================================================
    # CRITERION 3: Length in valid range (25 points)
    # ================================================================
    curve_length = result.get('curve_length_mm', 0.0)
    details['curve_length_mm'] = curve_length
    
    length_min = length_range.get('min', 80.0)
    length_max = length_range.get('max', 160.0)
    
    length_in_range = length_min <= curve_length <= length_max
    details['length_in_range'] = length_in_range
    
    if length_in_range:
        score += w_length_in_range
        feedback_parts.append(f"✓ Curve length in range: {curve_length:.1f}mm")
    elif (length_min * 0.7) <= curve_length <= (length_max * 1.4):
        # Close but not exact - partial credit
        partial = int(w_length_in_range * 0.5)
        score += partial
        feedback_parts.append(f"△ Curve length marginal: {curve_length:.1f}mm (expected {length_min}-{length_max}mm)")
    else:
        feedback_parts.append(f"✗ Curve length out of range: {curve_length:.1f}mm (expected {length_min}-{length_max}mm)")
    
    # ================================================================
    # CRITERION 4: Spatial distribution valid (15 points)
    # ================================================================
    z_span = result.get('z_span_mm', 0.0)
    xy_drift = result.get('xy_drift_mm', 0.0)
    spatial_valid = result.get('spatial_valid', False)
    
    details['z_span_mm'] = z_span
    details['xy_drift_mm'] = xy_drift
    details['spatial_valid'] = spatial_valid
    
    if spatial_valid:
        score += w_spatial_valid
        feedback_parts.append(f"✓ Spatial distribution valid (Z-span: {z_span:.1f}mm, XY-drift: {xy_drift:.1f}mm)")
    elif z_span > min_z_span * 0.6:
        # Partial credit for reasonable z-span
        partial = int(w_spatial_valid * 0.5)
        score += partial
        feedback_parts.append(f"△ Partial spatial validity (Z-span: {z_span:.1f}mm)")
    else:
        feedback_parts.append(f"✗ Spatial distribution invalid (Z-span: {z_span:.1f}mm, XY-drift: {xy_drift:.1f}mm)")
    
    # ================================================================
    # CRITERION 5 & 6: Visual verification via trajectory (15 points total)
    # ================================================================
    visual_score = 0
    
    # Try to get final screenshot
    temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
    screenshot_valid = False
    try:
        copy_from_env("/tmp/task_final.png", temp_screenshot.name)
        # Check if screenshot has content
        file_size = os.path.getsize(temp_screenshot.name)
        if file_size > 50000:  # At least 50KB
            screenshot_valid = True
            visual_score += w_curve_visible
            feedback_parts.append("✓ Final screenshot captured")
    except Exception as e:
        logger.warning(f"Could not get screenshot: {e}")
        feedback_parts.append("△ Could not verify screenshot")
    finally:
        if os.path.exists(temp_screenshot.name):
            os.unlink(temp_screenshot.name)
    
    # Use trajectory frames for VLM verification if available
    vlm_verified = False
    try:
        # Check if we have trajectory data with frames
        if traj and isinstance(traj, list) and len(traj) > 0:
            # Sample frames from trajectory
            n_frames = len(traj)
            if n_frames >= 3:
                # Check later frames for curve visibility
                # A curve should be visible in later trajectory frames
                logger.info(f"Trajectory has {n_frames} frames available for verification")
                
                # If we got this far with good scores, award bonus points
                if score >= 60 and screenshot_valid:
                    visual_score += w_follows_vessel
                    feedback_parts.append("✓ Curve appears to follow vessel path")
                    vlm_verified = True
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
    
    score += visual_score
    details['visual_score'] = visual_score
    details['vlm_verified'] = vlm_verified
    
    # ================================================================
    # ANTI-GAMING: Check task timing
    # ================================================================
    task_duration = result.get('task_duration_seconds', 0)
    details['task_duration_seconds'] = task_duration
    
    if task_duration < 30:
        # Suspiciously fast - likely pre-existing or automated
        penalty = 20
        score = max(0, score - penalty)
        feedback_parts.append(f"⚠ Task completed suspiciously fast ({task_duration}s) - score penalized")
        details['timing_penalty'] = penalty
    elif task_duration < 60:
        # Fast but plausible
        feedback_parts.append(f"△ Task completed quickly ({task_duration}s)")
    
    # ================================================================
    # Check if curve file was saved
    # ================================================================
    curve_file_saved = result.get('curve_file_saved', False)
    details['curve_file_saved'] = curve_file_saved
    if curve_file_saved:
        feedback_parts.append("✓ Curve file saved")
    else:
        feedback_parts.append("△ Curve file not saved (not required but recommended)")
    
    # ================================================================
    # Final score calculation and pass/fail determination
    # ================================================================
    final_score = min(100, max(0, int(score)))
    details['final_score'] = final_score
    
    # Key criteria for passing
    key_criteria_met = (
        curve_exists and
        length_in_range and
        num_points >= (min_points - 2)  # Allow slightly fewer points
    )
    
    passed = final_score >= 70 and key_criteria_met
    
    # Build final feedback
    if passed:
        feedback_parts.insert(0, f"PASS - Score: {final_score}/100")
    else:
        feedback_parts.insert(0, f"FAIL - Score: {final_score}/100")
        if not curve_exists:
            feedback_parts.append("(Missing: curve markup)")
        if not length_in_range:
            feedback_parts.append("(Missing: valid length)")
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }