#!/usr/bin/env python3
"""
Verifier for Create Closed Curve ROI task.

VERIFICATION STRATEGY (Multi-criteria with anti-gaming):

1. Closed Curve Exists (25 points)
   - A MarkupsClosedCurve node exists in the scene
   - Must be created during the task (not pre-existing)

2. Minimum Control Points (20 points)
   - Curve has at least 10 control points
   - Partial credit for 5-9 points

3. Proper Naming (10 points)
   - Curve name contains 'GTV', 'Tumor', or 'Margin'

4. Curve Location Valid (25 points)
   - Curve centroid is within tumor region bounds
   - Uses ground truth tumor location for verification

5. VLM Shape Quality (15 points)
   - Uses trajectory frames to verify work progression
   - Final frame shows closed curve on tumor

6. Curve Is Closed (5 points)
   - Verifies it's actually a closed curve (not open)

Pass threshold: 70 points AND key criteria (closed_curve_exists + curve_location_valid)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _calculate_distance_3d(p1, p2):
    """Calculate Euclidean distance between two 3D points."""
    return math.sqrt(sum((a - b)**2 for a, b in zip(p1, p2)))


def _point_in_bbox(point, bbox_min, bbox_max, tolerance=0):
    """Check if a point is within a bounding box (with optional tolerance)."""
    for i in range(3):
        if point[i] < bbox_min[i] - tolerance or point[i] > bbox_max[i] + tolerance:
            return False
    return True


def verify_closed_curve_roi(traj, env_info, task_info):
    """
    Verify that a closed curve ROI was created around the tumor margin.
    
    Uses multiple independent verification signals to prevent gaming.
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
    min_control_points = metadata.get('min_control_points', 10)
    name_patterns = metadata.get('expected_curve_name_patterns', 
                                  ['GTV', 'Tumor', 'Margin', 'tumor', 'gtv', 'margin'])
    location_tolerance = metadata.get('curve_location_tolerance_mm', 30)
    
    weights = metadata.get('scoring_weights', {})
    w_exists = weights.get('closed_curve_exists', 25)
    w_points = weights.get('min_control_points', 20)
    w_naming = weights.get('proper_naming', 10)
    w_location = weights.get('curve_location_valid', 25)
    w_vlm = weights.get('vlm_shape_quality', 15)
    w_closed = weights.get('curve_is_closed', 5)

    pass_threshold = metadata.get('pass_threshold', 70)
    
    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # COPY RESULT FILE FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/closed_curve_result.json", temp_result.name)
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

    # Check Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    details['slicer_running'] = True

    # ================================================================
    # CRITERION 1: CLOSED CURVE EXISTS (25 points)
    # ================================================================
    closed_curve_exists = result.get('closed_curve_exists', False)
    curve_created_during_task = result.get('curve_created_during_task', False)
    
    if closed_curve_exists:
        if curve_created_during_task:
            score += w_exists
            feedback_parts.append("Closed curve created")
        else:
            # Curve exists but might be pre-existing (partial credit)
            score += w_exists * 0.5
            feedback_parts.append("Closed curve exists (may be pre-existing)")
        details['closed_curve_exists'] = True
    else:
        feedback_parts.append("No closed curve found")
        details['closed_curve_exists'] = False
        # Without a closed curve, we can't verify much else
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: MINIMUM CONTROL POINTS (20 points)
    # ================================================================
    control_point_count = result.get('control_point_count', 0)
    details['control_point_count'] = control_point_count
    
    if control_point_count >= min_control_points:
        score += w_points
        feedback_parts.append(f"{control_point_count} control points (≥{min_control_points})")
    elif control_point_count >= min_control_points * 0.5:  # 5+ points
        partial = (control_point_count / min_control_points) * w_points
        score += partial
        feedback_parts.append(f"{control_point_count} points (partial credit)")
    elif control_point_count >= 3:
        score += w_points * 0.25
        feedback_parts.append(f"Only {control_point_count} points (minimum for curve)")
    else:
        feedback_parts.append(f"Too few points ({control_point_count})")

    # ================================================================
    # CRITERION 3: PROPER NAMING (10 points)
    # ================================================================
    curve_name = result.get('curve_name', '')
    details['curve_name'] = curve_name
    
    name_match = any(pattern.lower() in curve_name.lower() for pattern in name_patterns)
    if name_match:
        score += w_naming
        feedback_parts.append(f"Proper name: '{curve_name}'")
    else:
        feedback_parts.append(f"Name '{curve_name}' doesn't match expected patterns")

    # ================================================================
    # CRITERION 4: CURVE LOCATION VALID (25 points)
    # ================================================================
    curve_centroid = result.get('curve_centroid_ras', [0, 0, 0])
    tumor_centroid = result.get('tumor_centroid_ras', [0, 0, 0])
    tumor_bbox_min = result.get('tumor_bbox_min_ras', [0, 0, 0])
    tumor_bbox_max = result.get('tumor_bbox_max_ras', [0, 0, 0])
    tumor_exists = result.get('tumor_exists', False)
    
    details['curve_centroid_ras'] = curve_centroid
    details['tumor_centroid_ras'] = tumor_centroid
    
    location_valid = False
    if tumor_exists and any(c != 0 for c in tumor_centroid):
        # Calculate distance from curve centroid to tumor centroid
        distance_to_tumor = _calculate_distance_3d(curve_centroid, tumor_centroid)
        details['distance_to_tumor_center_mm'] = distance_to_tumor
        
        # Check if curve centroid is within tumor bounding box (with tolerance)
        in_bbox = _point_in_bbox(curve_centroid, tumor_bbox_min, tumor_bbox_max, 
                                  tolerance=location_tolerance)
        
        # Also check if within reasonable distance of tumor center
        within_distance = distance_to_tumor < location_tolerance * 2
        
        if in_bbox:
            score += w_location
            feedback_parts.append(f"Curve location valid (in tumor region)")
            location_valid = True
        elif within_distance:
            score += w_location * 0.7
            feedback_parts.append(f"Curve near tumor ({distance_to_tumor:.1f}mm from center)")
            location_valid = True
        else:
            feedback_parts.append(f"Curve too far from tumor ({distance_to_tumor:.1f}mm)")
    else:
        # No ground truth available, use heuristics
        # Check if curve is in a plausible brain location (center of image)
        if all(-100 < c < 100 for c in curve_centroid):
            score += w_location * 0.5
            feedback_parts.append("Curve in plausible location (no ground truth)")
            location_valid = True
        else:
            feedback_parts.append("Cannot verify curve location")
    
    details['location_valid'] = location_valid

    # ================================================================
    # CRITERION 5: VLM SHAPE QUALITY (15 points)
    # Uses trajectory frames to verify work progression
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    
    if query_vlm and traj:
        try:
            # Get trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            
            # Sample frames across the trajectory to verify work progression
            trajectory_frames = sample_trajectory_frames(traj, n=4)
            final_screenshot = get_final_screenshot(traj)
            
            if final_screenshot:
                # VLM prompt for trajectory verification
                trajectory_prompt = """You are analyzing screenshots from a medical imaging task in 3D Slicer.

The task was to create a closed curve annotation around a brain tumor.

Analyze these images (from earliest to latest in the workflow):

1. CURVE_VISIBLE: Is there a closed curve (colored line forming a loop) visible on the brain scan in the later images?
2. CURVE_ON_TUMOR: Does the curve appear to outline a distinct region (the tumor, typically a bright area on the brain scan)?
3. WORK_PROGRESSION: Do the images show progression from no annotation to having a curve drawn?
4. REASONABLE_SHAPE: Does the curve have a reasonable tumor-like shape (roughly oval/irregular, not a tiny triangle)?

Respond in JSON:
{
    "curve_visible": true/false,
    "curve_on_tumor": true/false,
    "work_progression": true/false,
    "reasonable_shape": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
                
                # Combine trajectory frames with final screenshot
                all_frames = (trajectory_frames or []) + [final_screenshot]
                
                vlm_result = query_vlm(prompt=trajectory_prompt, images=all_frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    curve_visible = parsed.get('curve_visible', False)
                    curve_on_tumor = parsed.get('curve_on_tumor', False)
                    work_progression = parsed.get('work_progression', False)
                    reasonable_shape = parsed.get('reasonable_shape', False)
                    
                    # Score based on VLM verification
                    if curve_visible:
                        vlm_score += w_vlm * 0.4
                    if curve_on_tumor:
                        vlm_score += w_vlm * 0.3
                    if reasonable_shape:
                        vlm_score += w_vlm * 0.2
                    if work_progression:
                        vlm_score += w_vlm * 0.1
                    
                    if vlm_score > 0:
                        feedback_parts.append(f"VLM: curve verified ({vlm_score:.0f}pts)")
                    else:
                        feedback_parts.append("VLM: curve not verified visually")
                else:
                    logger.warning("VLM query failed or returned no result")
                    details['vlm_error'] = vlm_result.get('error', 'Unknown error') if vlm_result else 'No result'
            else:
                logger.warning("No final screenshot available for VLM")
                
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    else:
        logger.info("VLM not available or no trajectory")
    
    score += vlm_score
    details['vlm_score'] = vlm_score

    # ================================================================
    # CRITERION 6: CURVE IS CLOSED (5 points)
    # ================================================================
    curve_is_closed = result.get('curve_is_closed', False)
    
    if curve_is_closed:
        score += w_closed
        feedback_parts.append("Curve is closed")
    else:
        feedback_parts.append("Curve not properly closed")
    
    details['curve_is_closed'] = curve_is_closed

    # ================================================================
    # ADDITIONAL METRICS
    # ================================================================
    details['curve_perimeter_mm'] = result.get('curve_perimeter_mm', 0)
    details['curve_area_mm2'] = result.get('curve_area_mm2', 0)
    details['curve_z_coord'] = result.get('curve_z_coord', 0)
    details['all_curves_count'] = len(result.get('all_curves', []))

    # ================================================================
    # FINAL SCORING
    # ================================================================
    score = int(score)
    
    # Key criteria check
    key_criteria_met = closed_curve_exists and location_valid
    
    # Determine pass/fail
    passed = score >= pass_threshold and key_criteria_met
    
    feedback = " | ".join(feedback_parts)
    
    # Add summary to feedback
    if passed:
        feedback = f"PASSED ({score}/100): {feedback}"
    else:
        if not key_criteria_met:
            feedback = f"FAILED (key criteria not met, {score}/100): {feedback}"
        else:
            feedback = f"FAILED ({score}/100 < {pass_threshold}): {feedback}"

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }