#!/usr/bin/env python3
"""
Verifier for AC-PC Line Creation task.

VERIFICATION STRATEGY (Multi-criteria scoring):
1. Markups file created (15 pts) - File exists at expected path with valid content
2. AC fiducial present (10 pts) - A fiducial named/labeled "AC" exists
3. PC fiducial present (10 pts) - A fiducial named/labeled "PC" exists
4. AC location accuracy (20 pts) - AC within tolerance of reference location
5. PC location accuracy (20 pts) - PC within tolerance of reference location
6. AC-PC distance valid (15 pts) - Measured distance is in physiological range (20-32mm)
7. Line markup created (5 pts) - A line connecting AC and PC exists
8. Correct spatial relationship (5 pts) - AC is anterior to PC (Y-coordinate check)

Pass threshold: 70 points with AC and PC fiducials present and in approximately correct locations
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def calculate_distance(p1, p2):
    """Calculate Euclidean distance between two 3D points."""
    if not p1 or not p2:
        return None
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1, p2)))


def verify_create_acpc_line(traj, env_info, task_info):
    """
    Verify AC-PC line creation task completion.
    
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
    
    # Reference coordinates (RAS)
    ref_ac = metadata.get('reference_ac_ras', [-0.5, 2.0, -4.0])
    ref_pc = metadata.get('reference_pc_ras', [-0.5, -23.0, -2.0])
    ac_tolerance = metadata.get('ac_tolerance_mm', 8.0)
    pc_tolerance = metadata.get('pc_tolerance_mm', 8.0)
    
    # Distance range
    distance_range = metadata.get('acpc_distance_range_mm', {"min": 20.0, "max": 32.0})
    min_dist = distance_range.get('min', 20.0)
    max_dist = distance_range.get('max', 32.0)
    
    # Midline tolerance
    midline_tol = metadata.get('midline_tolerance_mm', 10.0)
    
    # Scoring weights
    weights = metadata.get('scoring_weights', {})
    w_file = weights.get('markups_file_created', 15)
    w_ac_present = weights.get('ac_fiducial_present', 10)
    w_pc_present = weights.get('pc_fiducial_present', 10)
    w_ac_loc = weights.get('ac_location_accuracy', 20)
    w_pc_loc = weights.get('pc_location_accuracy', 20)
    w_dist = weights.get('acpc_distance_valid', 15)
    w_line = weights.get('line_markup_created', 5)
    w_spatial = weights.get('correct_spatial_relationship', 5)
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/acpc_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export result not found - task may not have run correctly"
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
        feedback_parts.append("Slicer not running")
        details['slicer_running'] = False
    else:
        details['slicer_running'] = True
    
    # ================================================================
    # CRITERION 1: Markups file created (15 points)
    # ================================================================
    output_exists = result.get('output_exists', False)
    created_during_task = result.get('output_created_during_task', False)
    output_size = result.get('output_size_bytes', 0)
    
    if output_exists and created_during_task and output_size > 100:
        score += w_file
        feedback_parts.append(f"Markups file created ({output_size}B)")
        details['file_created'] = True
    elif output_exists and output_size > 100:
        score += w_file * 0.5  # Partial credit if file exists but may be pre-existing
        feedback_parts.append("Markups file exists (may be pre-existing)")
        details['file_created'] = False
    else:
        feedback_parts.append("No markups file created")
        details['file_created'] = False
    
    # ================================================================
    # CRITERION 2: AC fiducial present (10 points)
    # ================================================================
    ac_found = result.get('ac_found', False)
    ac_coords = result.get('ac_coords')
    
    if ac_found and ac_coords:
        score += w_ac_present
        feedback_parts.append("AC fiducial found")
        details['ac_found'] = True
        details['ac_coords'] = ac_coords
    else:
        feedback_parts.append("AC fiducial NOT found")
        details['ac_found'] = False
    
    # ================================================================
    # CRITERION 3: PC fiducial present (10 points)
    # ================================================================
    pc_found = result.get('pc_found', False)
    pc_coords = result.get('pc_coords')
    
    if pc_found and pc_coords:
        score += w_pc_present
        feedback_parts.append("PC fiducial found")
        details['pc_found'] = True
        details['pc_coords'] = pc_coords
    else:
        feedback_parts.append("PC fiducial NOT found")
        details['pc_found'] = False
    
    # ================================================================
    # CRITERION 4: AC location accuracy (20 points)
    # ================================================================
    if ac_coords:
        ac_error = calculate_distance(ac_coords, ref_ac)
        details['ac_error_mm'] = ac_error
        
        if ac_error is not None:
            if ac_error <= ac_tolerance:
                score += w_ac_loc
                feedback_parts.append(f"AC accurate ({ac_error:.1f}mm error)")
            elif ac_error <= ac_tolerance * 2:
                # Partial credit for close but not perfect
                partial = w_ac_loc * (1 - (ac_error - ac_tolerance) / ac_tolerance)
                score += max(0, partial)
                feedback_parts.append(f"AC partially accurate ({ac_error:.1f}mm error)")
            else:
                feedback_parts.append(f"AC location far from reference ({ac_error:.1f}mm)")
        
        # Check if near midline
        if abs(ac_coords[0]) <= midline_tol:
            details['ac_near_midline'] = True
        else:
            details['ac_near_midline'] = False
            feedback_parts.append(f"AC not on midline (x={ac_coords[0]:.1f})")
    
    # ================================================================
    # CRITERION 5: PC location accuracy (20 points)
    # ================================================================
    if pc_coords:
        pc_error = calculate_distance(pc_coords, ref_pc)
        details['pc_error_mm'] = pc_error
        
        if pc_error is not None:
            if pc_error <= pc_tolerance:
                score += w_pc_loc
                feedback_parts.append(f"PC accurate ({pc_error:.1f}mm error)")
            elif pc_error <= pc_tolerance * 2:
                partial = w_pc_loc * (1 - (pc_error - pc_tolerance) / pc_tolerance)
                score += max(0, partial)
                feedback_parts.append(f"PC partially accurate ({pc_error:.1f}mm error)")
            else:
                feedback_parts.append(f"PC location far from reference ({pc_error:.1f}mm)")
        
        # Check if near midline
        if abs(pc_coords[0]) <= midline_tol:
            details['pc_near_midline'] = True
        else:
            details['pc_near_midline'] = False
            feedback_parts.append(f"PC not on midline (x={pc_coords[0]:.1f})")
    
    # ================================================================
    # CRITERION 6: AC-PC distance valid (15 points)
    # ================================================================
    acpc_distance = result.get('acpc_distance_mm', 0)
    if isinstance(acpc_distance, str):
        try:
            acpc_distance = float(acpc_distance)
        except ValueError:
            acpc_distance = 0
    
    details['acpc_distance_mm'] = acpc_distance
    details['expected_range'] = f"{min_dist}-{max_dist}mm"
    
    if acpc_distance > 0:
        if min_dist <= acpc_distance <= max_dist:
            score += w_dist
            feedback_parts.append(f"AC-PC distance valid ({acpc_distance:.1f}mm)")
        elif min_dist - 5 <= acpc_distance <= max_dist + 5:
            # Slightly outside range - partial credit
            score += w_dist * 0.5
            feedback_parts.append(f"AC-PC distance borderline ({acpc_distance:.1f}mm)")
        else:
            feedback_parts.append(f"AC-PC distance abnormal ({acpc_distance:.1f}mm)")
    else:
        # Try to calculate from coordinates
        if ac_coords and pc_coords:
            calc_dist = calculate_distance(ac_coords, pc_coords)
            if calc_dist and min_dist <= calc_dist <= max_dist:
                score += w_dist
                feedback_parts.append(f"Calculated AC-PC distance valid ({calc_dist:.1f}mm)")
                details['acpc_distance_mm'] = calc_dist
            elif calc_dist:
                feedback_parts.append(f"Calculated AC-PC distance: {calc_dist:.1f}mm")
                details['acpc_distance_mm'] = calc_dist
    
    # ================================================================
    # CRITERION 7: Line markup created (5 points)
    # ================================================================
    line_found = result.get('line_found', False)
    
    if line_found:
        score += w_line
        feedback_parts.append("Line markup created")
        details['line_created'] = True
    else:
        feedback_parts.append("No line markup")
        details['line_created'] = False
    
    # ================================================================
    # CRITERION 8: Correct spatial relationship (5 points)
    # AC should be anterior to PC (higher Y in RAS coordinates)
    # ================================================================
    if ac_coords and pc_coords:
        ac_y = ac_coords[1]
        pc_y = pc_coords[1]
        
        if ac_y > pc_y:
            score += w_spatial
            feedback_parts.append("Correct AC-PC orientation")
            details['spatial_correct'] = True
        else:
            feedback_parts.append("WARNING: AC appears posterior to PC")
            details['spatial_correct'] = False
    
    # ================================================================
    # DETERMINE PASS/FAIL
    # ================================================================
    # Key criteria: both fiducials present and reasonably placed
    key_criteria_met = (
        ac_found and pc_found and
        (details.get('ac_error_mm', 100) <= ac_tolerance * 2.5) and
        (details.get('pc_error_mm', 100) <= pc_tolerance * 2.5)
    )
    
    passed = score >= 70 and key_criteria_met
    
    # Additional check: if distance is way off, don't pass
    if acpc_distance > 0 and (acpc_distance < 10 or acpc_distance > 50):
        passed = False
        feedback_parts.append("FAIL: AC-PC distance anatomically implausible")
    
    # Build final feedback
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": int(score),
        "feedback": feedback,
        "details": details
    }