#!/usr/bin/env python3
"""
Verifier for CSG Hollow Pipe Cross Fitting task.

Checks:
1. File existence and timestamps (Anti-gaming).
2. Parametric dimensions in the SLVS file.
3. Volumetric accuracy of the exported STL file (Proves correct CSG boolean sequence).
4. VLM Trajectory analysis (Proves correct workflow).
"""

import json
import os
import struct
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# =============================================================================
# VLM PROMPT
# =============================================================================

VERIFICATION_PROMPT = """You are evaluating an AI agent's performance on a CAD task in SolveSpace.
The agent was asked to create a "CSG Hollow Pipe Cross Fitting".
This consists of two orthogonal pipes (cylinders) intersecting at the origin, with hollow cores so fluid can flow through them.

Examine the provided trajectory frames and final screenshot.
1. Did the agent use SolveSpace to draw and extrude cylinders?
2. Does the geometry visually resemble a 4-way cross or '+' shape?
3. Is there visual evidence that the agent hollowed out the pipes (e.g., using "Difference" operations, or drawing inner circles)?
4. Does the final result look like a hollow cross fitting?

Respond strictly in JSON format:
{
    "modeled_cross": true/false,
    "appears_hollow": true/false,
    "used_solvespace": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is visible in the frames."
}"""

# =============================================================================
# STL VOLUME CALCULATOR
# =============================================================================

def calculate_stl_volume(file_path):
    """Calculate the exact volume of a binary or ascii STL file."""
    volume = 0.0
    try:
        with open(file_path, 'rb') as f:
            header = f.read(80)
            count_bytes = f.read(4)
            if len(count_bytes) < 4: return 0.0
            num_faces = struct.unpack('<I', count_bytes)[0]
            
            # Check if it's a valid binary STL by file size
            # 84 bytes header + 50 bytes per face
            expected_size = 84 + 50 * num_faces
            file_size = os.path.getsize(file_path)
            
            if file_size == expected_size and num_faces > 0:
                # Binary STL parsing
                for _ in range(num_faces):
                    data = f.read(50)
                    if len(data) < 50: break
                    v = struct.unpack('<12fH', data)
                    p1, p2, p3 = v[3:6], v[6:9], v[9:12]
                    
                    # Signed volume of tetrahedron: v1 . (v2 x v3) / 6
                    cross_x = p2[1]*p3[2] - p2[2]*p3[1]
                    cross_y = p2[2]*p3[0] - p2[0]*p3[2]
                    cross_z = p2[0]*p3[1] - p2[1]*p3[0]
                    vol = (p1[0]*cross_x + p1[1]*cross_y + p1[2]*cross_z) / 6.0
                    volume += vol
                return abs(volume)
            else:
                # Fallback to Ascii STL parsing
                return calculate_ascii_stl_volume(file_path)
    except Exception as e:
        logger.error(f"Error parsing STL: {e}")
        return 0.0

def calculate_ascii_stl_volume(file_path):
    """Fallback parser for ASCII STL files."""
    volume = 0.0
    try:
        with open(file_path, 'r', encoding='utf-8', errors='ignore') as f:
            points = []
            for line in f:
                parts = line.strip().split()
                if not parts: continue
                if parts[0].lower() == 'vertex' and len(parts) >= 4:
                    points.append((float(parts[1]), float(parts[2]), float(parts[3])))
                    
                    if len(points) == 3:
                        p1, p2, p3 = points
                        cross_x = p2[1]*p3[2] - p2[2]*p3[1]
                        cross_y = p2[2]*p3[0] - p2[0]*p3[2]
                        cross_z = p2[0]*p3[1] - p2[1]*p3[0]
                        vol = (p1[0]*cross_x + p1[1]*cross_y + p1[2]*cross_z) / 6.0
                        volume += vol
                        points = []
    except Exception as e:
        logger.error(f"Error parsing ASCII STL: {e}")
    return abs(volume)

# =============================================================================
# MAIN VERIFIER
# =============================================================================

def verify_pipe_cross(traj, env_info, task_info):
    """Verifies the CSG Hollow Pipe Cross Fitting task."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_volume = metadata.get('target_volume_mm3', 42110.0)
    vol_tolerance = metadata.get('volume_tolerance', 2000.0)
    
    score = 0
    feedback_parts = []
    
    # 1. Fetch task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read task result: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    slvs_exists = result.get('slvs_exists', False)
    stl_exists = result.get('stl_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    # 2. Basic criteria: files created
    if not created_during_task and slvs_exists:
        return {"passed": False, "score": 0, "feedback": "Anti-gaming failure: File existed before task started."}

    if slvs_exists and stl_exists:
        score += 20
        feedback_parts.append("✅ Models saved successfully")
    elif slvs_exists:
        score += 10
        feedback_parts.append("⚠️ SLVS saved, but missing STL export")
    else:
        return {"passed": False, "score": 0, "feedback": "❌ Target SLVS model was not saved."}

    # 3. Process SLVS and STL files from environment
    temp_slvs = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    temp_stl = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    
    stl_volume = 0.0
    slvs_content = ""
    
    try:
        if slvs_exists:
            copy_from_env("/home/ga/Documents/SolveSpace/pipe_cross_fitting.slvs", temp_slvs.name)
            with open(temp_slvs.name, 'r', encoding='utf-8', errors='ignore') as f:
                slvs_content = f.read()
                
        if stl_exists:
            copy_from_env("/home/ga/Documents/SolveSpace/pipe_cross_fitting.stl", temp_stl.name)
            stl_volume = calculate_stl_volume(temp_stl.name)
    except Exception as e:
        logger.error(f"Error fetching files: {e}")
    finally:
        if os.path.exists(temp_slvs.name): os.unlink(temp_slvs.name)
        if os.path.exists(temp_stl.name): os.unlink(temp_stl.name)

    # 4. Dimension verification via SLVS text parsing
    # We look for dimension values of 30, 24, 15, 12, 100, 50.
    has_outer_dim = "30." in slvs_content or "15." in slvs_content
    has_inner_dim = "24." in slvs_content or "12." in slvs_content
    has_length_dim = "100." in slvs_content or "50." in slvs_content
    
    if has_outer_dim and has_inner_dim and has_length_dim:
        score += 20
        feedback_parts.append("✅ Parametric dimensions verified in SLVS")
    else:
        feedback_parts.append("⚠️ Missing exact dimensional constraints (30/24/100) in file")

    # 5. Volumetric Verification (The core CSG logic test)
    # Target volume is ~42,110 mm³.
    vol_diff = abs(stl_volume - target_volume)
    logger.info(f"Calculated STL Volume: {stl_volume} mm3 (Target: {target_volume})")
    
    volume_passed = False
    if stl_exists and stl_volume > 1000.0:
        if vol_diff <= vol_tolerance:
            score += 40
            volume_passed = True
            feedback_parts.append(f"✅ CSG Volume correct ({stl_volume:.1f} mm³)")
        elif vol_diff <= vol_tolerance * 3:
            score += 20
            feedback_parts.append(f"⚠️ CSG Volume slightly off ({stl_volume:.1f} mm³, expected {target_volume})")
        else:
            feedback_parts.append(f"❌ CSG Volume totally incorrect ({stl_volume:.1f} mm³). Check boolean logic.")
    elif stl_exists:
        feedback_parts.append("❌ Exported STL is empty or invalid.")

    # 6. VLM Trajectory Verification
    vlm_passed = False
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        if images:
            vlm_result = query_vlm(prompt=VERIFICATION_PROMPT, images=images)
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("modeled_cross") and parsed.get("used_solvespace"):
                    score += 10
                    if parsed.get("appears_hollow"):
                        score += 10
                        vlm_passed = True
                        feedback_parts.append("✅ VLM visual check confirmed hollow cross shape")
                    else:
                        feedback_parts.append("⚠️ VLM visual check: Cross shape modeled, but hollowness unclear")
                else:
                    feedback_parts.append("❌ VLM visual check failed to recognize the cross fitting")

    # Pass logic: Must have a decent score and either pass volume or visual + file logic
    is_passing = score >= 70 and slvs_exists and (volume_passed or vlm_passed)
    
    return {
        "passed": is_passing,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }