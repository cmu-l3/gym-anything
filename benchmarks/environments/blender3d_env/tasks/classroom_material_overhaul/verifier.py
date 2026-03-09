#!/usr/bin/env python3
"""
Verifier for classroom_material_overhaul task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. Floor material: brown/wood base color + roughness in range (25 points)
2. Wall material: light/white base color (20 points)
3. Desk material: wood-like brown base color (20 points)
4. Glass material: transmission > 0.5 (20 points)
5. Blend file saved correctly (15 points)

Pass threshold: 70 points.

The verifier reads material names dynamically from initial_state.json (via
the task_result.json "matched_materials" dict) so it does NOT rely on
hardcoded material names.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _in_range(value, lo, hi):
    """Check if value is within [lo, hi] inclusive."""
    return lo <= value <= hi


def _color_in_range(rgba, range_dict):
    """Check if RGB components of an RGBA color fall within the specified ranges."""
    r, g, b = rgba[0], rgba[1], rgba[2]
    r_ok = _in_range(r, range_dict["r"][0], range_dict["r"][1])
    g_ok = _in_range(g, range_dict["g"][0], range_dict["g"][1])
    b_ok = _in_range(b, range_dict["b"][0], range_dict["b"][1])
    return r_ok and g_ok and b_ok


def _is_grey(rgba, tolerance=0.08):
    """Check if a color is still flat grey (unchanged from setup)."""
    return (
        abs(rgba[0] - 0.5) < tolerance
        and abs(rgba[1] - 0.5) < tolerance
        and abs(rgba[2] - 0.5) < tolerance
    )


def verify_classroom_material_overhaul(traj, env_info, task_info):
    """
    Verify that the 4 classroom materials were fixed and the file was saved.

    Uses MULTIPLE INDEPENDENT SIGNALS with per-criterion try/except.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/BlenderProjects/classroom_fixed.blend')
    floor_color_range = metadata.get('floor_color_range', {"r": [0.15, 0.6], "g": [0.08, 0.35], "b": [0.02, 0.2]})
    wall_color_range = metadata.get('wall_color_range', {"r": [0.7, 1.0], "g": [0.7, 1.0], "b": [0.7, 1.0]})
    desk_color_range = metadata.get('desk_color_range', {"r": [0.2, 0.6], "g": [0.1, 0.4], "b": [0.02, 0.2]})
    glass_min_transmission = metadata.get('glass_min_transmission', 0.5)
    floor_roughness_range = metadata.get('floor_roughness_range', [0.3, 0.7])

    feedback_parts = []
    score = 0
    details = {}

    # ================================================================
    # Copy result file from container
    # ================================================================
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # ================================================================
    # GATE: If no primary output exists, agent did nothing -> score 0
    # (Lesson 22: output-existence gate prevents do-nothing scoring)
    # ================================================================
    if not result.get('output_exists', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output file found -- agent did not produce classroom_fixed.blend"
        }

    # Extract materials dict from result
    materials = result.get('materials', {})

    # ================================================================
    # CRITERION 1: Floor material (25 points)
    # Must have brown/wood base color + roughness in range
    # ================================================================
    try:
        floor_props = materials.get('floor', {})
        floor_bc = floor_props.get('base_color', [0.5, 0.5, 0.5, 1.0])
        floor_roughness = floor_props.get('roughness', 0.5)
        floor_linked = floor_props.get('base_color_linked', False)
        floor_has_texture = floor_props.get('has_texture', False)
        floor_error = floor_props.get('error', None)

        if floor_error:
            feedback_parts.append(f"Floor: ERROR - {floor_error}")
            details['floor_ok'] = False
        elif _is_grey(floor_bc) and not floor_linked:
            feedback_parts.append("Floor: still grey (unchanged)")
            details['floor_ok'] = False
        else:
            floor_points = 0

            # Color check: either direct color in range OR has a texture (likely wood texture)
            color_ok = _color_in_range(floor_bc, floor_color_range)
            if color_ok:
                floor_points += 15
                feedback_parts.append(
                    f"Floor color OK (R={floor_bc[0]:.2f} G={floor_bc[1]:.2f} B={floor_bc[2]:.2f})"
                )
            elif floor_linked or floor_has_texture:
                # Agent connected a texture node — give generous credit since
                # the default_value may not reflect the actual rendered appearance
                floor_points += 15
                feedback_parts.append(
                    f"Floor has texture node ({floor_props.get('base_color_source_type', 'unknown')})"
                )
            else:
                # Color is not grey but not in expected range — partial credit
                # if it looks brownish (R > G > B)
                if floor_bc[0] > floor_bc[1] > floor_bc[2] and floor_bc[0] > 0.15:
                    floor_points += 10
                    feedback_parts.append(
                        f"Floor color brownish (R={floor_bc[0]:.2f} G={floor_bc[1]:.2f} B={floor_bc[2]:.2f})"
                    )
                else:
                    floor_points += 3
                    feedback_parts.append(
                        f"Floor color changed but not brown (R={floor_bc[0]:.2f} G={floor_bc[1]:.2f} B={floor_bc[2]:.2f})"
                    )

            # Roughness check
            roughness_ok = _in_range(floor_roughness, floor_roughness_range[0], floor_roughness_range[1])
            roughness_linked = floor_props.get('roughness_linked', False)
            if roughness_ok or roughness_linked:
                floor_points += 10
                feedback_parts.append(f"Floor roughness OK ({floor_roughness:.2f})")
            elif not _in_range(floor_roughness, 0.49, 0.51):
                # Changed from default 0.5 — partial credit
                floor_points += 5
                feedback_parts.append(f"Floor roughness changed ({floor_roughness:.2f})")
            else:
                feedback_parts.append(f"Floor roughness unchanged ({floor_roughness:.2f})")

            score += floor_points
            details['floor_ok'] = floor_points >= 15
            details['floor_points'] = floor_points

    except Exception as e:
        feedback_parts.append(f"Floor check error: {str(e)[:60]}")
        details['floor_ok'] = False

    # ================================================================
    # CRITERION 2: Wall material (20 points)
    # Must have light/white base color
    # ================================================================
    try:
        wall_props = materials.get('wall', {})
        wall_bc = wall_props.get('base_color', [0.5, 0.5, 0.5, 1.0])
        wall_linked = wall_props.get('base_color_linked', False)
        wall_has_texture = wall_props.get('has_texture', False)
        wall_error = wall_props.get('error', None)

        if wall_error:
            feedback_parts.append(f"Wall: ERROR - {wall_error}")
            details['wall_ok'] = False
        elif _is_grey(wall_bc) and not wall_linked:
            feedback_parts.append("Wall: still grey (unchanged)")
            details['wall_ok'] = False
        else:
            wall_points = 0

            color_ok = _color_in_range(wall_bc, wall_color_range)
            if color_ok:
                wall_points += 20
                feedback_parts.append(
                    f"Wall color OK (R={wall_bc[0]:.2f} G={wall_bc[1]:.2f} B={wall_bc[2]:.2f})"
                )
            elif wall_linked or wall_has_texture:
                # Texture connected — give credit
                wall_points += 15
                feedback_parts.append(
                    f"Wall has texture node ({wall_props.get('base_color_source_type', 'unknown')})"
                )
            else:
                # Check if it's at least light-colored (all channels > 0.6)
                if all(wall_bc[i] > 0.6 for i in range(3)):
                    wall_points += 15
                    feedback_parts.append(
                        f"Wall color light (R={wall_bc[0]:.2f} G={wall_bc[1]:.2f} B={wall_bc[2]:.2f})"
                    )
                elif any(wall_bc[i] > 0.6 for i in range(3)):
                    wall_points += 8
                    feedback_parts.append(
                        f"Wall color partially light (R={wall_bc[0]:.2f} G={wall_bc[1]:.2f} B={wall_bc[2]:.2f})"
                    )
                else:
                    wall_points += 3
                    feedback_parts.append(
                        f"Wall color changed but not light (R={wall_bc[0]:.2f} G={wall_bc[1]:.2f} B={wall_bc[2]:.2f})"
                    )

            score += wall_points
            details['wall_ok'] = wall_points >= 15
            details['wall_points'] = wall_points

    except Exception as e:
        feedback_parts.append(f"Wall check error: {str(e)[:60]}")
        details['wall_ok'] = False

    # ================================================================
    # CRITERION 3: Desk material (20 points)
    # Must have wood-like brown base color
    # ================================================================
    try:
        desk_props = materials.get('desk', {})
        desk_bc = desk_props.get('base_color', [0.5, 0.5, 0.5, 1.0])
        desk_linked = desk_props.get('base_color_linked', False)
        desk_has_texture = desk_props.get('has_texture', False)
        desk_error = desk_props.get('error', None)

        if desk_error:
            feedback_parts.append(f"Desk: ERROR - {desk_error}")
            details['desk_ok'] = False
        elif _is_grey(desk_bc) and not desk_linked:
            feedback_parts.append("Desk: still grey (unchanged)")
            details['desk_ok'] = False
        else:
            desk_points = 0

            color_ok = _color_in_range(desk_bc, desk_color_range)
            if color_ok:
                desk_points += 20
                feedback_parts.append(
                    f"Desk color OK (R={desk_bc[0]:.2f} G={desk_bc[1]:.2f} B={desk_bc[2]:.2f})"
                )
            elif desk_linked or desk_has_texture:
                desk_points += 15
                feedback_parts.append(
                    f"Desk has texture node ({desk_props.get('base_color_source_type', 'unknown')})"
                )
            else:
                # Partial credit if brownish (R > G > B)
                if desk_bc[0] > desk_bc[1] > desk_bc[2] and desk_bc[0] > 0.15:
                    desk_points += 12
                    feedback_parts.append(
                        f"Desk color brownish (R={desk_bc[0]:.2f} G={desk_bc[1]:.2f} B={desk_bc[2]:.2f})"
                    )
                else:
                    desk_points += 3
                    feedback_parts.append(
                        f"Desk color changed but not brown (R={desk_bc[0]:.2f} G={desk_bc[1]:.2f} B={desk_bc[2]:.2f})"
                    )

            score += desk_points
            details['desk_ok'] = desk_points >= 12
            details['desk_points'] = desk_points

    except Exception as e:
        feedback_parts.append(f"Desk check error: {str(e)[:60]}")
        details['desk_ok'] = False

    # ================================================================
    # CRITERION 4: Glass/window material (20 points)
    # Must have transmission > 0.5
    # ================================================================
    try:
        glass_props = materials.get('glass', {})
        glass_bc = glass_props.get('base_color', [0.5, 0.5, 0.5, 1.0])
        glass_transmission = glass_props.get('transmission', 0.0)
        glass_linked = glass_props.get('base_color_linked', False)
        glass_trans_linked = glass_props.get('transmission_linked', False)
        glass_error = glass_props.get('error', None)

        if glass_error:
            feedback_parts.append(f"Glass: ERROR - {glass_error}")
            details['glass_ok'] = False
        else:
            glass_points = 0

            # Primary check: transmission value
            if glass_transmission >= glass_min_transmission or glass_trans_linked:
                glass_points += 20
                feedback_parts.append(f"Glass transmission OK ({glass_transmission:.2f})")
            elif glass_transmission > 0.1:
                # Some transmission but below threshold — partial credit
                glass_points += 10
                feedback_parts.append(
                    f"Glass transmission low ({glass_transmission:.2f}, need >= {glass_min_transmission})"
                )
            elif not _is_grey(glass_bc) or glass_linked:
                # At least color was changed — minimal credit
                glass_points += 3
                feedback_parts.append(
                    f"Glass color changed but no transmission ({glass_transmission:.2f})"
                )
            else:
                feedback_parts.append(f"Glass unchanged (transmission={glass_transmission:.2f})")

            score += glass_points
            details['glass_ok'] = glass_points >= 15
            details['glass_points'] = glass_points

    except Exception as e:
        feedback_parts.append(f"Glass check error: {str(e)[:60]}")
        details['glass_ok'] = False

    # ================================================================
    # CRITERION 5: File saved correctly (15 points)
    # ================================================================
    try:
        output_exists = result.get('output_exists', False)
        is_valid_blend = result.get('is_valid_blend', False)
        file_created = result.get('file_created', False)
        output_size = result.get('output_size_bytes', 0)

        if output_exists and is_valid_blend and file_created:
            score += 15
            feedback_parts.append(f"File saved OK ({output_size} bytes)")
            details['file_ok'] = True
        elif output_exists and file_created:
            score += 10
            feedback_parts.append(f"File saved (validity uncertain, {output_size} bytes)")
            details['file_ok'] = True
        elif output_exists:
            score += 5
            feedback_parts.append("File exists but may be pre-existing")
            details['file_ok'] = False
        else:
            feedback_parts.append("Output file NOT saved")
            details['file_ok'] = False

    except Exception as e:
        feedback_parts.append(f"File check error: {str(e)[:60]}")
        details['file_ok'] = False

    # ================================================================
    # NEGATIVE CHECK: Must have changed at least some materials
    # ================================================================
    summary = materials.get('_summary', {})
    materials_changed = summary.get('materials_changed', 0)
    details['materials_changed'] = materials_changed

    if materials_changed == 0 and not any(
        details.get(k, False) for k in ['floor_ok', 'wall_ok', 'desk_ok', 'glass_ok']
    ):
        feedback_parts.append("FAIL: No materials were changed from grey")
        score = min(score, 10)

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    passed = score >= 70

    if passed and score >= 90:
        feedback_parts.append("Excellent material work!")
    elif passed:
        feedback_parts.append("Materials fixed successfully")
    else:
        feedback_parts.append(f"FAIL: Score {score}/100 below threshold (70)")

    details['score'] = score

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
