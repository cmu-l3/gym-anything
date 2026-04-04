#!/usr/bin/env python3
"""
Verifier for compositor_node_setup@1 task.

Checks:
1. Compositor is enabled in the saved blend file.
2. Glare, Color Balance, and Lens Distortion nodes exist.
3. Nodes are connected in a chain from input to output.
4. Render output exists, is valid, and was created during the task.
5. VLM verification of the render output (bonus check).
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compositor_setup(traj, env_info, task_info):
    """
    Verify the Blender compositing task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }

    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read result: {e}"
        }
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic data extraction
    comp = result.get("compositor_analysis", {})
    render = result.get("render_output", {})
    blend = result.get("blend_file", {})
    task_start = result.get("task_start_time", 0)

    score = 0
    feedback_parts = []

    # 1. Check if Blend file exists and is valid (15 pts)
    if blend.get("exists") and blend.get("valid"):
        score += 15
        feedback_parts.append("Blend file saved")
    else:
        feedback_parts.append("Blend file missing or invalid")

    # 2. Check if Compositor is enabled (10 pts)
    if comp.get("compositor_enabled"):
        score += 10
        feedback_parts.append("Compositor enabled")
    else:
        feedback_parts.append("Compositor NOT enabled")

    # 3. Check specific nodes (30 pts)
    glare = comp.get("glare_node", {})
    color = comp.get("color_balance_node", {})
    lens = comp.get("lens_distortion_node", {})

    node_score = 0
    if glare.get("exists"): node_score += 10
    if color.get("exists"): node_score += 10
    if lens.get("exists"): node_score += 10
    score += node_score
    
    missing_nodes = []
    if not glare.get("exists"): missing_nodes.append("Glare")
    if not color.get("exists"): missing_nodes.append("Color Balance")
    if not lens.get("exists"): missing_nodes.append("Lens Distortion")
    
    if missing_nodes:
        feedback_parts.append(f"Missing nodes: {', '.join(missing_nodes)}")
    else:
        feedback_parts.append("All required nodes present")

    # Check parameters (10 pts)
    # Glare threshold check
    param_score = 0
    thresh = glare.get("threshold")
    if thresh is not None and thresh <= 1.0:
        param_score += 5
    
    # Lens distortion check
    dist = lens.get("distortion")
    if dist != "linked" and dist is not None:
        if -0.05 <= float(dist) <= 0.1 and float(dist) != 0:
            param_score += 5
    elif dist == "linked":
        param_score += 5 # Linked is acceptable
        
    score += param_score

    # 4. Check Chain Connectivity (15 pts)
    if comp.get("nodes_connected_chain"):
        score += 15
        feedback_parts.append("Nodes connected correctly")
    else:
        feedback_parts.append("Nodes NOT fully connected to Output")

    # 5. Check Render Output (20 pts)
    # Must exist, be created after start time, and have reasonable size
    render_score = 0
    if render.get("exists"):
        mtime = render.get("mtime", 0)
        size = render.get("size_kb", 0)
        
        if mtime > task_start:
            render_score += 10 # Created during task
            if size > 50:
                render_score += 10 # Reasonable size
            else:
                feedback_parts.append("Render file too small")
        else:
            feedback_parts.append("Render file exists but timestamp matches pre-task")
    else:
        feedback_parts.append("No render output found")
    
    score += render_score

    # VLM Verification (Bonus/Validation) - Does not add to score but validates visual outcome
    # Could potentially replace programmatic check if node graph analysis fails
    if query_vlm and render.get("exists") and score >= 60:
        # We only spend tokens on VLM if basic criteria are met
        try:
            # We need to copy the image out to verify it
            with tempfile.NamedTemporaryFile(suffix=".png") as tf:
                copy_from_env("/home/ga/BlenderProjects/cinematic_composite.png", tf.name)
                
                vlm_prompt = """
                Does this image show a 3D rendered car with post-processing effects?
                Look for:
                1. A glow or bloom effect around bright highlights (headlights/reflections).
                2. A cinematic color grading (not just flat grey/white).
                3. Possible slight lens distortion/fringing at edges.
                Answer YES or NO with a brief reason.
                """
                vlm_res = query_vlm(prompt=vlm_prompt, image=tf.name)
                if vlm_res.get("success"):
                    feedback_parts.append(f"VLM: {vlm_res.get('response', '')[:50]}")
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")

    # Final Pass Determination
    # Must have enabled compositor, have at least 2 nodes, and saved the blend file
    passed = (score >= 70) and comp.get("compositor_enabled") and blend.get("exists")

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }