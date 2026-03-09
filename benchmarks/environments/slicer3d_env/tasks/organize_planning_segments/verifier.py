#!/usr/bin/env python3
"""
Verifier for organize_planning_segments task.

VERIFICATION CRITERIA:
1. Output file exists (10 points)
2. File created during task - anti-gaming (10 points)
3. Liver Parenchyma segment named correctly (10 points)
4. Liver Parenchyma segment color correct (10 points)
5. Tumor segment named correctly (10 points)
6. Tumor segment color correct (10 points)
7. Portal Vein segment named correctly (10 points)
8. Portal Vein segment color correct (10 points)
9. Hepatic Vein segment named correctly (10 points)
10. Hepatic Vein segment color correct (10 points)

Pass threshold: 70 points with at least 3 segments correctly named
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def color_distance(c1, c2):
    """Calculate Euclidean distance between two RGB colors."""
    return math.sqrt(
        (c1['r'] - c2['r'])**2 +
        (c1['g'] - c2['g'])**2 +
        (c1['b'] - c2['b'])**2
    )


def verify_organize_planning_segments(traj, env_info, task_info):
    """
    Verify that segments were correctly renamed and colored.
    
    Uses multi-criteria scoring with color tolerance checks.
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
    expected_segments = metadata.get('expected_segments', {
        "Liver Parenchyma": {"r": 166, "g": 128, "b": 91},
        "Tumor": {"r": 241, "g": 214, "b": 69},
        "Portal Vein": {"r": 56, "g": 77, "b": 186},
        "Hepatic Vein": {"r": 128, "g": 48, "b": 166}
    })
    color_tolerance = metadata.get('color_tolerance', 15)
    
    weights = metadata.get('scoring_weights', {})
    w_file_exists = weights.get('output_file_exists', 10)
    w_file_created = weights.get('file_created_during_task', 10)
    w_liver_name = weights.get('liver_parenchyma_named', 10)
    w_liver_color = weights.get('liver_parenchyma_color', 10)
    w_tumor_name = weights.get('tumor_named', 10)
    w_tumor_color = weights.get('tumor_color', 10)
    w_portal_name = weights.get('portal_vein_named', 10)
    w_portal_color = weights.get('portal_vein_color', 10)
    w_hepatic_name = weights.get('hepatic_vein_named', 10)
    w_hepatic_color = weights.get('hepatic_vein_color', 10)

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/segment_task_result.json", temp_result.name)
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

    # ============================================================
    # CRITERION 1: Output file exists (10 points)
    # ============================================================
    output_exists = result.get('output_exists', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and output_size > 1000:
        score += w_file_exists
        feedback_parts.append(f"Output file exists ({output_size} bytes)")
        details['output_exists'] = True
    else:
        feedback_parts.append("Output file NOT found or empty")
        details['output_exists'] = False
        # Early exit - no point checking further
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # ============================================================
    # CRITERION 2: File created during task (10 points)
    # ============================================================
    file_created = result.get('file_created_during_task', False)
    
    if file_created:
        score += w_file_created
        feedback_parts.append("File created during task")
        details['file_created_during_task'] = True
    else:
        feedback_parts.append("WARNING: File may have existed before task")
        details['file_created_during_task'] = False

    # ============================================================
    # PARSE SEGMENTS FROM RESULT
    # ============================================================
    segments = result.get('segments', [])
    segment_count = result.get('segment_count', len(segments))
    details['segment_count'] = segment_count
    details['segments_found'] = [s.get('name', 'unknown') for s in segments]
    
    if segment_count == 0:
        feedback_parts.append("No segments found in output")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }

    # Create lookup for found segments (case-insensitive)
    found_segments = {}
    for seg in segments:
        name = seg.get('name', '').strip()
        if name:
            # Store with lowercase key for case-insensitive matching
            found_segments[name.lower()] = {
                'name': name,
                'r': seg.get('r', 0),
                'g': seg.get('g', 0),
                'b': seg.get('b', 0)
            }

    # ============================================================
    # CHECK EACH EXPECTED SEGMENT
    # ============================================================
    segments_correctly_named = 0
    segments_correctly_colored = 0
    
    # Helper function to check a segment
    def check_segment(expected_name, expected_color, name_weight, color_weight):
        nonlocal score, segments_correctly_named, segments_correctly_colored
        
        # Look for the segment (case-insensitive)
        found = found_segments.get(expected_name.lower())
        
        name_ok = False
        color_ok = False
        
        if found:
            # Check if name matches (allowing minor variations)
            actual_name = found['name']
            if actual_name.lower() == expected_name.lower():
                name_ok = True
                segments_correctly_named += 1
                score += name_weight
            
            # Check color
            actual_color = {'r': found['r'], 'g': found['g'], 'b': found['b']}
            dist = color_distance(actual_color, expected_color)
            
            if dist <= color_tolerance * math.sqrt(3):  # Tolerance per channel
                color_ok = True
                segments_correctly_colored += 1
                score += color_weight
            
            details[f'{expected_name}_name'] = name_ok
            details[f'{expected_name}_color'] = color_ok
            details[f'{expected_name}_actual_color'] = actual_color
            details[f'{expected_name}_color_distance'] = round(dist, 1)
            
            return name_ok, color_ok, actual_color
        else:
            details[f'{expected_name}_name'] = False
            details[f'{expected_name}_color'] = False
            return False, False, None

    # Check Liver Parenchyma
    liver_name_ok, liver_color_ok, liver_actual = check_segment(
        "Liver Parenchyma",
        expected_segments.get("Liver Parenchyma", {"r": 166, "g": 128, "b": 91}),
        w_liver_name, w_liver_color
    )
    if liver_name_ok:
        if liver_color_ok:
            feedback_parts.append("Liver Parenchyma: ✓ name & color")
        else:
            feedback_parts.append(f"Liver Parenchyma: ✓ name, ✗ color")
    else:
        feedback_parts.append("Liver Parenchyma: ✗ not found")

    # Check Tumor
    tumor_name_ok, tumor_color_ok, tumor_actual = check_segment(
        "Tumor",
        expected_segments.get("Tumor", {"r": 241, "g": 214, "b": 69}),
        w_tumor_name, w_tumor_color
    )
    if tumor_name_ok:
        if tumor_color_ok:
            feedback_parts.append("Tumor: ✓ name & color")
        else:
            feedback_parts.append(f"Tumor: ✓ name, ✗ color")
    else:
        feedback_parts.append("Tumor: ✗ not found")

    # Check Portal Vein
    portal_name_ok, portal_color_ok, portal_actual = check_segment(
        "Portal Vein",
        expected_segments.get("Portal Vein", {"r": 56, "g": 77, "b": 186}),
        w_portal_name, w_portal_color
    )
    if portal_name_ok:
        if portal_color_ok:
            feedback_parts.append("Portal Vein: ✓ name & color")
        else:
            feedback_parts.append(f"Portal Vein: ✓ name, ✗ color")
    else:
        feedback_parts.append("Portal Vein: ✗ not found")

    # Check Hepatic Vein
    hepatic_name_ok, hepatic_color_ok, hepatic_actual = check_segment(
        "Hepatic Vein",
        expected_segments.get("Hepatic Vein", {"r": 128, "g": 48, "b": 166}),
        w_hepatic_name, w_hepatic_color
    )
    if hepatic_name_ok:
        if hepatic_color_ok:
            feedback_parts.append("Hepatic Vein: ✓ name & color")
        else:
            feedback_parts.append(f"Hepatic Vein: ✓ name, ✗ color")
    else:
        feedback_parts.append("Hepatic Vein: ✗ not found")

    # ============================================================
    # SUMMARY
    # ============================================================
    details['segments_correctly_named'] = segments_correctly_named
    details['segments_correctly_colored'] = segments_correctly_colored
    
    # Determine pass/fail
    # Pass if: score >= 70 AND at least 3 segments correctly named
    key_criteria_met = segments_correctly_named >= 3 and output_exists and file_created
    passed = score >= 70 and key_criteria_met
    
    # Add summary to feedback
    summary = f"Score: {score}/100 | Named: {segments_correctly_named}/4 | Colored: {segments_correctly_colored}/4"
    feedback_parts.insert(0, summary)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }