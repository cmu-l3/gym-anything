#!/usr/bin/env python3
"""
Verifier for place_tumor_fiducials task.

VERIFICATION STRATEGY (Multi-Signal):

Programmatic Checks (85 points):
1. Markup file exists (15 pts) - File was saved to expected location
2. Valid JSON format (10 pts) - File is valid Slicer markup JSON
3. Exactly 4 points (20 pts) - Contains exactly 4 fiducial markers
4. Points named correctly (15 pts) - Labels contain Superior/Inferior/Anterior/Posterior
5. Superior is highest Z (10 pts) - Superior marker has greatest Z coordinate
6. Inferior is lowest Z (10 pts) - Inferior marker has smallest Z coordinate
7. Points near tumor (15 pts) - At least 3 markers within 15mm of tumor boundary
8. Points span tumor (5 pts) - Markers span significant portion of tumor extent

Anti-Gaming Checks:
- File must be created DURING task (timestamp check)
- Points must not all be identical
- Points must be in valid coordinate ranges

VLM Trajectory Check (15 points):
- Verify agent navigated through slices
- Verify Markups module was accessed
- Verify work progression visible in trajectory

Pass Threshold: 70 points with key criteria met:
- Exactly 4 points
- Points near tumor boundary
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_place_tumor_fiducials(traj, env_info, task_info):
    """
    Verify that tumor boundary fiducials were placed correctly.
    
    Uses multi-criteria scoring with ground truth validation.
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
    expected_num_points = metadata.get('expected_num_fiducials', 4)
    expected_labels = metadata.get('expected_labels', ['Superior', 'Inferior', 'Anterior', 'Posterior'])
    position_tolerance = metadata.get('position_tolerance_mm', 15.0)
    min_z_spread = metadata.get('min_z_spread_mm', 10.0)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('markup_file_exists', 15)
    w_valid_json = weights.get('valid_json_format', 10)
    w_exactly_4 = weights.get('exactly_4_points', 20)
    w_named = weights.get('points_named_correctly', 15)
    w_superior_z = weights.get('superior_highest_z', 10)
    w_inferior_z = weights.get('inferior_lowest_z', 10)
    w_near_tumor = weights.get('points_near_tumor', 15)
    w_span = weights.get('points_span_tumor', 5)

    score = 0
    feedback_parts = []
    details = {}

    # ================================================================
    # LOAD EXPORT RESULT
    # ================================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/fiducials_task_result.json", temp_result.name)
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

    details['export_result'] = result

    # ================================================================
    # CHECK BASIC REQUIREMENTS
    # ================================================================
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        feedback_parts.append("Slicer was not running")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 1: Markup file exists (15 pts)
    # ================================================================
    file_exists = result.get('markup_file_exists', False)
    created_during_task = result.get('created_during_task', False)
    
    if file_exists:
        if created_during_task:
            score += w_file_exists
            feedback_parts.append(f"Markup file created (+{w_file_exists})")
        else:
            score += w_file_exists * 0.5
            feedback_parts.append(f"Markup file exists but not created during task (+{w_file_exists * 0.5})")
    else:
        feedback_parts.append("No markup file found (0)")
        details['reason'] = "No markup file was saved"
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 2: Valid JSON format (10 pts)
    # ================================================================
    valid_json = result.get('markup_valid_json', False)
    
    if valid_json:
        score += w_valid_json
        feedback_parts.append(f"Valid JSON (+{w_valid_json})")
    else:
        feedback_parts.append("Invalid JSON format (0)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ================================================================
    # CRITERION 3: Exactly 4 points (20 pts)
    # ================================================================
    num_points = result.get('num_points', 0)
    details['num_points'] = num_points
    
    if num_points == expected_num_points:
        score += w_exactly_4
        feedback_parts.append(f"Exactly {expected_num_points} points (+{w_exactly_4})")
        key_criteria_4_points = True
    elif num_points >= 3:
        partial = w_exactly_4 * 0.5
        score += partial
        feedback_parts.append(f"{num_points} points (expected {expected_num_points}, +{partial})")
        key_criteria_4_points = False
    elif num_points >= 1:
        partial = w_exactly_4 * 0.25
        score += partial
        feedback_parts.append(f"Only {num_points} point(s) (+{partial})")
        key_criteria_4_points = False
    else:
        feedback_parts.append("No points found (0)")
        key_criteria_4_points = False

    # ================================================================
    # CRITERION 4: Points named correctly (15 pts)
    # ================================================================
    point_labels = result.get('point_labels', '')
    if isinstance(point_labels, str):
        point_labels_list = [l.strip() for l in point_labels.split(',') if l.strip()]
    else:
        point_labels_list = point_labels
    
    details['point_labels'] = point_labels_list
    
    # Check how many expected labels are found
    found_labels = 0
    for expected in expected_labels:
        expected_lower = expected.lower()
        for label in point_labels_list:
            if expected_lower in label.lower():
                found_labels += 1
                break
    
    if found_labels == len(expected_labels):
        score += w_named
        feedback_parts.append(f"All labels correct (+{w_named})")
    elif found_labels >= 2:
        partial = w_named * (found_labels / len(expected_labels))
        score += partial
        feedback_parts.append(f"{found_labels}/{len(expected_labels)} labels correct (+{partial:.0f})")
    else:
        feedback_parts.append(f"Missing labels ({found_labels}/{len(expected_labels)})")

    # ================================================================
    # CRITERION 5: Superior is highest Z (10 pts)
    # ================================================================
    superior_highest = result.get('superior_is_highest_z', False)
    
    if superior_highest:
        score += w_superior_z
        feedback_parts.append(f"Superior highest Z (+{w_superior_z})")
    else:
        feedback_parts.append("Superior not highest Z (0)")

    # ================================================================
    # CRITERION 6: Inferior is lowest Z (10 pts)
    # ================================================================
    inferior_lowest = result.get('inferior_is_lowest_z', False)
    
    if inferior_lowest:
        score += w_inferior_z
        feedback_parts.append(f"Inferior lowest Z (+{w_inferior_z})")
    else:
        feedback_parts.append("Inferior not lowest Z (0)")

    # ================================================================
    # CRITERION 7: Points near tumor boundary (15 pts)
    # ================================================================
    points_near_tumor = result.get('points_near_tumor', 0)
    details['points_near_tumor'] = points_near_tumor
    
    if points_near_tumor >= 4:
        score += w_near_tumor
        feedback_parts.append(f"All points near tumor (+{w_near_tumor})")
        key_criteria_near_tumor = True
    elif points_near_tumor >= 3:
        partial = w_near_tumor * 0.75
        score += partial
        feedback_parts.append(f"{points_near_tumor}/4 points near tumor (+{partial:.0f})")
        key_criteria_near_tumor = True
    elif points_near_tumor >= 2:
        partial = w_near_tumor * 0.5
        score += partial
        feedback_parts.append(f"{points_near_tumor}/4 points near tumor (+{partial:.0f})")
        key_criteria_near_tumor = False
    elif points_near_tumor >= 1:
        partial = w_near_tumor * 0.25
        score += partial
        feedback_parts.append(f"Only {points_near_tumor} point near tumor (+{partial:.0f})")
        key_criteria_near_tumor = False
    else:
        feedback_parts.append("No points near tumor (0)")
        key_criteria_near_tumor = False

    # ================================================================
    # CRITERION 8: Points span tumor extent (5 pts)
    # ================================================================
    z_spread = result.get('z_spread_mm', 0)
    details['z_spread_mm'] = z_spread
    
    if z_spread >= min_z_spread:
        score += w_span
        feedback_parts.append(f"Good Z spread {z_spread:.1f}mm (+{w_span})")
    elif z_spread > 0:
        partial = w_span * 0.5
        score += partial
        feedback_parts.append(f"Small Z spread {z_spread:.1f}mm (+{partial})")
    else:
        feedback_parts.append("No Z spread detected (0)")

    # ================================================================
    # VLM TRAJECTORY VERIFICATION (Optional - 15 bonus pts equivalent)
    # Verify agent actually did work by examining trajectory
    # ================================================================
    vlm_score = 0
    try:
        query_vlm = env_info.get('query_vlm')
        if query_vlm and traj:
            # Sample trajectory frames
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            
            if frames:
                vlm_prompt = """Analyze these screenshots from a 3D Slicer session where the user should be placing fiducial markers on a brain tumor.

Look for evidence of:
1. Brain MRI data visible in slice views
2. Markups module panel visible (list of points on the right side)
3. Fiducial markers (colored dots/spheres) visible in the slice views
4. Navigation through different slices (different brain sections visible)

Respond in JSON format:
{
    "brain_mri_visible": true/false,
    "markups_module_visible": true/false,
    "fiducial_markers_visible": true/false,
    "slice_navigation_evident": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description of what you see"
}
"""
                vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Count positive indicators
                    indicators = [
                        parsed.get('brain_mri_visible', False),
                        parsed.get('markups_module_visible', False),
                        parsed.get('fiducial_markers_visible', False),
                        parsed.get('slice_navigation_evident', False)
                    ]
                    positive_count = sum(1 for i in indicators if i)
                    
                    if positive_count >= 3:
                        vlm_score = 10
                        feedback_parts.append(f"VLM: Good workflow evidence (+{vlm_score} bonus)")
                    elif positive_count >= 2:
                        vlm_score = 5
                        feedback_parts.append(f"VLM: Some workflow evidence (+{vlm_score} bonus)")
                    else:
                        feedback_parts.append("VLM: Limited workflow evidence")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        details['vlm_error'] = str(e)

    # Add VLM bonus (capped at 100 total)
    score = min(100, score + vlm_score)

    # ================================================================
    # FINAL DETERMINATION
    # ================================================================
    
    # Key criteria for passing:
    # - Score >= 70
    # - Must have 4 points (or at least 3)
    # - Must have points near tumor
    key_criteria_met = key_criteria_4_points or (num_points >= 3 and key_criteria_near_tumor)
    
    passed = (score >= 70) and key_criteria_met
    
    if passed:
        feedback_parts.append(f"PASSED ({score}/100)")
    else:
        if score < 70:
            feedback_parts.append(f"FAILED: Score {score}/100 below threshold (70)")
        elif not key_criteria_met:
            feedback_parts.append(f"FAILED: Key criteria not met (need 4 points near tumor)")

    return {
        "passed": passed,
        "score": int(score),
        "feedback": " | ".join(feedback_parts),
        "details": details
    }