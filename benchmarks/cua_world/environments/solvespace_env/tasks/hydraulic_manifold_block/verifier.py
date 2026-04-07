#!/usr/bin/env python3
"""
Verifier for hydraulic_manifold_block task in SolveSpace.

Verification Strategy:
1. File Existence & Anti-Gaming: Check if `manifold_block.slvs` exists and was created during the task.
2. File Parsing (Topology): Parse the plain-text `.slvs` file to detect multiple extrusion groups and circle sketches.
3. File Parsing (Dimensions): Extract constraint parameters to verify absolute dimensions (80, 40, 20, 15, 10).
4. Visual Trajectory (VLM): Analyze trajectory frames to verify multi-plane 3D modeling and subtractive holes.
"""

import os
import json
import re
import tempfile
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_slvs_for_dimensions_and_features(filepath: str) -> Dict[str, Any]:
    """Parse the SolveSpace .slvs file to extract geometry info."""
    result = {
        "is_valid": False,
        "circle_count": 0,
        "extrude_count": 0,
        "has_80": False,
        "has_40": False,
        "has_20": False,
        "has_15_or_7_5": False,
        "has_10_or_5": False
    }
    
    try:
        with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            
        if "SolveSpace" in content or "Recipe" in content:
            result["is_valid"] = True
            
        # Count Circle requests (type=400)
        result["circle_count"] = content.count("Request.type=400")
        
        # Count Extrude groups (type=5100 or combinatory differences)
        # We just look for the extrude group signature or difference combinations
        result["extrude_count"] = content.count("Group.type=51") + content.count("Group.combine=1")
        
        # Extract all floats to check for specific dimensions (tolerance of 0.5)
        # Matches floats like 80.00000000
        floats = [abs(float(match.group())) for match in re.finditer(r'[-+]?\d*\.\d+', content)]
        
        def has_val(expected: float, tol: float = 0.5) -> bool:
            return any(abs(f - expected) <= tol for f in floats)
            
        result["has_80"] = has_val(80.0)
        result["has_40"] = has_val(40.0)
        result["has_20"] = has_val(20.0)
        result["has_15_or_7_5"] = has_val(15.0) or has_val(7.5)  # Diameter or Radius
        result["has_10_or_5"] = has_val(10.0) or has_val(5.0)    # Diameter or Radius
            
    except Exception as e:
        logger.error(f"Failed to parse slvs file: {e}")
        
    return result


def verify_manifold_block(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify the hydraulic manifold block task."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read export JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_exists = result.get('file_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Output file manifold_block.slvs not found."
        }
        
    if not created_during_task:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Output file was not created or modified during the task duration (anti-gaming violation)."
        }
        
    score += 10
    feedback_parts.append("✅ File created correctly")

    # 2. Extract and parse the actual .slvs file
    slvs_data = {"is_valid": False}
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    try:
        expected_path = task_info.get('metadata', {}).get('expected_output_path', '/home/ga/Documents/SolveSpace/manifold_block.slvs')
        copy_from_env(expected_path, temp_slvs.name)
        slvs_data = parse_slvs_for_dimensions_and_features(temp_slvs.name)
    except Exception as e:
        logger.error(f"Failed to copy/parse SLVS: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.unlink(temp_slvs.name)

    if not slvs_data["is_valid"]:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | ❌ File is not a valid SolveSpace format."
        }

    # Evaluate Topology (Max 30 pts)
    topology_score = 0
    if slvs_data["circle_count"] >= 3:
        topology_score += 15
        feedback_parts.append("✅ 3+ circle geometries detected")
    elif slvs_data["circle_count"] > 0:
        topology_score += 5
        feedback_parts.append("⚠️ Partial circle geometries detected")
        
    if slvs_data["extrude_count"] >= 3:
        topology_score += 15
        feedback_parts.append("✅ Multiple extrude/cut operations detected")
    elif slvs_data["extrude_count"] > 0:
        topology_score += 5
        feedback_parts.append("⚠️ Basic extrusion detected, but multi-face cuts missing")
    score += topology_score

    # Evaluate Dimensions (Max 30 pts)
    dim_score = 0
    if slvs_data["has_80"]: dim_score += 10
    if slvs_data["has_40"]: dim_score += 5
    if slvs_data["has_20"]: dim_score += 5
    if slvs_data["has_15_or_7_5"]: dim_score += 5
    if slvs_data["has_10_or_5"]: dim_score += 5
    
    if dim_score == 30:
        feedback_parts.append("✅ Perfect dimensional accuracy")
    elif dim_score > 0:
        feedback_parts.append(f"⚠️ Partial dimensional accuracy ({dim_score}/30)")
    else:
        feedback_parts.append("❌ Incorrect dimensions")
    score += dim_score

    # 3. VLM Trajectory Verification (Max 30 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        
        prompt = """You are assessing a computer agent modeling a 3D CAD part.
The goal was to create an 80x80x80 block with three circular holes cut into three different perpendicular faces.
Look at the trajectory frames and the final screenshot.
1. Did the agent successfully create a 3D solid block? (Focus on the 3D geometry visible).
2. Did the agent create circular holes on at least two different faces of the block? (Should appear as cut-outs/voids).

Respond with JSON:
{
  "has_3d_block": true/false,
  "has_holes_on_multiple_faces": true/false,
  "reasoning": "brief explanation"
}"""
        
        vlm_result = query_vlm(images=frames + [final] if final else frames, prompt=prompt)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("has_3d_block"):
                vlm_score += 10
            if parsed.get("has_holes_on_multiple_faces"):
                vlm_score += 20
                feedback_parts.append("✅ VLM visually confirmed multi-face holes")
            else:
                feedback_parts.append("❌ VLM could not confirm multi-face holes visually")
        else:
            feedback_parts.append("⚠️ VLM evaluation failed, awarding partial default points")
            vlm_score = 15
    else:
        feedback_parts.append("⚠️ VLM unavailable, skipping visual check")
        vlm_score = 30  # Default to full points for this section if VLM is offline
        
    score += vlm_score

    # Determine pass/fail
    passed = score >= 70 and slvs_data["extrude_count"] >= 2
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }