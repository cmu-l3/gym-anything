#!/usr/bin/env python3
"""
Verifier for Define Oblique Plane Through Landmarks task.

VERIFICATION CRITERIA:
1. Plane markup exists (15 points) - A plane markup node is present
2. Three control points (15 points) - Plane has exactly 3 control points
3. AC point accurate (20 points) - First point within 5mm of expected AC location
4. PC point accurate (20 points) - Second point within 5mm of expected PC location
5. Superior point valid (15 points) - Third point is on midline and superior to AC-PC
6. Plane orientation correct (15 points) - Plane normal approximately superior-inferior

Pass threshold: 65 points with plane_markup_exists criterion met
"""

import json
import os
import tempfile
import logging
import math
from typing import Dict, Any, List, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def euclidean_distance(p1: List[float], p2: List[float]) -> float:
    """Calculate Euclidean distance between two 3D points."""
    if len(p1) < 3 or len(p2) < 3:
        return float('inf')
    return math.sqrt(sum((a - b) ** 2 for a, b in zip(p1[:3], p2[:3])))


def angle_between_vectors(v1: List[float], v2: List[float]) -> float:
    """Calculate angle in degrees between two vectors."""
    if len(v1) < 3 or len(v2) < 3:
        return 90.0
    
    # Normalize vectors
    mag1 = math.sqrt(sum(x ** 2 for x in v1[:3]))
    mag2 = math.sqrt(sum(x ** 2 for x in v2[:3]))
    
    if mag1 < 1e-10 or mag2 < 1e-10:
        return 90.0
    
    v1_norm = [x / mag1 for x in v1[:3]]
    v2_norm = [x / mag2 for x in v2[:3]]
    
    dot = sum(a * b for a, b in zip(v1_norm, v2_norm))
    dot = max(-1.0, min(1.0, dot))  # Clamp to [-1, 1]
    
    return math.degrees(math.acos(abs(dot)))


def compute_plane_normal(p1: List[float], p2: List[float], p3: List[float]) -> List[float]:
    """Compute plane normal from three points."""
    # Vectors from p1 to p2 and p1 to p3
    v1 = [p2[i] - p1[i] for i in range(3)]
    v2 = [p3[i] - p1[i] for i in range(3)]
    
    # Cross product
    normal = [
        v1[1] * v2[2] - v1[2] * v2[1],
        v1[2] * v2[0] - v1[0] * v2[2],
        v1[0] * v2[1] - v1[1] * v2[0]
    ]
    
    # Normalize
    mag = math.sqrt(sum(x ** 2 for x in normal))
    if mag < 1e-10:
        return [0, 0, 1]
    
    return [x / mag for x in normal]


def verify_define_oblique_plane(traj, env_info, task_info):
    """
    Verify that the agent correctly defined the AC-PC plane.
    
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
    ac_expected = metadata.get('ac_ras_expected', [0.0, 1.5, -4.0])
    pc_expected = metadata.get('pc_ras_expected', [0.0, -24.5, -2.0])
    point_tolerance = metadata.get('point_tolerance_mm', 5.0)
    midline_tolerance = metadata.get('midline_tolerance_mm', 5.0)
    normal_tolerance_deg = metadata.get('plane_normal_tolerance_deg', 30.0)
    
    weights = metadata.get('scoring_weights', {})
    w_plane_exists = weights.get('plane_markup_exists', 15)
    w_three_points = weights.get('three_control_points', 15)
    w_ac_accurate = weights.get('ac_point_accurate', 20)
    w_pc_accurate = weights.get('pc_point_accurate', 20)
    w_superior_valid = weights.get('superior_point_valid', 15)
    w_orientation = weights.get('plane_orientation_correct', 15)
    
    # Expected superior direction normal (approximately [0, 0, 1] in RAS)
    expected_normal = [0.0, -0.08, 0.997]
    
    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/plane_task_result.json", temp_result.name)
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
    # ANTI-GAMING: Check timestamps
    # ================================================================
    task_start = result.get('task_start', 0)
    task_end = result.get('task_end', 0)
    file_created_during_task = result.get('file_created_during_task', False)
    
    if task_end > 0 and task_start > 0:
        duration = task_end - task_start
        details['task_duration_sec'] = duration
        if duration < 5:
            feedback_parts.append("WARNING: Task completed suspiciously fast")
    
    # ================================================================
    # CHECK: Slicer was running
    # ================================================================
    if not result.get('slicer_was_running', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Slicer was not running - cannot verify task completion"
        }
    
    # ================================================================
    # CRITERION 1: Plane markup exists (15 points)
    # ================================================================
    output_exists = result.get('output_file_exists', False)
    slicer_export = result.get('slicer_export_data', {})
    plane_count = slicer_export.get('plane_count', 0)
    
    plane_exists = output_exists or plane_count > 0
    
    if plane_exists:
        score += w_plane_exists
        feedback_parts.append("Plane markup exists")
        details['plane_exists'] = True
    else:
        feedback_parts.append("NO plane markup found")
        details['plane_exists'] = False
        # Early exit - nothing else to verify
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # Extract control points from result
    # ================================================================
    control_points = []
    
    # Try from direct export
    cp_list = result.get('control_points', [])
    if cp_list and len(cp_list) > 0:
        for cp in cp_list:
            pos = cp.get('position_ras', [])
            if pos and len(pos) >= 3:
                control_points.append(pos)
    
    # Also try from slicer export data
    if len(control_points) < 3 and 'planes' in slicer_export:
        for plane in slicer_export.get('planes', []):
            for cp in plane.get('control_points', []):
                pos = cp.get('position_ras', [])
                if pos and len(pos) >= 3:
                    if pos not in control_points:
                        control_points.append(pos)
    
    num_points = len(control_points)
    details['num_control_points'] = num_points
    details['control_points'] = control_points
    
    # ================================================================
    # CRITERION 2: Three control points (15 points)
    # ================================================================
    if num_points == 3:
        score += w_three_points
        feedback_parts.append("3 control points defined")
    elif num_points > 0:
        partial = w_three_points * (min(num_points, 3) / 3)
        score += int(partial)
        feedback_parts.append(f"{num_points} control points (need 3)")
    else:
        feedback_parts.append("No control points found")
    
    if num_points < 1:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "details": details
        }
    
    # ================================================================
    # CRITERION 3: AC point accurate (20 points)
    # ================================================================
    ac_point = control_points[0] if num_points >= 1 else None
    ac_distance = float('inf')
    
    if ac_point:
        ac_distance = euclidean_distance(ac_point, ac_expected)
        details['ac_point'] = ac_point
        details['ac_distance_mm'] = round(ac_distance, 2)
        
        if ac_distance <= point_tolerance:
            score += w_ac_accurate
            feedback_parts.append(f"AC point accurate ({ac_distance:.1f}mm)")
        elif ac_distance <= point_tolerance * 2:
            partial = w_ac_accurate * 0.5
            score += int(partial)
            feedback_parts.append(f"AC point close ({ac_distance:.1f}mm)")
        else:
            feedback_parts.append(f"AC point off ({ac_distance:.1f}mm)")
    else:
        feedback_parts.append("AC point missing")
    
    # ================================================================
    # CRITERION 4: PC point accurate (20 points)
    # ================================================================
    pc_point = control_points[1] if num_points >= 2 else None
    pc_distance = float('inf')
    
    if pc_point:
        pc_distance = euclidean_distance(pc_point, pc_expected)
        details['pc_point'] = pc_point
        details['pc_distance_mm'] = round(pc_distance, 2)
        
        if pc_distance <= point_tolerance:
            score += w_pc_accurate
            feedback_parts.append(f"PC point accurate ({pc_distance:.1f}mm)")
        elif pc_distance <= point_tolerance * 2:
            partial = w_pc_accurate * 0.5
            score += int(partial)
            feedback_parts.append(f"PC point close ({pc_distance:.1f}mm)")
        else:
            feedback_parts.append(f"PC point off ({pc_distance:.1f}mm)")
    else:
        feedback_parts.append("PC point missing")
    
    # ================================================================
    # CRITERION 5: Superior point valid (15 points)
    # - Must be on midline (|R| < tolerance)
    # - Must be superior to AC-PC line (S > max(AC_S, PC_S))
    # ================================================================
    sup_point = control_points[2] if num_points >= 3 else None
    
    if sup_point:
        details['superior_point'] = sup_point
        
        # Check midline (R coordinate near 0)
        r_coord = sup_point[0]
        on_midline = abs(r_coord) <= midline_tolerance
        
        # Check superior (S coordinate above AC-PC)
        s_coord = sup_point[2]
        ac_s = ac_expected[2]
        pc_s = pc_expected[2]
        is_superior = s_coord > max(ac_s, pc_s) + 5  # At least 5mm above
        
        details['superior_r_offset'] = round(abs(r_coord), 2)
        details['superior_s_coord'] = round(s_coord, 2)
        details['on_midline'] = on_midline
        details['is_superior'] = is_superior
        
        if on_midline and is_superior:
            score += w_superior_valid
            feedback_parts.append("Superior point valid (midline & above AC-PC)")
        elif on_midline:
            score += int(w_superior_valid * 0.5)
            feedback_parts.append(f"Superior point on midline but S={s_coord:.1f}")
        elif is_superior:
            score += int(w_superior_valid * 0.5)
            feedback_parts.append(f"Superior point above AC-PC but R={r_coord:.1f}")
        else:
            feedback_parts.append(f"Superior point invalid (R={r_coord:.1f}, S={s_coord:.1f})")
    else:
        feedback_parts.append("Superior point missing")
    
    # ================================================================
    # CRITERION 6: Plane orientation correct (15 points)
    # ================================================================
    if num_points >= 3:
        computed_normal = compute_plane_normal(
            control_points[0], control_points[1], control_points[2]
        )
        details['computed_normal'] = [round(x, 4) for x in computed_normal]
        
        # Angle to expected (approximately horizontal plane with normal pointing up)
        angle_to_expected = angle_between_vectors(computed_normal, expected_normal)
        details['normal_angle_deg'] = round(angle_to_expected, 2)
        
        if angle_to_expected <= normal_tolerance_deg:
            score += w_orientation
            feedback_parts.append(f"Plane orientation correct ({angle_to_expected:.1f}°)")
        elif angle_to_expected <= normal_tolerance_deg * 2:
            partial = w_orientation * 0.5
            score += int(partial)
            feedback_parts.append(f"Plane orientation acceptable ({angle_to_expected:.1f}°)")
        else:
            feedback_parts.append(f"Plane orientation off ({angle_to_expected:.1f}°)")
    
    # ================================================================
    # VLM TRAJECTORY VERIFICATION (bonus confidence)
    # ================================================================
    vlm_bonus = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            # Import trajectory sampling utilities
            from gym_anything.vlm import sample_trajectory_frames
            
            frames = sample_trajectory_frames(traj, n=4)
            
            if frames and len(frames) > 0:
                vlm_prompt = """Analyze these screenshots from a 3D Slicer session where the user should be creating an AC-PC plane.

The task involves:
1. Opening the Markups module
2. Creating a plane markup with 3 control points
3. Placing points at anatomical landmarks on a brain MRI

Look for evidence of:
- Brain MRI visible in slice views (sagittal view most important)
- Markups module or toolbar visible
- Control points/plane visualization in the views
- Navigation to deep brain structures (AC/PC are in the center of the brain)

Respond in JSON:
{
    "brain_mri_visible": true/false,
    "markups_interaction": true/false,
    "plane_or_points_visible": true/false,
    "sagittal_view_used": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief description"
}"""
                
                vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
                
                if vlm_result and vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    details['vlm_result'] = parsed
                    
                    # Award bonus for workflow evidence
                    if parsed.get('markups_interaction') and parsed.get('plane_or_points_visible'):
                        vlm_bonus = 5
                        feedback_parts.append("VLM confirms workflow (+5)")
                    elif parsed.get('brain_mri_visible') and parsed.get('sagittal_view_used'):
                        vlm_bonus = 3
                        feedback_parts.append("VLM sees appropriate navigation (+3)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            details['vlm_error'] = str(e)
    
    score += vlm_bonus
    
    # ================================================================
    # FINAL SCORING
    # ================================================================
    max_score = w_plane_exists + w_three_points + w_ac_accurate + w_pc_accurate + w_superior_valid + w_orientation
    score = min(score, 100)  # Cap at 100
    
    # Pass criteria: 65+ points AND plane exists
    passed = score >= 65 and plane_exists
    
    details['max_possible_score'] = max_score
    details['file_created_during_task'] = file_created_during_task
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": details
    }