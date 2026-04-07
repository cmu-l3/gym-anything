#!/usr/bin/env python3
"""
Verifier for lathe_revolve task in SolveSpace.

Verification Strategy:
1. STL file analysis:
   - Validates the mesh exists and was created during the task.
   - Calculates bounding box dimensions (verifies X~30, Y~25, Z~30 and X/Z symmetry).
   - Calculates the volume using signed tetrahedrons (verifies ~7555 mm3).
2. SLVS project analysis:
   - Verifies file existence and creation time.
   - Parses the text to ensure 'Lathe' group (type 5020) was used.
   - Parses the text to ensure line entities (type 11000) were drawn.
3. VLM Trajectory Verification:
   - Samples trajectory frames to confirm visual presence of a 3D revolved shaft.
"""

import json
import os
import tempfile
import logging
import struct
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_stl(filepath):
    """Parses an STL file (ASCII or Binary) and returns a list of vertices."""
    vertices = []
    try:
        with open(filepath, 'rb') as f:
            header = f.read(80)
            
            # Check if ASCII
            try:
                if b'solid' in header[:5]:
                    f.seek(0)
                    text = f.read().decode('utf-8', errors='ignore')
                    if 'facet normal' in text:
                        lines = text.split('\n')
                        for line in lines:
                            parts = line.strip().split()
                            if len(parts) == 4 and parts[0] == 'vertex':
                                vertices.append([float(parts[1]), float(parts[2]), float(parts[3])])
                        return vertices
            except Exception as e:
                logger.warning(f"Failed to parse as ASCII STL: {e}")
            
            # Parse as Binary
            f.seek(80)
            count_bytes = f.read(4)
            if len(count_bytes) != 4:
                return []
            count = struct.unpack('<I', count_bytes)[0]
            
            for _ in range(count):
                data = f.read(50)
                if len(data) != 50:
                    break
                unpacked = struct.unpack('<12fH', data)
                vertices.extend([unpacked[3:6], unpacked[6:9], unpacked[9:12]])
                
    except Exception as e:
        logger.error(f"Error reading STL file: {e}")
        
    return vertices


def compute_mesh_properties(vertices):
    """Computes volume, bounding box, and triangle count from vertices."""
    if not vertices or len(vertices) % 3 != 0:
        return None, None, None, 0
        
    verts = np.array(vertices)
    triangle_count = len(verts) // 3
    
    # Bounding Box
    min_v = np.min(verts, axis=0)
    max_v = np.max(verts, axis=0)
    bbox_extents = max_v - min_v
    
    # Volume (divergence theorem / signed tetrahedron volume)
    v1 = verts[0::3]
    v2 = verts[1::3]
    v3 = verts[2::3]
    vols = np.sum(v1 * np.cross(v2, v3), axis=1) / 6.0
    total_vol = abs(np.sum(vols))
    
    return total_vol, bbox_extents, min_v, triangle_count


def verify_lathe_revolve(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_vol = metadata.get('expected_volume_mm3', 7555)
    vol_tol = metadata.get('volume_tolerance_percent', 40) / 100.0
    expected_b = metadata.get('expected_bounds', {'x': 30, 'y': 25, 'z': 30})
    b_tol = metadata.get('bounds_tolerance_mm', 5.0)

    score = 0
    feedback_parts = []
    
    # 1. Read task metadata
    meta_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", meta_file.name)
        with open(meta_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(meta_file.name): os.unlink(meta_file.name)

    # Validate creation
    slvs_meta = result.get('slvs', {})
    stl_meta = result.get('stl', {})
    
    if slvs_meta.get('exists') and slvs_meta.get('created_during_task'):
        score += 5
        feedback_parts.append("SLVS file created")
    else:
        feedback_parts.append("SLVS file missing or not created during task")

    if stl_meta.get('exists') and stl_meta.get('created_during_task'):
        score += 5
        feedback_parts.append("STL file created")
    else:
        feedback_parts.append("STL file missing or not created during task")

    # 2. Analyze SLVS file
    slvs_file = tempfile.NamedTemporaryFile(delete=False, suffix='.slvs')
    has_lathe = False
    has_lines = False
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/stepped_shaft.slvs", slvs_file.name)
        with open(slvs_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            # 5020 is Lathe group type, 11000 is Line entity type
            if 'Group.type=5020' in content:
                has_lathe = True
                score += 15
                feedback_parts.append("Lathe operation used")
            else:
                feedback_parts.append("Lathe group not found in project")
                
            if 'Entity.type=11000' in content:
                has_lines = True
                score += 5
                feedback_parts.append("Line entities drawn")
    except Exception as e:
        logger.warning(f"SLVS parsing error: {e}")
    finally:
        if os.path.exists(slvs_file.name): os.unlink(slvs_file.name)

    # 3. Analyze STL file
    stl_file = tempfile.NamedTemporaryFile(delete=False, suffix='.stl')
    valid_mesh = False
    axial_symmetry = False
    try:
        copy_from_env("/home/ga/Documents/SolveSpace/stepped_shaft.stl", stl_file.name)
        vertices = parse_stl(stl_file.name)
        if len(vertices) > 0:
            vol, extents, min_v, count = compute_mesh_properties(vertices)
            if count >= 50:
                score += 10
                valid_mesh = True
                feedback_parts.append(f"Valid mesh ({count} triangles)")
                
                # Check bounds
                if abs(extents[0] - expected_b['x']) <= b_tol:
                    score += 10
                if abs(extents[1] - expected_b['y']) <= b_tol:
                    score += 10
                if abs(extents[2] - expected_b['z']) <= b_tol:
                    score += 5
                
                # Axial symmetry check (Revolve solid should have roughly equal X and Z extents)
                if extents[2] > 0 and 0.8 <= (extents[0] / extents[2]) <= 1.25:
                    axial_symmetry = True
                    score += 10
                    feedback_parts.append("Axial symmetry confirmed")
                else:
                    feedback_parts.append("Failed axial symmetry check (likely an extrude instead of lathe)")
                
                # Volume check
                min_vol = expected_vol * (1.0 - vol_tol)
                max_vol = expected_vol * (1.0 + vol_tol)
                if min_vol <= vol <= max_vol:
                    score += 10
                    feedback_parts.append(f"Volume correct (~{vol:.0f} mm3)")
                else:
                    feedback_parts.append(f"Volume incorrect: {vol:.0f} mm3 (expected ~{expected_vol})")
            else:
                feedback_parts.append(f"Mesh has too few triangles ({count})")
    except Exception as e:
        logger.warning(f"STL parsing error: {e}")
    finally:
        if os.path.exists(stl_file.name): os.unlink(stl_file.name)

    # 4. VLM Trajectory Verification
    vlm_passed = False
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        final_frame = get_final_screenshot(traj)
        if final_frame:
            frames.append(final_frame)
            
        prompt = """Look at these frames of a user working in SolveSpace.
Did the user successfully draw a 2D profile and revolve it into a 3D stepped shaft?
In the final frames, you should see a 3D cylindrical shape with a wider section (flange) and a narrower section (shaft) in the canvas.
Return a JSON object with:
{"revolve_solid_visible": true/false, "stepped_shaft_shape": true/false}"""
        
        try:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('parsed'):
                parsed = vlm_res['parsed']
                if parsed.get('revolve_solid_visible') and parsed.get('stepped_shaft_shape'):
                    vlm_passed = True
                    score += 15
                    feedback_parts.append("VLM confirmed 3D revolved shaft visible")
                else:
                    feedback_parts.append("VLM did not detect final 3D stepped shaft")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification failed")

    # Evaluate final passage
    key_criteria_met = valid_mesh and has_lathe and axial_symmetry
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }