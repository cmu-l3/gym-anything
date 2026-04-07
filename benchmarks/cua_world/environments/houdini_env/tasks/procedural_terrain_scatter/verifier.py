#!/usr/bin/env python3
"""Verifier for procedural_terrain_scatter task.

Scoring breakdown (100 points total, pass threshold 60):
  - Scene file exists and > 10KB:                    10 pts
  - HeightField terrain node exists:                 15 pts
  - Erosion applied (thermal or hydraulic):          15 pts
  - Scatter/copy-to-points exists:                   10 pts
    - with >= 50 instances:                           5 pts (bonus)
  - Material exists in /mat:                         10 pts
  - HDRI environment light configured:               10 pts
  - Camera node exists:                               5 pts
  - Render node configured in /out:                   5 pts
  - Render image exists and > 50KB:                  15 pts
                                                    --------
                                              Total: 100 pts
"""

import json
import os
import tempfile


def verify_procedural_terrain_scatter(traj, env_info, task_info):
    """Verify the procedural terrain scatter task completion.

    Reads /tmp/task_result.json (via copy_from_env) produced by export_result.sh
    and scores the agent's work based on presence and quality of scene components.
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
    min_scatter = task_info.get("metadata", {}).get("min_scatter_count", 50)

    # ================================================================
    # 1. Scene file exists and > 10KB (10 pts)
    # ================================================================
    scene_exists = data.get("scene_exists", False)
    scene_size = data.get("scene_size_bytes", 0)

    if scene_exists and scene_size > 10240:
        score += 10
        feedback_parts.append(f"[+10] Scene file exists ({scene_size} bytes)")
    elif scene_exists:
        score += 3
        feedback_parts.append(
            f"[+3] Scene file exists but is small ({scene_size} bytes, expected > 10KB)"
        )
    else:
        feedback_parts.append("[-] Scene file not found")

    # ================================================================
    # 2. HeightField terrain node exists (15 pts)
    # ================================================================
    has_heightfield = data.get("has_heightfield", False)
    hf_types = data.get("heightfield_node_types", [])

    if has_heightfield:
        score += 15
        feedback_parts.append(f"[+15] HeightField terrain found: {hf_types}")
    else:
        feedback_parts.append("[-] No HeightField terrain node found")

    # ================================================================
    # 3. Erosion applied (15 pts)
    # ================================================================
    has_erosion = data.get("has_erosion", False)
    erosion_types = data.get("erosion_node_types", [])

    if has_erosion:
        score += 15
        feedback_parts.append(f"[+15] Erosion applied: {erosion_types}")
    else:
        feedback_parts.append("[-] No erosion nodes found (expected heightfield_erode)")

    # ================================================================
    # 4. Scatter / Copy-to-Points (10 pts node + 5 pts count >= 50)
    # ================================================================
    has_scatter = data.get("has_scatter_or_copy", False)
    scatter_types = data.get("scatter_copy_node_types", [])
    scatter_count = data.get("scatter_point_count", 0)

    if has_scatter:
        score += 10
        feedback_parts.append(f"[+10] Scatter/copy node found: {scatter_types}")

        if scatter_count >= min_scatter:
            score += 5
            feedback_parts.append(
                f"[+5] Scatter count meets threshold ({scatter_count} >= {min_scatter})"
            )
        else:
            feedback_parts.append(
                f"[-] Scatter count below threshold ({scatter_count} < {min_scatter})"
            )
    else:
        feedback_parts.append("[-] No scatter or copy-to-points node found")

    # ================================================================
    # 5. Material exists in /mat (10 pts)
    # ================================================================
    has_material = data.get("has_material", False)
    material_names = data.get("material_names", [])

    if has_material:
        score += 10
        feedback_parts.append(f"[+10] Material(s) found in /mat: {material_names}")
    else:
        feedback_parts.append("[-] No materials found in /mat context")

    # ================================================================
    # 6. HDRI environment light configured (10 pts)
    # ================================================================
    has_env_light = data.get("has_env_light", False)
    env_light_hdri = data.get("env_light_hdri_path", "")

    if has_env_light and env_light_hdri:
        score += 10
        feedback_parts.append(f"[+10] Environment light with HDRI: {env_light_hdri}")
    elif has_env_light:
        score += 5
        feedback_parts.append("[+5] Environment light exists but no HDRI path set")
    else:
        feedback_parts.append("[-] No environment light found")

    # ================================================================
    # 7. Camera node exists (5 pts)
    # ================================================================
    has_camera = data.get("has_camera", False)

    if has_camera:
        score += 5
        feedback_parts.append("[+5] Camera node found")
    else:
        feedback_parts.append("[-] No camera node found in /obj")

    # ================================================================
    # 8. Render node configured in /out (5 pts)
    # ================================================================
    has_render_node = data.get("has_render_node", False)
    render_types = data.get("render_node_types", [])

    if has_render_node:
        score += 5
        feedback_parts.append(f"[+5] Render node found in /out: {render_types}")
    else:
        feedback_parts.append("[-] No render node (mantra/karma) found in /out")

    # ================================================================
    # 9. Render image exists and > 50KB (15 pts)
    # ================================================================
    render_exists = data.get("render_exists", False)
    render_size = data.get("render_size_bytes", 0)

    if render_exists and render_size > 51200:
        score += 15
        feedback_parts.append(
            f"[+15] Render image exists and is substantial ({render_size} bytes)"
        )
    elif render_exists and render_size > 0:
        score += 5
        feedback_parts.append(
            f"[+5] Render image exists but is small ({render_size} bytes, expected > 50KB)"
        )
    else:
        feedback_parts.append("[-] No render image found")

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
