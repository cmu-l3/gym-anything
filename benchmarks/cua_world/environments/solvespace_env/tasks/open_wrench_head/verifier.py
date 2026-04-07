#!/usr/bin/env python3
"""
Verifier for open_wrench_head task in SolveSpace.

Verification Strategy:
1. File Existence & Timestamps (Anti-gaming): Both .slvs and .stl must exist and be created during the task.
2. SLVS Content Parsing: Check for key parametric values (15 deg, 16mm/32mm, 7.5mm/15mm, 6mm extrude).
3. STL Validation: Parse binary STL to confirm positive volume and Z-thickness of ~6.0mm.
4. VLM Trajectory Verification: Check trajectory frames to ensure the 3D angled wrench head was actually drawn.
"""

import os
import json
import tempfile
import struct
import logging
from typing import Dict, Any

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt
VLM_PROMPT = """You are verifying a CAD task in SolveSpace.
The goal was to create a 15mm open-ended wrench head.
Key features required:
1. A rounded outer profile and an inner U-shaped jaw.
2. The jaw must be offset by an angle (15 degrees) from the horizontal axis.
3. The 2D sketch must be extruded into a 3D solid block.

Review these trajectory frames and the final screenshot.
Did the user successfully draw this angled wrench head and extrude it into 3D?
Note: Look for the geometric progression—sketching lines/arcs, adding constraints, and finally a 3D extruded view.

Return a JSON with:
{
    "is_3d_solid": true/false,
    "has_angled_jaw": true/false,
    "has_wrench_shape": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""


def get_stl_thickness(filepath: str) -> float:
    """Parse binary STL to calculate the Z bounding box thickness."""
    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            if header.startswith(b'solid'):
                # ASCII STL fallback (very simplified, usually agents export binary)
                with open(filepath, 'r', encoding='utf-8', errors='ignore') as text_f:
                    z_coords = []
                    for line in text_f:
                        if line.strip().startswith('vertex'):
                            parts = line.split()
                            if len(parts) >= 4:
                                z_coords.append(float(parts[3]))
                    if z_coords:
                        return max(z_coords) - min(z_coords)
                return 0.0

            # Binary STL
            count_bytes = f.read(4)
            if len(count_bytes) != 4:
                return 0.0
            num_triangles = struct.unpack('<I', count_bytes)[0]
            
            z_coords = []
            # Read up to 100k triangles to prevent memory/time bombs
            for _ in range(min(num_triangles, 100000)):
                data = f.read(50)
                if len(data) != 50:
                    break
                # format: 3 floats normal, 9 floats vertices, 1 short attribute
                unpacked = struct.unpack('<12fH', data)
                # Z coordinates are at indices 5, 8, 11
                z_coords.extend([unpacked[5], unpacked[8], unpacked[11]])
                
            if z_coords:
                return max(z_coords) - min(z_coords)
    except Exception as e:
        logger.error(f"Error parsing STL: {e}")
    return 0.0


def verify_open_wrench_head(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env or not query_vlm:
        return {"passed": False, "score": 0, "feedback": "Required framework functions missing."}

    feedback = []
    score = 0

    # 1. Retrieve the task result JSON
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_result:
        pass
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.remove(temp_result.name)

    # File Checks
    slvs_created = result.get('slvs_exists', False) and result.get('slvs_created_during_task', False)
    stl_created = result.get('stl_exists', False) and result.get('stl_created_during_task', False)

    if slvs_created and stl_created:
        score += 20
        feedback.append("✅ Files (.slvs and .stl) properly created.")
    else:
        feedback.append("❌ Required files not created or missing anti-gaming timestamp validation.")
        return {"passed": False, "score": score, "feedback": "\n".join(feedback)}

    # 2. SLVS File Parsing
    with tempfile.NamedTemporaryFile(delete=False, suffix='.slvs') as temp_slvs:
        pass
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/wrench_head.slvs", temp_slvs.name)
        with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            slvs_content = f.read()

        # Check for constraint parameters
        has_angle = "Param.val=15.0" in slvs_content or "Param.val=165.0" in slvs_content
        has_extrude = "Group.type=5100" in slvs_content and "Param.val=6.0" in slvs_content
        
        # Radii or Diameters
        has_outer = "Param.val=16.0" in slvs_content or "Param.val=32.0" in slvs_content
        has_inner = "Param.val=7.5" in slvs_content or "Param.val=15.0" in slvs_content

        if has_angle: score += 10
        if has_outer and has_inner: score += 10
        if has_extrude: score += 10

        feedback.append(f"SLVS constraints found: Angle={has_angle}, Radii={has_outer and has_inner}, Extrude={has_extrude}.")
    except Exception as e:
        feedback.append(f"⚠️ Error parsing SLVS: {e}")
    finally:
        if os.path.exists(temp_slvs.name):
            os.remove(temp_slvs.name)

    # 3. STL File Parsing
    with tempfile.NamedTemporaryFile(delete=False, suffix='.stl') as temp_stl:
        pass
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/wrench_head.stl", temp_stl.name)
        thickness = get_stl_thickness(temp_stl.name)
        
        if 5.8 <= thickness <= 6.2:
            score += 20
            feedback.append(f"✅ STL thickness verified: {thickness:.2f}mm")
        elif thickness > 0:
            score += 10
            feedback.append(f"⚠️ STL exported but incorrect thickness: {thickness:.2f}mm")
        else:
            feedback.append("❌ STL file is empty or invalid.")
    except Exception as e:
        feedback.append(f"⚠️ Error parsing STL: {e}")
    finally:
        if os.path.exists(temp_stl.name):
            os.remove(temp_stl.name)

    # 4. VLM Trajectory Verification
    frames = sample_trajectory_frames(traj, n=4)
    final_img = get_final_screenshot(traj)
    images = frames + [final_img] if final_img else frames

    if images:
        vlm_res = query_vlm(images=images, prompt=VLM_PROMPT)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            vlm_score = 0
            if parsed.get("is_3d_solid"): vlm_score += 10
            if parsed.get("has_angled_jaw"): vlm_score += 10
            if parsed.get("has_wrench_shape"): vlm_score += 10
            
            score += vlm_score
            feedback.append(f"VLM Visual check: {vlm_score}/30 pts. Reasoning: {parsed.get('reasoning')}")
        else:
            feedback.append("⚠️ VLM verification failed to run.")
            score += 15 # Fallback partial credit if VLM errors out but files exist
    else:
        feedback.append("⚠️ No images available for VLM verification.")

    key_criteria_met = slvs_created and stl_created and has_extrude
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": "\n".join(feedback)
    }