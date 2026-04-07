#!/usr/bin/env python3
"""
Verifier for compositing_product_pipeline task.

SCORING CRITERIA (100 pts total):
1. Render Settings (12 pts): Cycles engine, 64 samples, 1920x1080
2. Render Passes (8 pts): AO and Mist enabled
3. Mist Configuration (5 pts): Start ~5m, Depth ~25m
4. Glare Node (12 pts): Exists, Fog Glow type, threshold/size correct
5. Color Balance Node (12 pts): Exists, Gain warm, Lift cool
6. Map Value Node (8 pts): Exists, Size ~0.35
7. Mix Node (8 pts): Exists, fog color blue-grey
8. File Output Node (5 pts): Exists with correct path
9. Node Connectivity (12 pts): Correct pipeline topology
10. Render Output (9 pts): PNG exists, valid, > 50KB
11. Project Saved (9 pts): .blend exists, valid, modified after start

Pass threshold: 70 pts
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_compositing_product_pipeline(
    traj: Dict[str, Any],
    env_info: Dict[str, Any],
    task_info: Dict[str, Any]
) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # Load result JSON from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    analysis = result.get("scene_analysis", {})

    # ================================================================
    # GATE: No output files at all -> score 0
    # ================================================================
    if not result.get("blend_exists") and not result.get("render_exists"):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files found (no .blend and no rendered .png)"
        }

    # ================================================================
    # GATE: No compositor nodes beyond defaults -> cap at 20
    # ================================================================
    comp_nodes = analysis.get("compositor_nodes", [])
    custom_node_types = [n["type"] for n in comp_nodes
                         if n.get("type") not in ("R_LAYERS", "COMPOSITE")]
    max_score_cap = 100  # may be reduced by gates below
    if len(custom_node_types) == 0:
        max_score_cap = 20
        feedback.append("No custom compositor nodes found beyond defaults")

    # ================================================================
    # 1. RENDER SETTINGS (12 pts)
    # ================================================================
    # Engine = Cycles (4 pts)
    if analysis.get("render_engine") == "CYCLES":
        score += 4
    else:
        feedback.append(f"Render engine: {analysis.get('render_engine', 'unknown')} (expected CYCLES)")

    # Samples = 64 +/- 5 (4 pts)
    samples = analysis.get("cycles_samples", -1)
    if 59 <= samples <= 69:
        score += 4
    elif 32 <= samples <= 128:
        score += 2
        feedback.append(f"Samples: {samples} (expected ~64)")
    else:
        feedback.append(f"Samples: {samples} (expected ~64)")

    # Resolution = 1920x1080 (4 pts)
    res_x = analysis.get("resolution_x", 0)
    res_y = analysis.get("resolution_y", 0)
    if res_x == 1920 and res_y == 1080:
        score += 4
    elif res_x >= 1280 and res_y >= 720:
        score += 2
        feedback.append(f"Resolution: {res_x}x{res_y} (expected 1920x1080)")
    else:
        feedback.append(f"Resolution: {res_x}x{res_y} (expected 1920x1080)")

    # ================================================================
    # 2. RENDER PASSES (8 pts)
    # ================================================================
    if analysis.get("pass_ao"):
        score += 4
    else:
        feedback.append("AO pass not enabled")

    if analysis.get("pass_mist"):
        score += 4
    else:
        feedback.append("Mist pass not enabled")

    # ================================================================
    # 3. MIST CONFIGURATION (5 pts)
    # ================================================================
    mist_start = analysis.get("mist_start", -1)
    mist_depth = analysis.get("mist_depth", -1)

    if 4.0 <= mist_start <= 6.0:
        score += 2.5
    elif mist_start > 0:
        score += 1
        feedback.append(f"Mist Start: {mist_start} (expected ~5.0)")
    else:
        feedback.append(f"Mist Start: {mist_start} (expected ~5.0)")

    if 20.0 <= mist_depth <= 30.0:
        score += 2.5
    elif mist_depth > 0:
        score += 1
        feedback.append(f"Mist Depth: {mist_depth} (expected ~25.0)")
    else:
        feedback.append(f"Mist Depth: {mist_depth} (expected ~25.0)")

    # ================================================================
    # 4. GLARE NODE (12 pts)
    # ================================================================
    glare_nodes = [n for n in comp_nodes if n.get("type") == "GLARE"]
    if glare_nodes:
        gn = glare_nodes[0]
        # Exists + correct type (5 pts)
        if gn.get("glare_type") == "FOG_GLOW":
            score += 5
        else:
            score += 2
            feedback.append(f"Glare type: {gn.get('glare_type')} (expected FOG_GLOW)")

        # Threshold in range (3 pts)
        threshold = gn.get("threshold", -1)
        if 0.6 <= threshold <= 1.0:
            score += 3
        elif threshold > 0:
            score += 1
            feedback.append(f"Glare threshold: {threshold} (expected ~0.8)")

        # Size in range (2 pts)
        size = gn.get("size", -1)
        if 5 <= size <= 9:
            score += 2
        elif size > 0:
            score += 1
            feedback.append(f"Glare size: {size} (expected ~7)")

        # Quality (2 pts)
        if gn.get("quality") == "HIGH":
            score += 2
        else:
            score += 1  # partial credit for any quality
    else:
        feedback.append("No Glare node found in compositor")

    # ================================================================
    # 5. COLOR BALANCE NODE (12 pts)
    # ================================================================
    cb_nodes = [n for n in comp_nodes if n.get("type") == "COLORBALANCE"]
    if cb_nodes:
        cb = cb_nodes[0]
        score += 3  # Exists

        # Gain should be warm: R > B (4.5 pts)
        gain = cb.get("gain", [1, 1, 1])
        if len(gain) >= 3 and gain[0] > gain[2]:
            score += 4.5
        else:
            score += 1
            feedback.append(f"Color Balance Gain: {gain} (expected R > B for warm)")

        # Lift should be cool: B > R (4.5 pts)
        lift = cb.get("lift", [1, 1, 1])
        if len(lift) >= 3 and lift[2] > lift[0]:
            score += 4.5
        else:
            score += 1
            feedback.append(f"Color Balance Lift: {lift} (expected B > R for cool)")
    else:
        feedback.append("No Color Balance node found in compositor")

    # ================================================================
    # 6. MAP VALUE NODE (8 pts)
    # ================================================================
    mv_nodes = [n for n in comp_nodes if n.get("type") == "MAP_VALUE"]
    if mv_nodes:
        mv = mv_nodes[0]
        score += 3  # Exists

        # Size ~0.35 (5 pts)
        size_val = mv.get("size_val", [1.0])
        if isinstance(size_val, list) and len(size_val) > 0:
            sv = size_val[0]
        else:
            sv = size_val
        if 0.2 <= sv <= 0.5:
            score += 5
        elif 0.1 <= sv <= 1.0:
            score += 2
            feedback.append(f"Map Value Size: {sv} (expected ~0.35)")
        else:
            feedback.append(f"Map Value Size: {sv} (expected ~0.35)")
    else:
        feedback.append("No Map Value node found in compositor")

    # ================================================================
    # 7. MIX NODE (8 pts)
    # ================================================================
    mix_nodes = [n for n in comp_nodes if n.get("type") == "MIX_RGB"]
    if mix_nodes:
        mn = mix_nodes[0]
        score += 3  # Exists

        # Color2 should be bluish: B > R and B > G (5 pts)
        color2 = mn.get("color2_default", [0.5, 0.5, 0.5])
        if len(color2) >= 3 and color2[2] > color2[0] and color2[2] > color2[1]:
            score += 5
        elif len(color2) >= 3 and color2[2] >= color2[0]:
            score += 2
            feedback.append(f"Mix Color2: {color2} (expected blue-grey)")
        else:
            feedback.append(f"Mix Color2: {color2} (expected blue-grey)")
    else:
        feedback.append("No Mix Color node found in compositor")

    # ================================================================
    # 8. FILE OUTPUT NODE (5 pts)
    # ================================================================
    fo_nodes = [n for n in comp_nodes if n.get("type") == "OUTPUT_FILE"]
    if fo_nodes:
        fo = fo_nodes[0]
        base_path = fo.get("base_path", "")
        if "bmw_composited" in base_path or "BlenderProjects" in base_path:
            score += 5
        else:
            score += 2
            feedback.append(f"File Output path: {base_path}")
    else:
        feedback.append("No File Output node found in compositor")

    # ================================================================
    # 9. NODE CONNECTIVITY (12 pts)
    # ================================================================
    links = analysis.get("compositor_links", [])

    def has_link(from_type, to_type, from_socket=None, to_socket=None):
        """Check if a link exists between node types."""
        for link in links:
            fn = link.get("from_node", "")
            tn = link.get("to_node", "")
            # Match by finding nodes of the right type
            fn_node = next((n for n in comp_nodes if n["name"] == fn), {})
            tn_node = next((n for n in comp_nodes if n["name"] == tn), {})
            if fn_node.get("type") == from_type and tn_node.get("type") == to_type:
                if from_socket and link.get("from_socket") != from_socket:
                    continue
                if to_socket and link.get("to_socket") != to_socket:
                    continue
                return True
        return False

    # RL -> Glare -> Color Balance (4 pts)
    if has_link("R_LAYERS", "GLARE") and has_link("GLARE", "COLORBALANCE"):
        score += 4
    elif has_link("R_LAYERS", "GLARE") or has_link("GLARE", "COLORBALANCE"):
        score += 2

    # Mist -> Map Value -> Mix Fac (4 pts)
    mist_to_mv = has_link("R_LAYERS", "MAP_VALUE", from_socket="Mist")
    mv_to_mix = has_link("MAP_VALUE", "MIX_RGB")
    if mist_to_mv and mv_to_mix:
        score += 4
    elif mist_to_mv or mv_to_mix:
        score += 2

    # Mix -> Composite (4 pts)
    if has_link("MIX_RGB", "COMPOSITE"):
        score += 4
    elif has_link("COLORBALANCE", "COMPOSITE") or has_link("GLARE", "COMPOSITE"):
        score += 2  # partial: at least some processed output goes to composite

    # ================================================================
    # 10. RENDER OUTPUT (9 pts)
    # ================================================================
    render_exists = result.get("render_exists", False)
    render_size = result.get("render_size_bytes", 0)
    render_mtime = result.get("render_mtime", 0)
    task_start = result.get("task_start", 0)

    if render_exists and render_size > 50000:
        if render_mtime > task_start:
            score += 9
        else:
            score += 5
            feedback.append("Render exists but may be stale (mtime before task start)")
    elif render_exists:
        score += 3
        feedback.append(f"Render exists but small ({render_size} bytes)")
    else:
        feedback.append("Render output not found")

    # ================================================================
    # 11. PROJECT SAVED (9 pts)
    # ================================================================
    blend_exists = result.get("blend_exists", False)
    blend_size = result.get("blend_size_bytes", 0)
    blend_mtime = result.get("blend_mtime", 0)

    if blend_exists and blend_size > 100000:
        if blend_mtime > task_start:
            score += 9
        else:
            score += 5
            feedback.append("Blend exists but may be stale")
    elif blend_exists:
        score += 3
        feedback.append(f"Blend exists but small ({blend_size} bytes)")
    else:
        feedback.append("Project file not saved")

    # ================================================================
    # APPLY SCORE CAP FROM GATES
    # ================================================================
    score = min(score, max_score_cap)

    passed = score >= 70

    return {
        "passed": passed,
        "score": int(score),
        "feedback": f"Score: {int(score)}/100. " + "; ".join(feedback) if feedback else f"Score: {int(score)}/100. All checks passed.",
        "details": {
            "score_breakdown": {
                "render_settings": "checked",
                "passes": "checked",
                "mist": "checked",
                "glare": bool(glare_nodes),
                "color_balance": bool(cb_nodes),
                "map_value": bool(mv_nodes),
                "mix": bool(mix_nodes),
                "file_output": bool(fo_nodes),
                "connectivity": len(links),
                "render_saved": render_exists,
                "blend_saved": blend_exists
            }
        }
    }
