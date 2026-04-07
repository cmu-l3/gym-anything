#!/usr/bin/env python3
"""
Verifier for connecting_rod_profile task in SolveSpace.

Multi-Signal Verification Strategy:
1. File Analysis: Checks if .slvs and .stl were created during the task (10 pts)
2. Mesh Geometry (Extents): Bounding box matches exactly [135, 40, 10] (30 pts)
3. Mesh Geometry (Volume): Verifies material solid density constraint (30 pts)
4. Mesh Topology: Euler characteristic == -2 ensures two through-holes exist (15 pts)
5. VLM Visual Verification: Identifies correct tangent constraint application (15 pts)
"""

import os
import sys
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def ensure_dependencies():
    """Dynamically installs python CAD geometry analysis dependencies if missing"""
    try:
        import trimesh
        return True
    except ImportError:
        logger.info("Installing required geometry dependencies (trimesh, networkx, rtree, scipy)...")
        import subprocess
        try:
            subprocess.check_call([
                sys.executable, "-m", "pip", "install", "-q", 
                "trimesh", "networkx", "rtree", "scipy"
            ])
            return True
        except Exception as e:
            logger.error(f"Failed to install dependencies: {e}")
            return False

def verify_connecting_rod_profile(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_extents = metadata.get('expected_extents', [135.0, 40.0, 10.0])
    volume_min = metadata.get('volume_min', 36000.0)
    volume_max = metadata.get('volume_max', 42000.0)
    expected_euler = metadata.get('expected_euler', -2)
    output_stl = metadata.get('output_stl', '/home/ga/Documents/SolveSpace/connecting_rod.stl')

    feedback_parts = []
    score = 0

    # 1. Read exported task metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    slvs_created = result.get('slvs_created_during_task', False)
    stl_created = result.get('stl_created_during_task', False)
    
    if slvs_created and stl_created:
        score += 10
        feedback_parts.append("✅ SLVS and STL models successfully exported")
    elif slvs_created:
        score += 5
        feedback_parts.append("⚠️ SLVS file created, but STL file is missing")
    else:
        feedback_parts.append("❌ Required files were not created/saved")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Stop here if STL doesn't exist
    if not stl_created:
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 2. Analyze the extracted STL file for topological & mathematical correctness
    stl_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    try:
        copy_from_env(output_stl, stl_temp.name)
        
        if ensure_dependencies():
            import trimesh
            try:
                mesh = trimesh.load(stl_temp.name)
                
                if getattr(mesh, 'is_empty', False):
                    feedback_parts.append("❌ Exported STL is completely empty")
                else:
                    # Sort extents to ignore model orientation (e.g. if drawn sideways)
                    extents = sorted(list(mesh.extents), reverse=True)
                    expected_sorted = sorted(expected_extents, reverse=True)
                    
                    # Extents Check (30 points)
                    extents_diff = [abs(e - x) for e, x in zip(expected_sorted, extents)]
                    if all(diff < 2.0 for diff in extents_diff):
                        score += 30
                        feedback_parts.append(f"✅ Bounding Box correct: {[round(x,1) for x in extents]}")
                    elif all(diff < 5.0 for diff in extents_diff):
                        score += 15
                        feedback_parts.append(f"⚠️ Bounding Box slightly off: {[round(x,1) for x in extents]}")
                    else:
                        feedback_parts.append(f"❌ Bounding Box incorrect: {[round(x,1) for x in extents]} vs Expected {expected_sorted}")

                    # Volume Check (30 points)
                    volume = mesh.volume
                    if volume_min <= volume <= volume_max:
                        score += 30
                        feedback_parts.append(f"✅ Solid Volume correct: {round(volume)} mm³")
                    else:
                        feedback_parts.append(f"❌ Solid Volume incorrect: {round(volume)} mm³ (Expected {volume_min}-{volume_max})")

                    # Euler Characteristic Check (15 points) - Mathematically proves the holes cut completely through
                    euler = mesh.euler_number
                    if euler == expected_euler:
                        score += 15
                        feedback_parts.append(f"✅ Mesh Topology correct: Exactly 2 through-holes (Euler {euler})")
                    else:
                        holes = 1 - (euler / 2)
                        feedback_parts.append(f"❌ Mesh Topology incorrect: Found {int(holes)} holes (Euler {euler})")

            except Exception as e:
                logger.error(f"Error processing STL: {e}")
                feedback_parts.append(f"❌ Error processing STL: {str(e)}")
        else:
            feedback_parts.append("⚠️ Could not load trimesh dependency for exact geometric verification")
            
    finally:
        if os.path.exists(stl_temp.name):
            os.unlink(stl_temp.name)

    # 3. VLM Verification (15 points) using trajectory frames
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    images = frames + [final] if final else frames
    
    if query_vlm and images:
        vlm_prompt = """You are evaluating a 2D CAD drafting task in SolveSpace.
The goal was to draw a connecting rod profile using tangent lines and arcs, with two inner holes, fully constrained.

Please verify:
1. Did the agent utilize Tangent constraints to connect straight lines smoothly into the outer arcs?
2. Is the sketch shown as fully constrained? (Status text usually says 'OK, 0 DOF' in the bottom left).
3. Was an extrusion performed to make it a 3D solid?

Return a JSON with boolean flags for each, and a short explanation:
{
    "tangent_used": true/false,
    "fully_constrained": true/false,
    "extrusion_performed": true/false,
    "explanation": "..."
}"""
        vlm_result = query_vlm(prompt=vlm_prompt, images=images)
        parsed = vlm_result.get("parsed", {})
        
        vlm_pts = 0
        if parsed.get("tangent_used", False): vlm_pts += 5
        if parsed.get("fully_constrained", False): vlm_pts += 5
        if parsed.get("extrusion_performed", False): vlm_pts += 5
        
        score += vlm_pts
        feedback_parts.append(f"VLM Visual Check: {vlm_pts}/15 pts ({parsed.get('explanation', '')})")
    else:
        feedback_parts.append("⚠️ VLM visual verification skipped (missing image or function)")

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }