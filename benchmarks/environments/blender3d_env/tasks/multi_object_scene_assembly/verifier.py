#!/usr/bin/env python3
"""
Verifier for multi_object_scene_assembly task.

ROBUST MULTI-SIGNAL VERIFICATION:
1. All 5 primitive mesh types present (25 pts -- 5 pts each)
2. 5+ distinct materials with different base colors (25 pts)
3. Objects arranged without overlap / reasonable spacing (15 pts)
4. Ground plane exists (10 pts)
5. 2+ lights in the scene (10 pts)
6. Blend file saved correctly (15 pts)

Pass threshold: 70
"""

import json
import math
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_MESH_TYPES = ["sphere", "cube", "cylinder", "cone", "torus"]
POINTS_PER_MESH_TYPE = 5       # 5 types x 5 pts = 25
POINTS_MATERIALS = 25
POINTS_SPACING = 15
POINTS_GROUND_PLANE = 10
POINTS_LIGHTS = 10
POINTS_FILE_SAVED = 15
PASS_THRESHOLD = 70
MIN_COLOR_DIFF = 0.1           # Minimum difference in at least one RGB channel
MIN_SPACING = 1.5              # Minimum pairwise distance between non-ground meshes


def _colors_are_distinct(color_a, color_b, threshold=MIN_COLOR_DIFF):
    """Check if two RGBA colors differ by at least threshold in any RGB channel."""
    if not color_a or not color_b:
        return True  # Can't compare, assume distinct
    for i in range(3):  # R, G, B only
        if abs(color_a[i] - color_b[i]) >= threshold:
            return True
    return False


def _count_distinct_colors(materials_dict):
    """
    Given a dict of {material_name: [r, g, b, a]}, count how many
    have pairwise-distinct base colors.

    Returns the size of the largest subset where all colors are
    mutually distinct. Uses a greedy approach.
    """
    names = list(materials_dict.keys())
    colors = [materials_dict[n] for n in names]

    if len(colors) <= 1:
        return len(colors)

    # Greedy: add materials one by one if they are distinct from all already added
    distinct_set = [0]  # Start with first material
    for i in range(1, len(colors)):
        all_distinct = True
        for j in distinct_set:
            if not _colors_are_distinct(colors[i], colors[j]):
                all_distinct = False
                break
        if all_distinct:
            distinct_set.append(i)

    return len(distinct_set)


def verify_multi_object_scene_assembly(traj, env_info, task_info):
    """
    Verify that the multi-object showcase scene was built correctly.

    Uses MULTIPLE INDEPENDENT SIGNALS to prevent gaming.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output = metadata.get('expected_output', '/home/ga/BlenderProjects/showcase_scene.blend')
    min_material_count = metadata.get('min_material_count', 5)
    min_light_count = metadata.get('min_light_count', 2)
    min_spacing = metadata.get('min_spacing', MIN_SPACING)
    required_mesh_types = metadata.get('required_mesh_types', REQUIRED_MESH_TYPES)

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
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
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
            "feedback": "No output file found -- agent did not produce showcase_scene.blend"
        }

    scene = result.get('scene_analysis', {})

    # ================================================================
    # SUBTASK 1: All 5 primitive mesh types present (25 points)
    # 5 pts each for sphere, cube, cylinder, cone, torus
    # ================================================================
    try:
        detected_types = scene.get('detected_mesh_types', {})
        found_types = []
        missing_types = []

        for mesh_type in required_mesh_types:
            if mesh_type in detected_types and len(detected_types[mesh_type]) > 0:
                score += POINTS_PER_MESH_TYPE
                found_types.append(mesh_type)
            else:
                missing_types.append(mesh_type)

        if missing_types:
            feedback_parts.append(f"Primitives: found {len(found_types)}/5 (missing: {', '.join(missing_types)})")
        else:
            feedback_parts.append("All 5 primitive types present")

        details["found_mesh_types"] = found_types
        details["missing_mesh_types"] = missing_types
    except Exception as e:
        feedback_parts.append(f"Mesh type check error: {str(e)[:50]}")
        details["mesh_type_error"] = str(e)

    # ================================================================
    # SUBTASK 2: 5+ distinct materials with different base colors (25 points)
    # ================================================================
    try:
        all_materials = scene.get('all_materials', {})
        unique_material_count = scene.get('unique_material_count', 0)

        # Count how many materials have truly distinct colors
        distinct_color_count = _count_distinct_colors(all_materials)

        # Also check that materials are actually assigned to the 5 mesh objects
        mesh_objects = scene.get('mesh_objects', [])
        objects_with_materials = 0
        for mobj in mesh_objects:
            mats = mobj.get('materials', [])
            if mats and any(m.get('name') for m in mats):
                objects_with_materials += 1

        if distinct_color_count >= min_material_count:
            score += POINTS_MATERIALS
            feedback_parts.append(f"Materials: {distinct_color_count} distinct colors ({unique_material_count} total materials)")
        elif distinct_color_count >= 3:
            # Partial credit: proportional
            partial = int(POINTS_MATERIALS * distinct_color_count / min_material_count)
            score += partial
            feedback_parts.append(f"Materials: {distinct_color_count}/{min_material_count} distinct colors ({partial}/{POINTS_MATERIALS} pts)")
        elif unique_material_count >= min_material_count:
            # Materials exist but colors too similar
            score += 10
            feedback_parts.append(f"Materials: {unique_material_count} materials but only {distinct_color_count} distinct colors")
        else:
            feedback_parts.append(f"Materials: only {unique_material_count} materials (need {min_material_count})")

        details["unique_material_count"] = unique_material_count
        details["distinct_color_count"] = distinct_color_count
        details["objects_with_materials"] = objects_with_materials
        details["material_names"] = list(all_materials.keys())
    except Exception as e:
        feedback_parts.append(f"Material check error: {str(e)[:50]}")
        details["material_error"] = str(e)

    # ================================================================
    # SUBTASK 3: Objects arranged without overlap (15 points)
    # Min pairwise distance between non-ground mesh objects > threshold
    # ================================================================
    try:
        min_pairwise_distance = scene.get('min_pairwise_distance', 0.0)
        non_ground_mesh_count = scene.get('non_ground_mesh_count', 0)

        if non_ground_mesh_count >= 5 and min_pairwise_distance >= min_spacing:
            score += POINTS_SPACING
            feedback_parts.append(f"Spacing OK (min dist: {min_pairwise_distance:.2f})")
        elif non_ground_mesh_count >= 5 and min_pairwise_distance >= min_spacing * 0.5:
            # Partial credit for objects that are close but not overlapping
            score += 10
            feedback_parts.append(f"Spacing marginal (min dist: {min_pairwise_distance:.2f}, need {min_spacing})")
        elif non_ground_mesh_count >= 5 and min_pairwise_distance > 0.1:
            score += 5
            feedback_parts.append(f"Spacing tight (min dist: {min_pairwise_distance:.2f})")
        elif non_ground_mesh_count < 5:
            feedback_parts.append(f"Only {non_ground_mesh_count} non-ground meshes (need 5)")
        else:
            feedback_parts.append(f"Objects overlap or stacked (min dist: {min_pairwise_distance:.2f})")

        details["min_pairwise_distance"] = min_pairwise_distance
        details["non_ground_mesh_count"] = non_ground_mesh_count
    except Exception as e:
        feedback_parts.append(f"Spacing check error: {str(e)[:50]}")
        details["spacing_error"] = str(e)

    # ================================================================
    # SUBTASK 4: Ground plane exists (10 points)
    # ================================================================
    try:
        has_ground_plane = scene.get('has_ground_plane', False)
        ground_planes = scene.get('ground_planes', [])

        if has_ground_plane and len(ground_planes) > 0:
            score += POINTS_GROUND_PLANE
            feedback_parts.append(f"Ground plane found: {ground_planes[0]}")
        else:
            feedback_parts.append("No ground plane detected")

        details["has_ground_plane"] = has_ground_plane
        details["ground_plane_names"] = ground_planes
    except Exception as e:
        feedback_parts.append(f"Ground plane check error: {str(e)[:50]}")
        details["ground_plane_error"] = str(e)

    # ================================================================
    # SUBTASK 5: 2+ lights exist (10 points)
    # ================================================================
    try:
        light_count = scene.get('light_count', 0)
        light_objects = scene.get('light_objects', [])

        if light_count >= min_light_count:
            score += POINTS_LIGHTS
            light_names = [l.get('name', '?') for l in light_objects]
            feedback_parts.append(f"Lights: {light_count} ({', '.join(light_names)})")
        elif light_count == 1:
            score += 5
            feedback_parts.append(f"Only 1 light (need {min_light_count})")
        else:
            feedback_parts.append(f"No lights found (need {min_light_count})")

        details["light_count"] = light_count
    except Exception as e:
        feedback_parts.append(f"Light check error: {str(e)[:50]}")
        details["light_error"] = str(e)

    # ================================================================
    # SUBTASK 6: Blend file saved correctly (15 points)
    # ================================================================
    try:
        output_exists = result.get('output_exists', False)
        is_valid_blend = result.get('is_valid_blend', False)
        output_size = result.get('output_size_bytes', 0)

        if output_exists and is_valid_blend and output_size > 1000:
            score += POINTS_FILE_SAVED
            feedback_parts.append(f"File saved ({output_size} bytes)")
        elif output_exists and is_valid_blend:
            score += 10
            feedback_parts.append(f"File saved but small ({output_size} bytes)")
        elif output_exists:
            score += 5
            feedback_parts.append("File exists but may not be valid blend")
        else:
            feedback_parts.append("Output file NOT saved")

        details["file_exists"] = output_exists
        details["file_valid"] = is_valid_blend
        details["file_size"] = output_size
    except Exception as e:
        feedback_parts.append(f"File check error: {str(e)[:50]}")
        details["file_error"] = str(e)

    # ================================================================
    # CALCULATE FINAL RESULT
    # ================================================================
    passed = score >= PASS_THRESHOLD

    if passed and score >= 90:
        feedback_parts.append("Excellent showcase scene!")
    elif passed:
        feedback_parts.append("Showcase scene assembled successfully")
    else:
        feedback_parts.append(f"Score {score}/100 below threshold ({PASS_THRESHOLD})")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details
    }
