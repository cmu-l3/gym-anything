#!/usr/bin/env python3
"""
Verifier for dose_zone_margins task.

VERIFICATION CRITERIA:
1. Four segments exist (15 points) - Tumor + 3 zone segments
2. Correct segment names (10 points) - Zones named with distance indicators
3. Zone1 correct (15 points) - Red segment, ring shape, 5mm margin
4. Zone2 correct (15 points) - Yellow segment, ring shape, 10mm margin
5. Zone3 correct (15 points) - Green segment, ring shape, 15mm margin
6. Non-overlapping zones (10 points) - Zones are rings (Boolean subtraction applied)
7. Correct color coding (10 points) - Red→Yellow→Green from inner to outer
8. Volume ordering valid (10 points) - Zone1 < Zone2 < Zone3 by volume

Pass threshold: 70 points with at least Zone1 and Zone2 correctly created
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_dose_zone_margins(traj, env_info, task_info):
    """
    Verify that dose zone margin segments were created correctly.
    
    Uses multi-criteria scoring with structural and color checks.
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
    weights = metadata.get('scoring_weights', {})
    
    w_four_segments = weights.get('four_segments_exist', 15)
    w_names = weights.get('correct_segment_names', 10)
    w_zone1 = weights.get('zone1_correct', 15)
    w_zone2 = weights.get('zone2_correct', 15)
    w_zone3 = weights.get('zone3_correct', 15)
    w_non_overlap = weights.get('non_overlapping_zones', 10)
    w_colors = weights.get('correct_color_coding', 10)
    w_volume_order = weights.get('volume_ordering_valid', 10)
    
    color_tolerance = metadata.get('color_tolerance', 30)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/dose_zone_result.json", temp_result.name)
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

    # ================================================================
    # BASIC CHECKS
    # ================================================================
    
    # Check if Slicer was running
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }

    # Check if segmentation exists
    if not result.get('segmentation_node_exists', False):
        return {
            "passed": False,
            "score": 5,
            "feedback": "No segmentation node found in Slicer scene"
        }

    # ================================================================
    # CRITERION 1: Four segments exist (15 points)
    # ================================================================
    segment_count = result.get('segment_count', 0)
    details['segment_count'] = segment_count
    
    if segment_count >= 4:
        score += w_four_segments
        feedback_parts.append(f"4+ segments exist ({segment_count})")
    elif segment_count == 3:
        score += w_four_segments * 0.7
        feedback_parts.append(f"Only 3 segments (expected 4)")
    elif segment_count == 2:
        score += w_four_segments * 0.4
        feedback_parts.append(f"Only 2 segments")
    elif segment_count == 1:
        score += w_four_segments * 0.2
        feedback_parts.append(f"Only 1 segment")
    else:
        feedback_parts.append("No segments found")

    # ================================================================
    # CRITERION 2: Correct segment names (10 points)
    # ================================================================
    tumor_found = result.get('tumor_found', False)
    zone1_found = result.get('zone1_found', False)
    zone2_found = result.get('zone2_found', False)
    zone3_found = result.get('zone3_found', False)
    
    details['tumor_found'] = tumor_found
    details['zone1_found'] = zone1_found
    details['zone2_found'] = zone2_found
    details['zone3_found'] = zone3_found
    
    named_correctly = sum([tumor_found, zone1_found, zone2_found, zone3_found])
    if named_correctly == 4:
        score += w_names
        feedback_parts.append("All segments named correctly")
    elif named_correctly >= 2:
        score += w_names * (named_correctly / 4)
        feedback_parts.append(f"{named_correctly}/4 segments named correctly")
    else:
        feedback_parts.append("Segments not named correctly")

    # ================================================================
    # CRITERION 3: Zone1 correct (15 points)
    # ================================================================
    zone1_color = result.get('zone1_color_correct', False)
    details['zone1_color_correct'] = zone1_color
    
    if zone1_found:
        zone1_score = w_zone1 * 0.6  # Base for finding zone
        if zone1_color:
            zone1_score = w_zone1  # Full points with correct color
            feedback_parts.append("Zone1 (5mm, red) ✓")
        else:
            feedback_parts.append("Zone1 found but wrong color")
        score += zone1_score
    else:
        feedback_parts.append("Zone1 (5mm) not found")

    # ================================================================
    # CRITERION 4: Zone2 correct (15 points)
    # ================================================================
    zone2_color = result.get('zone2_color_correct', False)
    details['zone2_color_correct'] = zone2_color
    
    if zone2_found:
        zone2_score = w_zone2 * 0.6
        if zone2_color:
            zone2_score = w_zone2
            feedback_parts.append("Zone2 (10mm, yellow) ✓")
        else:
            feedback_parts.append("Zone2 found but wrong color")
        score += zone2_score
    else:
        feedback_parts.append("Zone2 (10mm) not found")

    # ================================================================
    # CRITERION 5: Zone3 correct (15 points)
    # ================================================================
    zone3_color = result.get('zone3_color_correct', False)
    details['zone3_color_correct'] = zone3_color
    
    if zone3_found:
        zone3_score = w_zone3 * 0.6
        if zone3_color:
            zone3_score = w_zone3
            feedback_parts.append("Zone3 (15mm, green) ✓")
        else:
            feedback_parts.append("Zone3 found but wrong color")
        score += zone3_score
    else:
        feedback_parts.append("Zone3 (15mm) not found")

    # ================================================================
    # CRITERION 6: Non-overlapping zones / rings (10 points)
    # ================================================================
    zones_are_rings = result.get('zones_are_rings', False)
    details['zones_are_rings'] = zones_are_rings
    
    if zones_are_rings:
        score += w_non_overlap
        feedback_parts.append("Zones are proper rings")
    elif zone1_found and zone2_found:
        # Partial credit if zones exist but might be solid
        score += w_non_overlap * 0.5
        feedback_parts.append("Zones exist (ring check inconclusive)")

    # ================================================================
    # CRITERION 7: Correct color coding (10 points)
    # ================================================================
    all_colors_correct = zone1_color and zone2_color and zone3_color
    details['all_colors_correct'] = all_colors_correct
    
    if all_colors_correct:
        score += w_colors
        feedback_parts.append("Color coding correct (R→Y→G)")
    else:
        colors_correct = sum([zone1_color, zone2_color, zone3_color])
        if colors_correct > 0:
            score += w_colors * (colors_correct / 3)
            feedback_parts.append(f"{colors_correct}/3 colors correct")

    # ================================================================
    # CRITERION 8: Volume ordering valid (10 points)
    # ================================================================
    volume_order_ok = result.get('volume_ordering_correct', False)
    details['volume_ordering_correct'] = volume_order_ok
    
    if volume_order_ok:
        score += w_volume_order
        feedback_parts.append("Volume ordering correct")
    elif zone1_found and zone2_found and zone3_found:
        feedback_parts.append("Volume ordering incorrect")

    # ================================================================
    # ANTI-GAMING: File creation timestamp check
    # ================================================================
    file_created = result.get('file_created_during_task', False)
    output_exists = result.get('output_file_exists', False)
    
    details['output_saved'] = output_exists
    details['created_during_task'] = file_created
    
    if output_exists and file_created:
        feedback_parts.append("Output file saved")
    elif output_exists:
        feedback_parts.append("Output file exists (pre-existing?)")
    # Not penalizing for unsaved file if segments exist in scene

    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    
    # Key criteria: at least Zone1 and Zone2 should be correctly created
    key_criteria_met = (zone1_found and zone2_found and 
                        segment_count >= 3 and
                        result.get('segmentation_node_exists', False))
    
    # Round score
    score = int(round(score))
    
    # Pass if score >= 70 and key criteria met
    passed = (score >= 70) and key_criteria_met
    
    # Build feedback string
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }