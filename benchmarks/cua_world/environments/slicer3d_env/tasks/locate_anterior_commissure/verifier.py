#!/usr/bin/env python3
"""
Verifier for locate_anterior_commissure task.

VERIFICATION STRATEGY:
1. Fiducial Exists (25 points) - At least one fiducial marker was created
2. Created During Task (15 points) - Scene was modified during task session
3. Within 5mm of AC (35 points) - Fiducial is within 5mm of ground truth AC
4. Within 3mm Precision Bonus (15 points) - High precision placement
5. Midline Placement (10 points) - Fiducial R-coordinate is near 0

Pass threshold: 75 points (requires fiducial exists + within 5mm)
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_locate_anterior_commissure(traj, env_info, task_info):
    """
    Verify that the agent correctly located and marked the anterior commissure.
    
    Uses multi-criteria scoring with anatomical validation.
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
    gt_ac_coords = metadata.get('ground_truth_ac_ras', [0.0, 1.5, -3.0])
    tolerance_5mm = metadata.get('tolerance_5mm', 5.0)
    tolerance_3mm = metadata.get('tolerance_3mm', 3.0)
    midline_tolerance = metadata.get('midline_tolerance_mm', 2.0)
    pass_threshold = metadata.get('pass_threshold', 75)
    
    weights = metadata.get('scoring_weights', {})
    w_fiducial_exists = weights.get('fiducial_exists', 25)
    w_created_during_task = weights.get('created_during_task', 15)
    w_within_5mm = weights.get('within_5mm', 35)
    w_within_3mm = weights.get('within_3mm_bonus', 15)
    w_midline = weights.get('midline_placement', 10)
    
    max_score = w_fiducial_exists + w_created_during_task + w_within_5mm + w_within_3mm + w_midline
    
    # Copy result file from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
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
    details = {
        'ground_truth_ac_ras': gt_ac_coords,
        'tolerance_5mm': tolerance_5mm,
        'tolerance_3mm': tolerance_3mm
    }
    
    # ================================================================
    # CHECK: Slicer was running
    # ================================================================
    if not result.get('slicer_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "3D Slicer was not running - cannot verify task completion",
            "details": details
        }
    details['slicer_running'] = True
    
    # ================================================================
    # CHECK: Volume was loaded
    # ================================================================
    volumes_loaded = result.get('volumes_loaded', 0)
    if volumes_loaded < 1:
        feedback_parts.append("No volume was loaded")
        details['volumes_loaded'] = 0
    else:
        feedback_parts.append(f"Volume loaded ({volumes_loaded})")
        details['volumes_loaded'] = volumes_loaded
    
    # ================================================================
    # CRITERION 1: Fiducial exists (25 points)
    # ================================================================
    fiducials_found = result.get('fiducials_found', False)
    fiducial_count = result.get('fiducial_count', 0)
    fiducials = result.get('fiducials', [])
    
    details['fiducials_found'] = fiducials_found
    details['fiducial_count'] = fiducial_count
    
    if fiducials_found and fiducial_count > 0:
        score += w_fiducial_exists
        feedback_parts.append(f"✓ Fiducial marker created ({fiducial_count} found): +{w_fiducial_exists} points")
        details['criterion_fiducial_exists'] = True
    else:
        feedback_parts.append(f"✗ No fiducial marker was placed: +0 points")
        details['criterion_fiducial_exists'] = False
        # Cannot pass without a fiducial
        return {
            "passed": False,
            "score": score,
            "feedback": f"Score: {score}/{max_score}\n" + "\n".join(feedback_parts) + "\n\n✗ FAILED - No fiducial marker was placed",
            "details": details
        }
    
    # ================================================================
    # CRITERION 2: Created during task (15 points)
    # ================================================================
    # If fiducial exists and was queried from live scene, it was created during session
    task_duration = result.get('task_duration_sec', 0)
    if task_duration > 0 and fiducials_found:
        score += w_created_during_task
        feedback_parts.append(f"✓ Fiducial created during task session ({task_duration}s): +{w_created_during_task} points")
        details['criterion_created_during_task'] = True
    else:
        feedback_parts.append(f"○ Could not verify task timing")
        details['criterion_created_during_task'] = False
    
    # ================================================================
    # CRITERION 3: Within 5mm of AC (35 points)
    # ================================================================
    closest_distance = result.get('closest_distance_mm', -1)
    closest_fiducial = result.get('closest_fiducial', {})
    within_5mm = result.get('within_5mm', False)
    
    details['closest_distance_mm'] = closest_distance
    
    if closest_fiducial:
        details['placed_position_ras'] = closest_fiducial.get('position_ras', [])
        details['fiducial_name'] = closest_fiducial.get('name', 'unnamed')
    
    if closest_distance >= 0:
        if within_5mm:
            score += w_within_5mm
            feedback_parts.append(f"✓ Within 5mm of AC ({closest_distance:.1f}mm): +{w_within_5mm} points")
            details['criterion_within_5mm'] = True
        else:
            feedback_parts.append(f"✗ Not within 5mm of AC ({closest_distance:.1f}mm): +0 points")
            details['criterion_within_5mm'] = False
    else:
        feedback_parts.append("✗ Could not calculate distance to AC")
        details['criterion_within_5mm'] = False
    
    # ================================================================
    # CRITERION 4: Within 3mm precision bonus (15 points)
    # ================================================================
    within_3mm = result.get('within_3mm', False)
    
    if within_3mm:
        score += w_within_3mm
        feedback_parts.append(f"✓ High precision - within 3mm ({closest_distance:.1f}mm): +{w_within_3mm} bonus points")
        details['criterion_within_3mm'] = True
    else:
        if closest_distance >= 0 and closest_distance <= tolerance_5mm:
            feedback_parts.append(f"○ Acceptable but not high precision ({closest_distance:.1f}mm > 3mm)")
        details['criterion_within_3mm'] = False
    
    # ================================================================
    # CRITERION 5: Midline placement (10 points)
    # ================================================================
    midline_placement = result.get('midline_placement', False)
    r_coordinate = result.get('r_coordinate', None)
    
    if midline_placement:
        score += w_midline
        r_str = f"R={r_coordinate:.1f}mm" if r_coordinate is not None else ""
        feedback_parts.append(f"✓ Correctly placed on midline ({r_str}): +{w_midline} points")
        details['criterion_midline_placement'] = True
    else:
        if closest_fiducial and 'position_ras' in closest_fiducial:
            r_coord = closest_fiducial['position_ras'][0]
            feedback_parts.append(f"✗ Not on midline (R={r_coord:.1f}mm, should be ±{midline_tolerance}mm): +0 points")
        else:
            feedback_parts.append("✗ Could not verify midline placement")
        details['criterion_midline_placement'] = False
    
    # ================================================================
    # Calculate final result
    # ================================================================
    # Key criteria: fiducial must exist AND be within 5mm
    key_criteria_met = details.get('criterion_fiducial_exists', False) and details.get('criterion_within_5mm', False)
    passed = score >= pass_threshold and key_criteria_met
    
    details['score'] = score
    details['max_score'] = max_score
    details['pass_threshold'] = pass_threshold
    details['key_criteria_met'] = key_criteria_met
    details['passed'] = passed
    
    # Build feedback string
    feedback = f"Score: {score}/{max_score} (pass threshold: {pass_threshold})\n"
    feedback += "\n".join(feedback_parts)
    
    if passed:
        if within_3mm:
            feedback += f"\n\n✓ PASSED with EXCELLENT precision! Successfully located the anterior commissure within {closest_distance:.1f}mm."
        else:
            feedback += f"\n\n✓ PASSED - Successfully located the anterior commissure within {closest_distance:.1f}mm."
    else:
        if not details.get('criterion_within_5mm', False) and details.get('criterion_fiducial_exists', False):
            feedback += f"\n\n✗ FAILED - Fiducial was placed but too far from the AC ({closest_distance:.1f}mm > 5mm threshold)"
        else:
            feedback += f"\n\n✗ FAILED - Did not meet pass threshold of {pass_threshold} points"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }


if __name__ == "__main__":
    # Test run
    import sys
    
    # Mock data for testing
    mock_result = {
        "slicer_running": True,
        "volumes_loaded": 1,
        "fiducials_found": True,
        "fiducial_count": 1,
        "fiducials": [
            {
                "name": "AC",
                "position_ras": [0.5, 2.0, -2.5],
                "node_name": "F"
            }
        ],
        "ground_truth_ac": [0.0, 1.5, -3.0],
        "closest_distance_mm": 1.12,
        "closest_fiducial": {
            "name": "AC",
            "position_ras": [0.5, 2.0, -2.5]
        },
        "within_5mm": True,
        "within_3mm": True,
        "midline_placement": True,
        "task_duration_sec": 120
    }
    
    print("Mock test result:")
    print(json.dumps(mock_result, indent=2))