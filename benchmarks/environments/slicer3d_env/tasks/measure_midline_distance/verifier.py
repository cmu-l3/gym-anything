#!/usr/bin/env python3
"""
Verifier for Measure Tumor-to-Midline Distance task.

VERIFICATION STRATEGY (Hybrid: Programmatic + VLM):

Programmatic checks (90 points):
  1. Line annotation exists (30 pts) - A line markup was created
  2. Endpoint near midline (20 pts) - One endpoint has x ≈ 0 (RAS)
  3. Endpoint near tumor (15 pts) - One endpoint is near tumor region
  4. Distance plausible (10 pts) - Measurement in reasonable range
  5. Distance matches ground truth (15 pts) - Within tolerance of computed GT

VLM check (10 points):
  6. Screenshot verification (10 pts) - Screenshot shows line annotation

Pass threshold: 60 points with line_annotation_exists
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_midline_distance(traj, env_info, task_info):
    """
    Verify that the agent correctly measured tumor-to-midline distance.

    Uses multi-criteria scoring with anatomical plausibility checks.
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
    midline_tolerance = metadata.get('midline_tolerance_mm', 10.0)
    tumor_tolerance = metadata.get('tumor_proximity_tolerance_mm', 15.0)
    distance_tolerance = metadata.get('distance_tolerance_mm', 15.0)
    plausible_range = metadata.get('plausible_distance_range_mm', {"min": 2.0, "max": 100.0})

    weights = metadata.get('scoring_weights', {})
    w_line_exists = weights.get('line_annotation_exists', 30)
    w_midline = weights.get('endpoint_near_midline', 20)
    w_tumor = weights.get('endpoint_near_tumor', 15)
    w_plausible = weights.get('distance_plausible', 10)
    w_matches_gt = weights.get('distance_matches_gt', 15)
    w_screenshot = weights.get('screenshot_saved', 10)

    # Initialize scoring
    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # LOAD TASK RESULT FROM CONTAINER
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/midline_task_result.json", temp_result.name)
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

    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # ================================================================
    # LOAD GROUND TRUTH
    # ================================================================
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    gt_data = {}
    try:
        copy_from_env("/tmp/midline_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to load ground truth: {e}")
        details['gt_load_error'] = str(e)
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    gt_distance = gt_data.get('min_distance_to_midline_mm', 0)
    gt_tumor_center = gt_data.get('tumor_center_ras', [0, 0, 0])
    gt_closest_point = gt_data.get('closest_tumor_point_ras', [0, 0, 0])
    gt_computed = gt_data.get('computed', False)

    details['gt_distance_mm'] = gt_distance
    details['gt_tumor_center'] = gt_tumor_center
    details['gt_closest_point'] = gt_closest_point

    # ================================================================
    # CRITERION 1: Line annotation exists (30 points)
    # ================================================================
    line_exists = result.get('line_annotation_exists', False)
    num_lines = result.get('num_line_nodes', 0)

    if line_exists and num_lines > 0:
        score += w_line_exists
        feedback_parts.append(f"Line annotation created ({num_lines} line(s))")
        details['line_exists'] = True
    else:
        feedback_parts.append("No line annotation found")
        details['line_exists'] = False
        # Without a line, we can't verify much else
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # EXTRACT LINE DATA
    # ================================================================
    line_length = result.get('line_length_mm', 0)
    endpoint1 = result.get('endpoint1_ras', [0, 0, 0])
    endpoint2 = result.get('endpoint2_ras', [0, 0, 0])

    # Handle string format if needed
    if isinstance(endpoint1, str):
        try:
            endpoint1 = json.loads(endpoint1)
        except:
            endpoint1 = [0, 0, 0]
    if isinstance(endpoint2, str):
        try:
            endpoint2 = json.loads(endpoint2)
        except:
            endpoint2 = [0, 0, 0]

    # Convert to floats
    try:
        line_length = float(line_length)
        endpoint1 = [float(x) for x in endpoint1]
        endpoint2 = [float(x) for x in endpoint2]
    except (ValueError, TypeError) as e:
        logger.warning(f"Error parsing line data: {e}")
        endpoint1 = [0, 0, 0]
        endpoint2 = [0, 0, 0]
        line_length = 0

    details['measured_length_mm'] = line_length
    details['endpoint1_ras'] = endpoint1
    details['endpoint2_ras'] = endpoint2

    # ================================================================
    # CRITERION 2: One endpoint near midline (20 points)
    # Midline is at x ≈ 0 in RAS coordinates
    # ================================================================
    dist_to_midline_1 = abs(endpoint1[0])  # x-coordinate
    dist_to_midline_2 = abs(endpoint2[0])
    min_dist_to_midline = min(dist_to_midline_1, dist_to_midline_2)

    details['endpoint1_dist_to_midline_mm'] = dist_to_midline_1
    details['endpoint2_dist_to_midline_mm'] = dist_to_midline_2

    if min_dist_to_midline <= midline_tolerance:
        score += w_midline
        feedback_parts.append(f"Endpoint on midline (x={min_dist_to_midline:.1f}mm from x=0)")
        details['midline_endpoint_valid'] = True
    elif min_dist_to_midline <= midline_tolerance * 2:
        score += w_midline // 2
        feedback_parts.append(f"Endpoint near midline (x={min_dist_to_midline:.1f}mm)")
        details['midline_endpoint_valid'] = "partial"
    else:
        feedback_parts.append(f"No endpoint on midline (min dist={min_dist_to_midline:.1f}mm)")
        details['midline_endpoint_valid'] = False

    # ================================================================
    # CRITERION 3: One endpoint near tumor (15 points)
    # ================================================================
    if gt_computed and gt_closest_point != [0, 0, 0]:
        # Calculate distance from each endpoint to the closest tumor point
        def euclidean_dist(p1, p2):
            return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))

        dist_to_tumor_1 = euclidean_dist(endpoint1, gt_closest_point)
        dist_to_tumor_2 = euclidean_dist(endpoint2, gt_closest_point)

        # Also check distance to tumor center
        dist_to_center_1 = euclidean_dist(endpoint1, gt_tumor_center)
        dist_to_center_2 = euclidean_dist(endpoint2, gt_tumor_center)

        min_dist_to_tumor = min(dist_to_tumor_1, dist_to_tumor_2)
        min_dist_to_center = min(dist_to_center_1, dist_to_center_2)

        details['endpoint1_dist_to_tumor_mm'] = dist_to_tumor_1
        details['endpoint2_dist_to_tumor_mm'] = dist_to_tumor_2

        # The endpoint should be near the tumor (but not necessarily exactly at the closest point)
        # Allow some tolerance since agent may choose a slightly different point
        if min_dist_to_tumor <= tumor_tolerance:
            score += w_tumor
            feedback_parts.append(f"Endpoint near tumor edge ({min_dist_to_tumor:.1f}mm)")
            details['tumor_endpoint_valid'] = True
        elif min_dist_to_center <= tumor_tolerance * 3:
            # Within reasonable range of tumor
            score += w_tumor // 2
            feedback_parts.append(f"Endpoint in tumor region ({min_dist_to_center:.1f}mm from center)")
            details['tumor_endpoint_valid'] = "partial"
        else:
            feedback_parts.append(f"Endpoint not near tumor")
            details['tumor_endpoint_valid'] = False
    else:
        # Can't verify without ground truth
        feedback_parts.append("Tumor proximity check skipped (no GT)")
        details['tumor_endpoint_valid'] = "unknown"

    # ================================================================
    # CRITERION 4: Distance is plausible (10 points)
    # ================================================================
    min_plausible = plausible_range.get('min', 2.0)
    max_plausible = plausible_range.get('max', 100.0)

    if min_plausible <= line_length <= max_plausible:
        score += w_plausible
        feedback_parts.append(f"Distance plausible ({line_length:.1f}mm)")
        details['distance_plausible'] = True
    elif line_length > 0:
        score += w_plausible // 2
        feedback_parts.append(f"Distance outside typical range ({line_length:.1f}mm)")
        details['distance_plausible'] = "partial"
    else:
        feedback_parts.append(f"Invalid distance ({line_length}mm)")
        details['distance_plausible'] = False

    # ================================================================
    # CRITERION 5: Distance matches ground truth (15 points)
    # ================================================================
    if gt_computed and gt_distance > 0:
        distance_error = abs(line_length - gt_distance)
        details['distance_error_mm'] = distance_error

        if distance_error <= distance_tolerance:
            score += w_matches_gt
            feedback_parts.append(f"Distance matches GT ({line_length:.1f} vs {gt_distance:.1f}mm)")
            details['matches_gt'] = True
        elif distance_error <= distance_tolerance * 2:
            score += w_matches_gt // 2
            feedback_parts.append(f"Distance close to GT (error={distance_error:.1f}mm)")
            details['matches_gt'] = "partial"
        else:
            feedback_parts.append(f"Distance differs from GT (error={distance_error:.1f}mm)")
            details['matches_gt'] = False
    else:
        feedback_parts.append("GT comparison skipped")
        details['matches_gt'] = "unknown"

    # ================================================================
    # CRITERION 6: Screenshot saved (10 points)
    # ================================================================
    screenshot_exists = result.get('user_screenshot_exists', False)
    screenshot_created = result.get('user_screenshot_created_during_task', False)
    screenshot_size = result.get('user_screenshot_size_kb', 0)

    if screenshot_exists and screenshot_created and screenshot_size > 50:
        score += w_screenshot
        feedback_parts.append(f"Screenshot saved ({screenshot_size}KB)")
        details['screenshot_valid'] = True
    elif screenshot_exists and screenshot_size > 20:
        score += w_screenshot // 2
        feedback_parts.append("Screenshot exists (may be pre-existing)")
        details['screenshot_valid'] = "partial"
    elif result.get('new_screenshots_count', 0) > 0:
        score += w_screenshot // 2
        feedback_parts.append("New screenshot(s) created")
        details['screenshot_valid'] = "partial"
    else:
        feedback_parts.append("No screenshot saved")
        details['screenshot_valid'] = False

    # ================================================================
    # VLM VERIFICATION (Optional bonus)
    # ================================================================
    vlm_verified = False
    query_vlm = env_info.get('query_vlm')

    if query_vlm and traj:
        try:
            # Try to get trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

            frames = sample_trajectory_frames(traj, n=3)
            final = get_final_screenshot(traj)

            if frames or final:
                images = (frames or []) + ([final] if final else [])

                vlm_prompt = """Analyze these screenshots from 3D Slicer showing a brain MRI.

The task was to measure the distance from a brain tumor to the brain's midline using a line/ruler tool.

Check for:
1. Is a LINE ANNOTATION visible? (A ruler/measurement line between two points)
2. Does one end of the line appear to be on a bright tumor region?
3. Does the other end appear to be at the center (midline) of the brain?
4. Is a distance measurement displayed?

Respond in JSON:
{
    "line_visible": true/false,
    "line_connects_tumor_to_midline": true/false,
    "measurement_displayed": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}
"""
                vlm_result = query_vlm(prompt=vlm_prompt, images=images)

                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed

                    if parsed.get('line_visible') and parsed.get('line_connects_tumor_to_midline'):
                        vlm_verified = True
                        details['vlm_verified'] = True
                    else:
                        details['vlm_verified'] = False

        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)

    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_line_exists + w_midline + w_tumor + w_plausible + w_matches_gt + w_screenshot

    # Determine pass/fail
    # Key criteria: line exists + reasonable measurement
    key_criteria_met = (
        details.get('line_exists', False) and
        (details.get('midline_endpoint_valid', False) in [True, "partial"]) and
        details.get('distance_plausible', False) in [True, "partial"]
    )

    passed = score >= 60 and key_criteria_met

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }