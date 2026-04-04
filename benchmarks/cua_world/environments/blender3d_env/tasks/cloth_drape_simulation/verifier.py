#!/usr/bin/env python3
"""
Verifier for cloth_drape_simulation task.

Criteria:
1. Cloth physics set up on a plane (20 pts)
2. Sufficient mesh density for simulation (10 pts)
3. Collision physics on TableTop (15 pts)
4. Collision physics on Ground (5 pts)
5. Cloth has actually deformed/draped (checked via Z-variance) (20 pts)
6. Frame range set appropriately (5 pts)
7. Blend file saved (10 pts)
8. Render output exists and valid (15 pts)

Total: 100 points
Pass Threshold: 70 points
"""

import json
import os
import logging
import tempfile
from typing import Dict, Any

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cloth_drape_simulation(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """
    Verify the cloth drape simulation task.
    """
    # 1. Use copy_from_env to get results
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Framework Error: copy_from_env not available"
        }

    # Helper to load JSON from container
    def load_container_json(path):
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_name = tmp.name
        try:
            copy_from_env(path, tmp_name)
            with open(tmp_name, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"Failed to load {path}: {e}")
            return None
        finally:
            if os.path.exists(tmp_name):
                os.unlink(tmp_name)

    # Load result
    result_data = load_container_json("/tmp/task_result.json")
    if not result_data:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Failed to retrieve task execution results"
        }

    # Extract data
    analysis = result_data.get("scene_analysis", {})
    blend_info = result_data.get("blend_file", {})
    render_info = result_data.get("render_file", {})
    
    score = 0
    feedback_parts = []
    
    # --- CRITERION 1: Cloth object exists (20 pts) ---
    cloth_objects = analysis.get("cloth_objects", [])
    if len(cloth_objects) >= 1:
        score += 20
        feedback_parts.append(f"✅ Cloth physics found ({len(cloth_objects)} object(s))")
    else:
        feedback_parts.append("❌ No Cloth physics modifier found")

    # --- CRITERION 2: Mesh density (10 pts) ---
    vertex_count = analysis.get("cloth_vertex_count", 0)
    if vertex_count >= 100:
        score += 10
        feedback_parts.append(f"✅ Sufficient mesh density ({vertex_count} verts)")
    elif vertex_count >= 25:
        score += 5
        feedback_parts.append(f"⚠️ Low mesh density ({vertex_count} verts)")
    else:
        feedback_parts.append("❌ Insufficient mesh density")

    # --- CRITERION 3: Table Collision (15 pts) ---
    if analysis.get("table_has_collision", False):
        score += 15
        feedback_parts.append("✅ Table collision enabled")
    else:
        feedback_parts.append("❌ Table collision missing")

    # --- CRITERION 4: Ground Collision (5 pts) ---
    if analysis.get("ground_has_collision", False):
        score += 5
        feedback_parts.append("✅ Ground collision enabled")
    else:
        feedback_parts.append("❌ Ground collision missing")

    # --- CRITERION 5: Cloth Deformation/Draping (20 pts) ---
    # Measured by Z-variance. A flat plane has 0 variance.
    z_variance = analysis.get("cloth_z_variance", 0.0)
    # Threshold: 0.005 is conservative for a 1-unit scale scene
    if z_variance > 0.005:
        score += 20
        feedback_parts.append(f"✅ Cloth deformation detected (variance: {z_variance:.4f})")
    elif z_variance > 0.0001:
        score += 10
        feedback_parts.append(f"⚠️ Minimal deformation detected (variance: {z_variance:.4f})")
    else:
        feedback_parts.append("❌ Cloth appears flat (no simulation bake?)")

    # --- CRITERION 6: Frame Range (5 pts) ---
    frame_end = analysis.get("frame_end", 250)
    if 30 <= frame_end <= 150:
        score += 5
        feedback_parts.append(f"✅ Frame range reasonable ({frame_end})")
    else:
        # Not a dealbreaker, just 0 points
        feedback_parts.append(f"⚠️ Frame range large/default ({frame_end})")

    # --- CRITERION 7: Blend File Saved (10 pts) ---
    if blend_info.get("valid", False):
        score += 10
        feedback_parts.append("✅ Blend file saved")
    else:
        feedback_parts.append("❌ Blend file invalid/missing")

    # --- CRITERION 8: Render Output (15 pts) ---
    if (render_info.get("exists", False) and 
        render_info.get("size", 0) > 50000 and 
        render_info.get("created_after_start", False)):
        score += 15
        feedback_parts.append("✅ Render output valid")
    elif render_info.get("exists", False):
        score += 5
        feedback_parts.append("⚠️ Render exists but small/old")
    else:
        feedback_parts.append("❌ No render output")

    # --- VLM Check (Optional/Bonus info) ---
    # We can use VLM to double-check if specific criteria are met visually
    # but primarily rely on programmatic for scoring to be deterministic.
    query_vlm = env_info.get('query_vlm')
    if query_vlm and render_info.get("exists", False):
        # We could query here, but we'll stick to robust programmatic scoring for this task
        pass

    # Final verdict
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }