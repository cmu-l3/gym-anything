#!/usr/bin/env python3
"""
Verifier for flatten_3d_breaklines task.

Multi-Criteria Verification:
1. File Verification: DXF file exists and was created during the task.
2. Content parsing (ezdxf): Parses the output DXF to evaluate geometry.
3. Planimetric strictness: Checks that NO entity has a Z-value > 0.001 (Fully flattened).
4. Data Integrity: Ensures lines weren't just deleted (checks minimum entity count & spatial extent).
5. VLM Trajectory: Uses VLM across trajectory frames to confirm genuine UI interaction with TopoCal.
"""

import os
import json
import logging
import tempfile
import sys
import subprocess

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def ensure_ezdxf():
    """Install ezdxf dynamically if not available on the host."""
    try:
        import ezdxf
        return True, ezdxf
    except ImportError:
        logger.info("ezdxf not found. Installing...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
            import ezdxf
            return True, ezdxf
        except Exception as e:
            logger.error(f"Failed to install ezdxf: {e}")
            return False, None

def verify_flatten_3d_breaklines(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    # 1. Fetch JSON result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    created_during_task = result.get('file_created_during_task', False)

    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "DXF output file was not found at the expected location."
        }
    
    score += 10
    feedback_parts.append("DXF file exported")

    if created_during_task:
        score += 10
        feedback_parts.append("File created/modified during task execution")
    else:
        feedback_parts.append("Warning: File timestamp predates task start")

    # 2. Fetch DXF file to host
    temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
    dxf_fetched = False
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\architectural_basemap_2d.dxf", temp_dxf.name)
        dxf_fetched = True
    except Exception as e:
        feedback_parts.append(f"Failed to fetch DXF: {e}")
    
    # 3. Parse DXF Content
    entities_valid = False
    fully_flattened = False
    
    if dxf_fetched:
        has_ezdxf, ezdxf = ensure_ezdxf()
        if has_ezdxf:
            try:
                doc = ezdxf.readfile(temp_dxf.name)
                msp = doc.modelspace()
                
                z_values = []
                entity_count = 0
                
                # Bounding box trackers to prevent "deleted everything except 1 line" gaming
                min_x, max_x = float('inf'), float('-inf')
                min_y, max_y = float('inf'), float('-inf')

                # Extract coordinates from common CAD entities
                for entity in msp:
                    entity_count += 1
                    if entity.dxftype() == 'LINE':
                        z_values.extend([entity.dxf.start.z, entity.dxf.end.z])
                        min_x = min(min_x, entity.dxf.start.x, entity.dxf.end.x)
                        max_x = max(max_x, entity.dxf.start.x, entity.dxf.end.x)
                        min_y = min(min_y, entity.dxf.start.y, entity.dxf.end.y)
                        max_y = max(max_y, entity.dxf.start.y, entity.dxf.end.y)
                        
                    elif entity.dxftype() == 'LWPOLYLINE':
                        # LWPOLYLINE has a global elevation attribute
                        z_values.append(entity.dxf.get('elevation', 0.0))
                        with entity.points() as points:
                            for p in points:
                                min_x = min(min_x, p[0])
                                max_x = max(max_x, p[0])
                                min_y = min(min_y, p[1])
                                max_y = max(max_y, p[1])
                                
                    elif entity.dxftype() == 'POLYLINE':
                        for vertex in entity.vertices:
                            z_values.append(vertex.dxf.location.z)
                            min_x = min(min_x, vertex.dxf.location.x)
                            max_x = max(max_x, vertex.dxf.location.x)
                            min_y = min(min_y, vertex.dxf.location.y)
                            max_y = max(max_y, vertex.dxf.location.y)
                            
                    elif entity.dxftype() == 'POINT':
                        z_values.append(entity.dxf.location.z)
                        min_x = min(min_x, entity.dxf.location.x)
                        max_x = max(max_x, entity.dxf.location.x)

                # Integrity Checks
                if entity_count >= 10 and (max_x - min_x > 5):
                    entities_valid = True
                    score += 20
                    feedback_parts.append(f"Horizontal geometry preserved ({entity_count} entities)")
                else:
                    feedback_parts.append("DXF lacks sufficient spatial geometry (Possible deletion cheat)")

                # Z-Coordinate Checks
                if entities_valid and len(z_values) > 0:
                    max_z = max(abs(z) for z in z_values)
                    if max_z <= 0.001:
                        fully_flattened = True
                        score += 40
                        feedback_parts.append("All coordinates strictly flattened to Z=0.00")
                    else:
                        feedback_parts.append(f"Failed to flatten: Max elevation found is {max_z:.2f}")

            except Exception as e:
                feedback_parts.append(f"DXF parse error: {str(e)}")
        else:
            feedback_parts.append("Skipped local DXF verify (ezdxf not installed)")
            # Grace partial points if library failed, but require VLM fallback
            score += 20 

    if os.path.exists(temp_dxf.name):
        os.unlink(temp_dxf.name)

    # 4. VLM Verification (Trajectory checks)
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    query_func = env_info.get('query_vlm')
    if query_func:
        frames = sample_trajectory_frames(traj, n=4)
        final = get_final_screenshot(traj)
        images = frames + [final] if final else frames
        
        prompt = """Look at these trajectory screenshots of an agent using TopoCal.
        Did the agent successfully do the following?
        1. Select 3D polylines/lines in the drawing.
        2. Access property tools or menus (like 'Pasar a 2D' or 'Cota') to set Z-elevation to 0.
        3. Navigate to File -> Export -> DXF to save the file.
        
        Respond with JSON containing:
        {
            "worked_in_topocal": true/false,
            "modified_z_properties": true/false,
            "exported_dxf": true/false
        }"""
        
        vlm_res = query_func(prompt=prompt, images=images)
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("worked_in_topocal") and parsed.get("modified_z_properties"):
                score += 15
                feedback_parts.append("VLM confirmed UI property modification")
            if parsed.get("exported_dxf"):
                score += 5
                feedback_parts.append("VLM confirmed DXF export UI")

    # Evaluate Pass/Fail Condition
    key_criteria_met = output_exists and fully_flattened and entities_valid
    passed = (score >= 80) and key_criteria_met
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }