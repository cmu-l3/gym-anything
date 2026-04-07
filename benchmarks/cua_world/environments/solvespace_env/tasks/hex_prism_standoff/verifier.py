#!/usr/bin/env python3
"""
Verifier for hex_prism_standoff task.

VERIFICATION STRATEGY:
1. File validation: Checks timestamps on SLVS and STL files to ensure they were created during the task.
2. SLVS Parsing: Interrogates the text-based SLVS file for line segment entities and extrude operations.
3. STL Geometric Analysis: Computes the 3D volume of the exported STL to ensure it matches a 10mm flat x 15mm tall hex prism.
4. Visual (VLM) Validation: Uses trajectory frames to visually confirm the shape created.
"""

import os
import json
import struct
import tempfile
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def check_stl_volume(filepath):
    """
    Computes the volume of a closed 3D mesh from a binary STL file using the 
    signed volume of tetrahedra formula.
    """
    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) != 4: 
                return -1
                
            num_tris = struct.unpack('<I', count_bytes)[0]
            
            # Verify it's actually a standard binary STL file based on expected size
            if os.path.getsize(filepath) == 84 + num_tris * 50:
                vol = 0.0
                for _ in range(num_tris):
                    data = f.read(50)
                    if len(data) < 50: 
                        break
                    
                    # Read Normal (3), Vertex 1 (3), Vertex 2 (3), Vertex 3 (3), Attr (1)
                    _, p1x, p1y, p1z, p2x, p2y, p2z, p3x, p3y, p3z, _ = struct.unpack('<3f 3f 3f 3f H', data)
                    
                    # Volume of tetrahedron from origin: p1 . (p2 x p3) / 6
                    v = p1x * (p2y * p3z - p2z * p3y) \
                      - p1y * (p2x * p3z - p2z * p3x) \
                      + p1z * (p2x * p3y - p2y * p3x)
                    
                    vol += v / 6.0
                    
                return abs(vol)
    except Exception as e:
        logger.warning(f"Failed to compute STL volume: {e}")
    return -1


def verify_hex_prism(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_vol = metadata.get('target_volume_min', 800)
    max_vol = metadata.get('target_volume_max', 1800)

    score = 0
    feedback = []

    # 1. Gather Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)
    slvs_meta = result.get('slvs', {})
    stl_meta = result.get('stl', {})

    # 2. Gather SLVS and STL files securely
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    has_slvs, has_stl = False, False

    try:
        if slvs_meta.get('exists', False):
            copy_from_env("/home/ga/Documents/SolveSpace/hex_standoff.slvs", temp_slvs.name)
            has_slvs = True
            
        if stl_meta.get('exists', False):
            copy_from_env("/home/ga/Documents/SolveSpace/hex_standoff.stl", temp_stl.name)
            has_stl = True
            
        # Analyze SLVS Contents
        slvs_created = slvs_meta.get('mtime', 0) > task_start
        if has_slvs and slvs_created:
            score += 15
            feedback.append("SLVS file created successfully")
            
            with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            line_segments = content.count('Entity.type=11000')
            has_extrude = ('Group.type=5100' in content) or ('name=extrude' in content.lower())
            
            if line_segments >= 6:
                score += 15
                feedback.append(f"SLVS geometry check: Verified {line_segments} line segments (expected >= 6)")
            else:
                feedback.append(f"SLVS geometry check: Found only {line_segments} line segments. Incomplete sketch.")
                
            if has_extrude:
                score += 15
                feedback.append("SLVS group check: Extrude operation found")
            else:
                feedback.append("SLVS group check: No Extrude operation found")
        else:
            feedback.append("SLVS file missing or was not modified during the task")

        # Analyze STL Volume
        stl_created = stl_meta.get('mtime', 0) > task_start
        if has_stl and stl_created:
            score += 10
            feedback.append("STL file exported successfully")
            
            volume = check_stl_volume(temp_stl.name)
            if min_vol <= volume <= max_vol:
                score += 20
                feedback.append(f"STL Volume Check: Valid shape volume ({volume:.1f} mm³)")
            elif volume > 0:
                score += 5
                feedback.append(f"STL Volume Check: Shape volume ({volume:.1f} mm³) outside target range {min_vol}-{max_vol}")
            else:
                feedback.append("STL Volume Check: Could not compute binary STL volume (possibly exported as ASCII or invalid)")
        else:
            feedback.append("STL file missing or was not exported during the task")

    finally:
        if os.path.exists(temp_slvs.name): os.unlink(temp_slvs.name)
        if os.path.exists(temp_stl.name): os.unlink(temp_stl.name)

    # 3. VLM Verification of Trajectory
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=3)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """Analyze these screenshots from a SolveSpace CAD session.
Did the user successfully draw a 2D hexagon (a 6-sided polygon) and extrude it into a 3D hexagonal prism?

Respond ONLY with a JSON object in this format:
{
    "drew_hexagon": true or false,
    "extruded_3d": true or false,
    "reasoning": "Brief explanation"
}"""
        
        vlm_result = query_vlm(prompt=prompt, images=images)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            
            if parsed.get("drew_hexagon"):
                score += 10
                feedback.append("VLM visual check: 2D hexagon identified")
                
            if parsed.get("extruded_3d"):
                score += 15
                feedback.append("VLM visual check: 3D extrusion identified")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }