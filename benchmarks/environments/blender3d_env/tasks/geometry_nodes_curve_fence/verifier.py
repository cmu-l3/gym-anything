#!/usr/bin/env python3
"""
Verifier for Geometry Nodes Curve Fence task.

SCORING CRITERIA:
1. File Creation (10 pts): Valid blend file saved.
2. Modifier Setup (20 pts): Geometry Nodes modifier exists on 'FencePath'.
3. Instancing (20 pts): Correct object instanced, roughly correct count (resampling).
4. Proceduralism (25 pts): Changing curve length updates instance count (Anti-Gaming).
5. Alignment (15 pts): Instances rotate with the curve tangent.
6. VLM Verification (10 pts): Visual confirmation of fence structure.

Pass threshold: 70/100
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_geometry_nodes_fence(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    
    # 1. Load JSON Result
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
            
    # Check if output exists
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
        
    score += 10 # File exists
    
    analysis = result.get("analysis", {})
    if not analysis:
         return {"passed": False, "score": 10, "feedback": "Could not analyze Blender file"}

    # 2. Modifier Check (20 pts)
    if analysis.get("modifier_found"):
        score += 20
        feedback_parts.append("✅ Geometry Nodes modifier found")
    else:
        feedback_parts.append("❌ No Geometry Nodes modifier found")

    # 3. Instancing & Resampling Check (20 pts)
    if analysis.get("instancing_correct"):
        score += 10
        feedback_parts.append("✅ Correct object instanced")
    else:
        feedback_parts.append("❌ Instancing incorrect or missing")
        
    if analysis.get("resampling_correct"):
        score += 10
        feedback_parts.append("✅ Spacing/Resampling looks correct")
    else:
        count = analysis.get("instance_count", 0)
        feedback_parts.append(f"❌ Incorrect instance count ({count}) - check spacing")

    # 4. Procedural Stress Test (25 pts)
    # This verifies they didn't just apply the modifier or place objects manually
    if analysis.get("procedural_check_passed"):
        score += 25
        feedback_parts.append("✅ Setup is fully procedural")
    else:
        feedback_parts.append("❌ Setup is not procedural (fence didn't update when curve changed)")

    # 5. Alignment Check (15 pts)
    if analysis.get("alignment_correct"):
        score += 15
        feedback_parts.append("✅ Posts aligned to curve tangent")
    else:
        feedback_parts.append("❌ Posts not aligned to curve (all have same rotation)")

    # 6. VLM Verification (10 pts)
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    if final_screenshot and env_info.get('query_vlm'):
        prompt = """
        Analyze this Blender 3D viewport screenshot.
        Does it show a fence-like structure following a curved path?
        Look for:
        1. Repeated vertical posts.
        2. Arrangement in a curved line/S-shape.
        
        Return JSON: {"is_fence": bool, "follows_curve": bool}
        """
        try:
            vlm_res = env_info['query_vlm'](prompt, final_screenshot)
            parsed = vlm_res.get('parsed', {})
            if parsed.get('is_fence') and parsed.get('follows_curve'):
                vlm_score = 10
                feedback_parts.append("✅ VLM confirmed visual structure")
            else:
                feedback_parts.append("⚠️ VLM could not clearly identify curved fence")
        except Exception:
            pass # Fail gracefully
            
    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }