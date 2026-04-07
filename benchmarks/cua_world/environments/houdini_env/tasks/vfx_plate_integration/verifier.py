#!/usr/bin/env python3
"""Verifier for vfx_plate_integration task.

Scoring breakdown (100 points total, pass threshold 60):
  - Output scene exists and > 10KB:                     5 pts
  - Ground plane geometry exists:                       8 pts
  - Shadow catcher material exists (matte-like):       12 pts
  - Shadow catcher assigned to ground plane:            5 pts
  - Chrome/reflective material exists (metallic>0.5):  10 pts
  - Chrome material assigned to bunny:                  5 pts
  - Mantra render node with output path:                5 pts
  - Separate render passes (>=2 paths or extra planes):10 pts
  - COP2 network exists with >= 3 nodes:              10 pts
  - COP network references bg_plate.jpg:               5 pts
  - COP has composite/merge operations:                 5 pts
  - Any rendered file in integration/ dir:             10 pts
  - Final composite exists and > 10KB:                 10 pts
                                                       --------
                                                 Total: 100 pts

Do-nothing baseline: source scene exists (~5 pts for scene), passed=False.
"""

import json
import os
import tempfile


def verify_vfx_plate_integration(traj, env_info, task_info):
    """Verify the VFX plate integration task completion.

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

    # ================================================================
    # 1. Output scene exists and > 10KB (5 pts)
    # ================================================================
    scene_exists = data.get("scene_exists", False)
    scene_size = data.get("scene_size_bytes", 0)

    if scene_exists and scene_size > 10240:
        score += 5
        feedback_parts.append(f"[+5] Output scene exists ({scene_size} bytes)")
    elif scene_exists:
        score += 2
        feedback_parts.append(
            f"[+2] Output scene exists but small ({scene_size} bytes, expected > 10KB)"
        )
    else:
        feedback_parts.append("[-] Output scene file not found")

    # ================================================================
    # 2. Ground plane geometry exists (8 pts)
    # ================================================================
    has_ground_plane = data.get("has_ground_plane", False)
    ground_plane_name = data.get("ground_plane_name", "")

    if has_ground_plane:
        score += 8
        feedback_parts.append(f"[+8] Ground plane geometry found: '{ground_plane_name}'")
    else:
        feedback_parts.append("[-] No ground plane geometry found in /obj")

    # ================================================================
    # 3. Shadow catcher material exists (12 pts)
    # ================================================================
    has_shadow_catcher = data.get("has_shadow_catcher_material", False)
    shadow_catcher_name = data.get("shadow_catcher_material_name", "")

    if has_shadow_catcher:
        score += 12
        feedback_parts.append(
            f"[+12] Shadow catcher/matte material found: '{shadow_catcher_name}'"
        )
    else:
        feedback_parts.append("[-] No shadow catcher/matte material found in /mat")

    # ================================================================
    # 4. Shadow catcher assigned to ground plane (5 pts)
    # ================================================================
    ground_has_mat = data.get("ground_plane_has_material", False)

    if ground_has_mat:
        score += 5
        mat_path = data.get("ground_plane_material_path", "")
        feedback_parts.append(
            f"[+5] Ground plane has material assigned: '{mat_path}'"
        )
    elif has_ground_plane:
        feedback_parts.append("[-] Ground plane exists but no material assigned")
    else:
        feedback_parts.append("[-] No ground plane to check material assignment")

    # ================================================================
    # 5. Chrome/reflective material exists (10 pts)
    # ================================================================
    has_chrome = data.get("has_chrome_material", False)
    chrome_name = data.get("chrome_material_name", "")
    chrome_metallic = data.get("chrome_metallic", 0)

    if has_chrome:
        score += 10
        feedback_parts.append(
            f"[+10] Chrome/reflective material found: '{chrome_name}' "
            f"(metallic={chrome_metallic})"
        )
    else:
        # Partial credit if any material with moderate metallic exists
        material_names = data.get("material_names", [])
        if chrome_metallic > 0.3:
            score += 4
            feedback_parts.append(
                f"[+4] Partial: material with metallic={chrome_metallic} found "
                f"(expected > 0.5 for full credit)"
            )
        else:
            feedback_parts.append(
                f"[-] No chrome/reflective material found (materials: {material_names})"
            )

    # ================================================================
    # 6. Chrome material assigned to bunny (5 pts)
    # ================================================================
    bunny_has_mat = data.get("bunny_has_material", False)

    if bunny_has_mat:
        score += 5
        bunny_mat_path = data.get("bunny_material_path", "")
        feedback_parts.append(
            f"[+5] Bunny has material assigned: '{bunny_mat_path}'"
        )
    else:
        feedback_parts.append("[-] Bunny geometry has no material assigned")

    # ================================================================
    # 7. Mantra render node with output path (5 pts)
    # ================================================================
    has_mantra = data.get("has_mantra_node", False)
    mantra_output = data.get("mantra_output_path", "")

    if has_mantra and mantra_output:
        score += 5
        feedback_parts.append(
            f"[+5] Mantra render node configured with output: '{mantra_output}'"
        )
    elif has_mantra:
        score += 2
        feedback_parts.append("[+2] Mantra render node exists but no output path set")
    else:
        feedback_parts.append("[-] No Mantra render node found in /out")

    # ================================================================
    # 8. Separate render passes configured (10 pts)
    # ================================================================
    has_separate_passes = data.get("has_separate_passes", False)
    pass_count = data.get("pass_count", 0)
    extra_planes = data.get("extra_image_planes", [])

    if has_separate_passes:
        score += 10
        feedback_parts.append(
            f"[+10] Separate render passes configured "
            f"(pass_count={pass_count}, extra_planes={len(extra_planes)})"
        )
    elif has_mantra:
        feedback_parts.append(
            "[-] Mantra node found but no separate passes "
            "(expected >=2 output paths or extra image planes)"
        )
    else:
        feedback_parts.append("[-] No render passes configured")

    # ================================================================
    # 9. COP2 network exists with >= 3 nodes (10 pts)
    # ================================================================
    has_cop = data.get("has_cop_network", False)
    cop_count = data.get("cop_node_count", 0)

    if has_cop and cop_count >= 3:
        score += 10
        feedback_parts.append(
            f"[+10] COP2 compositing network with {cop_count} nodes"
        )
    elif has_cop and cop_count >= 1:
        score += 4
        feedback_parts.append(
            f"[+4] COP2 network exists but only {cop_count} nodes (expected >= 3)"
        )
    else:
        feedback_parts.append("[-] No COP2 compositing network found in /img")

    # ================================================================
    # 10. COP network references bg_plate.jpg (5 pts)
    # ================================================================
    cop_refs_bg = data.get("cop_references_bg_plate", False)

    if cop_refs_bg:
        score += 5
        feedback_parts.append("[+5] COP network references bg_plate.jpg")
    elif has_cop:
        feedback_parts.append("[-] COP network exists but does not reference bg_plate.jpg")
    else:
        feedback_parts.append("[-] No COP network to check for bg_plate reference")

    # ================================================================
    # 11. COP has composite/merge operations (5 pts)
    # ================================================================
    cop_has_composite = data.get("cop_has_composite_op", False)

    if cop_has_composite:
        score += 5
        feedback_parts.append("[+5] COP network has composite/merge operations")
    elif has_cop:
        cop_types = data.get("cop_node_types", [])
        feedback_parts.append(
            f"[-] COP network exists but no composite/merge ops found "
            f"(node types: {cop_types})"
        )
    else:
        feedback_parts.append("[-] No COP network to check for composite operations")

    # ================================================================
    # 12. Any rendered file exists in integration/ dir (10 pts)
    # ================================================================
    render_file_count = data.get("render_file_count", 0)
    render_files = data.get("render_files", [])

    if render_file_count > 0:
        score += 10
        feedback_parts.append(
            f"[+10] Rendered files found in integration/ dir "
            f"({render_file_count} files)"
        )
    else:
        feedback_parts.append("[-] No rendered files found in integration/ directory")

    # ================================================================
    # 13. Final composite file exists and > 10KB (10 pts)
    # ================================================================
    composite_exists = data.get("composite_exists", False)
    composite_size = data.get("composite_size_bytes", 0)

    if composite_exists and composite_size > 10240:
        score += 10
        feedback_parts.append(
            f"[+10] Final composite exists ({composite_size} bytes)"
        )
    elif composite_exists and composite_size > 0:
        score += 4
        feedback_parts.append(
            f"[+4] Final composite exists but small ({composite_size} bytes, "
            f"expected > 10KB)"
        )
    else:
        feedback_parts.append(
            "[-] Final composite (final_comp.exr) not found in integration/ dir"
        )

    # ================================================================
    # FINAL RESULT
    # ================================================================
    passed = score >= 60
    feedback = (
        f"Score: {score}/100 (pass threshold: 60). "
        + " | ".join(feedback_parts)
    )

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
    }
