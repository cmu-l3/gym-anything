#!/usr/bin/env python3
"""Verifier for multipass_render_composite task.

Scoring (100 points total, pass threshold 60):
  - Output scene exists and > 10KB:                5 pts
  - Mantra node has extra image planes configured: 10 pts
  - direct_diffuse AOV present:                     8 pts
  - indirect_diffuse AOV present:                   8 pts
  - direct_specular AOV present:                    8 pts
  - emission AOV present:                           8 pts
  - At least one rendered pass file exists:         8 pts
  - COP2 network (/img) exists with nodes:         15 pts
  - COP network has file input nodes:              10 pts
  - COP network has merge/composite node:          10 pts
  - Final composite file exists and > 10KB:        10 pts
"""

import json
import os
import tempfile


def verify_multipass_render_composite(traj, env_info, task_info):
    """Verify the multipass render and composite task.

    Uses copy_from_env to pull /tmp/task_result.json from the environment,
    then scores based on Mantra AOV configuration and COP compositing network.

    Do-nothing baseline: the pre-built scene exists but has no extra image
    planes and no COP network, yielding ~5 pts (scene exists) -- well below
    the 60-point pass threshold.
    """

    score = 0
    feedback_parts = []

    # ------------------------------------------------------------------
    # Retrieve the result file from the environment
    # ------------------------------------------------------------------
    result_file = task_info.get("metadata", {}).get("result_file", "/tmp/task_result.json")
    copy_fn = env_info.get("copy_from_env")

    local = os.path.join(tempfile.mkdtemp(), "result.json")
    try:
        copy_fn(result_file, local)
        with open(local) as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not retrieve result file: {e}",
        }

    # ------------------------------------------------------------------
    # 1. Output scene exists and > 10KB (5 pts)
    # ------------------------------------------------------------------
    scene_exists = result_data.get("scene_exists", False)
    scene_size = result_data.get("scene_size_bytes", 0)

    if scene_exists and scene_size > 10240:
        score += 5
        feedback_parts.append(f"Scene exists ({scene_size} bytes): +5")
    elif scene_exists:
        score += 2
        feedback_parts.append(
            f"Scene exists but small ({scene_size} bytes): +2"
        )
    else:
        feedback_parts.append("Output scene not found: +0")

    # ------------------------------------------------------------------
    # 2. Mantra node has extra image planes configured (10 pts)
    # ------------------------------------------------------------------
    num_extra_planes = result_data.get("num_extra_planes", 0)
    mantra_found = result_data.get("mantra_node_found", False)

    if mantra_found and num_extra_planes >= 4:
        score += 10
        feedback_parts.append(
            f"Mantra has {num_extra_planes} extra image planes: +10"
        )
    elif mantra_found and num_extra_planes > 0:
        partial = min(10, num_extra_planes * 2)
        score += partial
        feedback_parts.append(
            f"Mantra has {num_extra_planes} extra planes (need >=4): +{partial}"
        )
    else:
        feedback_parts.append("No extra image planes configured: +0")

    # ------------------------------------------------------------------
    # 3-6. Check individual AOV passes (8 pts each, 32 pts total)
    # ------------------------------------------------------------------
    extra_plane_variables = result_data.get("extra_plane_variables", [])
    # Normalize to lowercase for matching
    plane_vars_lower = [v.lower() for v in extra_plane_variables]

    required_passes = {
        "direct_diffuse": 8,
        "indirect_diffuse": 8,
        "direct_specular": 8,
        "emission": 8,
    }

    for pass_name, pts in required_passes.items():
        # Check exact match and common variations
        found = False
        search_terms = [pass_name.lower()]

        # Add variations: with/without underscores, short forms
        if "_" in pass_name:
            search_terms.append(pass_name.replace("_", "").lower())

        for var in plane_vars_lower:
            for term in search_terms:
                if term in var or var in term:
                    found = True
                    break
            if found:
                break

        if found:
            score += pts
            feedback_parts.append(f"AOV '{pass_name}' found: +{pts}")
        else:
            feedback_parts.append(f"AOV '{pass_name}' NOT found: +0")

    # ------------------------------------------------------------------
    # 7. At least one rendered pass file exists (8 pts)
    # ------------------------------------------------------------------
    pass_files_count = result_data.get("pass_files_count", 0)

    if pass_files_count > 0:
        score += 8
        feedback_parts.append(
            f"Rendered pass files found ({pass_files_count}): +8"
        )
    else:
        feedback_parts.append("No rendered pass files found: +0")

    # ------------------------------------------------------------------
    # 8. COP2 network (/img) exists with nodes (15 pts)
    # ------------------------------------------------------------------
    cop_exists = result_data.get("cop_network_exists", False)
    cop_node_count = result_data.get("cop_node_count", 0)

    if cop_exists and cop_node_count >= 2:
        score += 15
        feedback_parts.append(
            f"COP2 network exists with {cop_node_count} nodes: +15"
        )
    elif cop_exists and cop_node_count > 0:
        score += 8
        feedback_parts.append(
            f"COP2 network exists with {cop_node_count} node(s) (need >=2): +8"
        )
    elif cop_exists:
        score += 3
        feedback_parts.append("COP2 network exists but empty: +3")
    else:
        feedback_parts.append("No COP2 network found: +0")

    # ------------------------------------------------------------------
    # 9. COP network has file input nodes (10 pts)
    # ------------------------------------------------------------------
    cop_has_file = result_data.get("cop_has_file_nodes", False)
    cop_file_count = result_data.get("cop_file_node_count", 0)

    if cop_has_file and cop_file_count >= 2:
        score += 10
        feedback_parts.append(
            f"COP has {cop_file_count} file input nodes: +10"
        )
    elif cop_has_file:
        score += 5
        feedback_parts.append(
            f"COP has {cop_file_count} file input node(s) (need >=2): +5"
        )
    else:
        feedback_parts.append("No COP file input nodes found: +0")

    # ------------------------------------------------------------------
    # 10. COP network has merge/composite node (10 pts)
    # ------------------------------------------------------------------
    cop_has_merge = result_data.get("cop_has_merge_or_composite", False)

    if cop_has_merge:
        score += 10
        feedback_parts.append("COP has merge/composite node: +10")
    else:
        feedback_parts.append("No COP merge/composite node found: +0")

    # ------------------------------------------------------------------
    # 11. Final composite file exists and > 10KB (10 pts)
    # ------------------------------------------------------------------
    composite_exists = result_data.get("composite_exists", False)
    composite_size = result_data.get("composite_size_bytes", 0)

    if composite_exists and composite_size > 10240:
        score += 10
        feedback_parts.append(
            f"Final composite exists ({composite_size} bytes): +10"
        )
    elif composite_exists:
        score += 5
        feedback_parts.append(
            f"Final composite exists but small ({composite_size} bytes): +5"
        )
    else:
        feedback_parts.append("Final composite not found: +0")

    # ------------------------------------------------------------------
    # Determine pass/fail
    # ------------------------------------------------------------------
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "scene_exists": scene_exists,
            "scene_size": scene_size,
            "mantra_found": mantra_found,
            "num_extra_planes": num_extra_planes,
            "extra_plane_variables": extra_plane_variables,
            "pass_files_count": pass_files_count,
            "cop_network_exists": cop_exists,
            "cop_node_count": cop_node_count,
            "cop_has_file_nodes": cop_has_file,
            "cop_has_merge": cop_has_merge,
            "composite_exists": composite_exists,
            "composite_size": composite_size,
        },
    }
