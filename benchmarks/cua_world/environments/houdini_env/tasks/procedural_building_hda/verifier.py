#!/usr/bin/env python3
"""Verifier for procedural_building_hda task.

Scoring breakdown (100 points total, pass threshold 60):
  - HDA file exists and > 1KB:                         10 pts
  - HDA installs successfully (valid HDA format):       5 pts
  - Has building_width parameter:                       8 pts
  - Has building_height parameter:                      8 pts
  - Has num_floors parameter:                           8 pts
  - Has window_density parameter:                       8 pts
  - Generated geometry has polygons (500-50000):        8 pts
  - Geometry has UVs:                                   8 pts
  - Test scene exists:                                  5 pts
  - At least 3 HDA instances in test scene:            10 pts
  - Instances have different parameter values:          7 pts
  - Polygon count changes with different num_floors:    8 pts
  - Geometry height changes with building_height:       7 pts
                                                      --------
                                                Total: 100 pts
"""

import json
import os
import tempfile


def verify_procedural_building_hda(traj, env_info, task_info):
    """Verify the procedural building HDA task completion.

    Reads /tmp/task_result.json (via copy_from_env) produced by export_result.sh
    and scores the agent's work based on HDA quality, parameters, and test scene.
    """
    # ================================================================
    # Retrieve the result file from the environment
    # ================================================================
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/task_result.json")
    copy_fn = env_info.get("copy_from_env")

    local = os.path.join(tempfile.mkdtemp(), "result.json")
    try:
        copy_fn(result_file, local)
        with open(local) as f:
            data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}",
        }

    score = 0
    feedback_parts = []
    min_instances = task_info.get("metadata", {}).get("min_instances", 3)

    # ================================================================
    # 1. HDA file exists and > 1KB (10 pts)
    # ================================================================
    hda_exists = data.get("hda_exists", False)
    hda_size = data.get("hda_size_bytes", 0)

    if hda_exists and hda_size > 1024:
        score += 10
        feedback_parts.append(f"[+10] HDA file exists ({hda_size} bytes)")
    elif hda_exists:
        score += 3
        feedback_parts.append(
            f"[+3] HDA file exists but is small ({hda_size} bytes, expected > 1KB)"
        )
    else:
        feedback_parts.append("[-] HDA file not found")

    # ================================================================
    # 2. HDA installs successfully (5 pts)
    # ================================================================
    hda_installs = data.get("hda_installs", False)

    if hda_installs:
        score += 5
        feedback_parts.append("[+5] HDA installs successfully (valid format)")
    else:
        feedback_parts.append("[-] HDA failed to install or is not a valid HDA file")

    # ================================================================
    # 3. Has building_width parameter (8 pts)
    # ================================================================
    has_building_width = data.get("has_building_width", False)

    if has_building_width:
        score += 8
        feedback_parts.append("[+8] Has building_width parameter")
    else:
        feedback_parts.append("[-] Missing building_width parameter")

    # ================================================================
    # 4. Has building_height parameter (8 pts)
    # ================================================================
    has_building_height = data.get("has_building_height", False)

    if has_building_height:
        score += 8
        feedback_parts.append("[+8] Has building_height parameter")
    else:
        feedback_parts.append("[-] Missing building_height parameter")

    # ================================================================
    # 5. Has num_floors parameter (8 pts)
    # ================================================================
    has_num_floors = data.get("has_num_floors", False)

    if has_num_floors:
        score += 8
        feedback_parts.append("[+8] Has num_floors parameter")
    else:
        feedback_parts.append("[-] Missing num_floors parameter")

    # ================================================================
    # 6. Has window_density parameter (8 pts)
    # ================================================================
    has_window_density = data.get("has_window_density", False)

    if has_window_density:
        score += 8
        feedback_parts.append("[+8] Has window_density parameter")
    else:
        feedback_parts.append("[-] Missing window_density parameter")

    # ================================================================
    # 7. Generated geometry has polygons in range 500-50000 (8 pts)
    # ================================================================
    default_poly_count = data.get("default_poly_count", 0)

    if 500 <= default_poly_count <= 50000:
        score += 8
        feedback_parts.append(
            f"[+8] Geometry polygon count in range ({default_poly_count} polys)"
        )
    elif default_poly_count > 0:
        score += 3
        feedback_parts.append(
            f"[+3] Geometry has polygons but count out of range "
            f"({default_poly_count}, expected 500-50000)"
        )
    else:
        feedback_parts.append("[-] No geometry generated or zero polygon count")

    # ================================================================
    # 8. Geometry has UVs (8 pts)
    # ================================================================
    default_has_uvs = data.get("default_has_uvs", False)

    if default_has_uvs:
        score += 8
        feedback_parts.append("[+8] Geometry has UV attribute")
    else:
        feedback_parts.append("[-] No UV attribute found on geometry")

    # ================================================================
    # 9. Test scene exists (5 pts)
    # ================================================================
    scene_exists = data.get("scene_exists", False)

    if scene_exists:
        score += 5
        feedback_parts.append("[+5] Test scene file exists")
    else:
        feedback_parts.append("[-] Test scene file not found")

    # ================================================================
    # 10. At least 3 HDA instances in test scene (10 pts)
    # ================================================================
    instance_count = data.get("instance_count", 0)

    if instance_count >= min_instances:
        score += 10
        feedback_parts.append(
            f"[+10] Test scene has {instance_count} HDA instances "
            f"(>= {min_instances} required)"
        )
    elif instance_count > 0:
        # Partial credit: proportional to how many instances were created
        partial = int(10 * instance_count / min_instances)
        score += partial
        feedback_parts.append(
            f"[+{partial}] Test scene has {instance_count} HDA instances "
            f"(need {min_instances})"
        )
    else:
        feedback_parts.append("[-] No HDA instances found in test scene")

    # ================================================================
    # 11. Instances have different parameter values (7 pts)
    # ================================================================
    instance_params = data.get("instance_params", [])
    has_different_params = False

    if len(instance_params) >= 2:
        # Check if at least two instances differ in any parameter
        param_sets = []
        for ip in instance_params:
            # Create a hashable representation of the parameter values
            param_tuple = tuple(sorted(ip.items()))
            param_sets.append(param_tuple)
        if len(set(param_sets)) >= 2:
            has_different_params = True

    if has_different_params:
        score += 7
        feedback_parts.append("[+7] Instances have different parameter values")
    elif len(instance_params) >= 2:
        feedback_parts.append("[-] Instances exist but have identical parameter values")
    else:
        feedback_parts.append("[-] Not enough instances to compare parameters")

    # ================================================================
    # 12. Polygon count changes with different num_floors (8 pts)
    # ================================================================
    poly_count_varies = data.get("poly_count_varies_with_floors", False)

    if poly_count_varies:
        score += 8
        feedback_parts.append(
            "[+8] Polygon count changes when num_floors is varied"
        )
    else:
        feedback_parts.append(
            "[-] Polygon count does not change with different num_floors values"
        )

    # ================================================================
    # 13. Geometry height changes with building_height parameter (7 pts)
    # ================================================================
    height_varies = data.get("height_varies_with_param", False)

    if height_varies:
        score += 7
        feedback_parts.append(
            "[+7] Geometry height changes when building_height parameter is varied"
        )
    else:
        feedback_parts.append(
            "[-] Geometry height does not respond to building_height parameter"
        )

    # ================================================================
    # FINAL RESULT
    # ================================================================
    passed = score >= 60
    feedback = f"Score: {score}/100 (pass threshold: 60). " + " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
    }
