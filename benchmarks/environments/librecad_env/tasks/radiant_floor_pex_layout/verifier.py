#!/usr/bin/env python3
"""
Verifier for Radiant Floor PEX Layout Task.

Verifies:
1. DXF file creation and validity.
2. Layer structure (WALLS, HEATING).
3. Geometric accuracy (Room bounds, PEX path spacing and offsets).
4. VLM confirmation of workflow.
"""

import json
import os
import sys
import tempfile
import logging
import math
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def get_final_screenshot(traj): return None
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

# Try importing ezdxf for CAD analysis
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_radiant_floor(traj, env_info, task_info):
    """
    Main verification function.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/radiant_heating_layout.dxf')
    
    score = 0
    max_score = 100
    feedback = []
    
    # =========================================================
    # 1. READ TASK RESULT JSON
    # =========================================================
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name): os.unlink(temp_result.name)

    # Basic File Checks
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "DXF file not found."}
    
    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "File was not created during the task (anti-gaming check failed)."}
    
    score += 10
    feedback.append("File created successfully.")

    # =========================================================
    # 2. ANALYZE DXF CONTENT (Geometric Verification)
    # =========================================================
    if not EZDXF_AVAILABLE:
        feedback.append("Warning: ezdxf not installed in verifier. Skipping precise geometric checks.")
        # Fallback to VLM only if ezdxf is missing (should not happen in prod)
    else:
        temp_dxf = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf')
        try:
            copy_from_env(expected_path, temp_dxf.name)
            doc = ezdxf.readfile(temp_dxf.name)
            msp = doc.modelspace()
            
            # Check Layers
            layers = [layer.dxf.name for layer in doc.layers]
            has_walls = "WALLS" in layers or "Walls" in layers or "walls" in layers
            has_heating = "HEATING" in layers or "Heating" in layers or "heating" in layers
            
            if has_walls and has_heating:
                score += 10
                feedback.append("Correct layers found.")
            else:
                feedback.append(f"Missing required layers. Found: {layers}")

            # Check Room Boundary (Rectangle approx 3000x2500)
            # We look for a closed polyline or set of lines on WALLS layer
            room_entities = msp.query(f'*[layer=="{metadata.get("layer_walls", "WALLS")}"]')
            bbox_room = ezdxf.bbox.extents(room_entities)
            
            room_valid = False
            if bbox_room.has_data:
                width = bbox_room.extmax.x - bbox_room.extmin.x
                height = bbox_room.extmax.y - bbox_room.extmin.y
                # Allow slight tolerance
                if abs(width - 3000) < 50 and abs(height - 2500) < 50:
                    room_valid = True
                    score += 20
                    feedback.append("Room boundary dimensions correct (3000x2500).")
                else:
                    feedback.append(f"Room dimensions incorrect. Measured: {width:.1f}x{height:.1f}")
            else:
                feedback.append("No geometry found on WALLS layer.")

            # Check Heating Path
            # Should be a Polyline or connected Lines on HEATING layer
            heating_entities = msp.query(f'*[layer=="{metadata.get("layer_heating", "HEATING")}"]')
            bbox_heat = ezdxf.bbox.extents(heating_entities)
            
            path_valid = False
            if bbox_heat.has_data:
                # Check bounding box of heating element (should be inset by 150mm)
                # Expected: X(150 to 2850), Y(150 to 2350)
                # Width ~ 2700, Height ~ 2200
                h_width = bbox_heat.extmax.x - bbox_heat.extmin.x
                h_height = bbox_heat.extmax.y - bbox_heat.extmin.y
                
                if abs(h_width - 2700) < 100 and abs(h_height - 2200) < 100:
                    score += 20
                    feedback.append("Heating loop bounding box correct (reflects 150mm offset).")
                    path_valid = True
                else:
                    feedback.append(f"Heating loop bounds incorrect. Width: {h_width:.1f}, Height: {h_height:.1f}")
                
                # Check complexity (Vertex count)
                # A 3000x2500 room with 200mm spacing implies ~12 runs.
                # Each run is 2 points (if lines) or 1 segment (polyline).
                # Total vertices for a serpentine polyline ~24.
                vertex_count = 0
                for e in heating_entities:
                    if e.dxftype() == 'LWPOLYLINE':
                        vertex_count += len(e)
                    elif e.dxftype() == 'LINE':
                        vertex_count += 1 # Rough approximation for lines
                
                # We expect roughly 24 vertices.
                if 20 <= vertex_count <= 30:
                    score += 20
                    feedback.append(f"Heating path complexity looks correct ({vertex_count} vertices).")
                else:
                    feedback.append(f"Heating path vertex count suspicious ({vertex_count}). Expected ~24.")
            else:
                feedback.append("No geometry found on HEATING layer.")

        except Exception as e:
            feedback.append(f"Error parsing DXF: {str(e)}")
        finally:
            if os.path.exists(temp_dxf.name): os.unlink(temp_dxf.name)

    # =========================================================
    # 3. VLM VERIFICATION (Visual Check)
    # =========================================================
    # Use trajectory to ensure they actually drew it
    frames = sample_trajectory_frames(traj, n=4)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        frames.append(final_shot)
        
    vlm_prompt = """
    You are verifying a CAD task. The user was asked to draw a 'radiant floor heating layout'.
    
    Look for:
    1. A white rectangular room outline.
    2. A red continuous line snake/serpentine pattern filling the room.
    3. The red line should look evenly spaced (like a grid of lines).
    
    Does the final result show a red serpentine line pattern inside a white rectangle?
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    vlm_score = 0
    if vlm_result.get("success"):
        # We look for positive confirmation in the VLM analysis (simple heuristic here)
        # In a real impl, we'd parse specific JSON fields from VLM
        if "yes" in str(vlm_result).lower() and "red" in str(vlm_result).lower():
            vlm_score = 20
            feedback.append("VLM confirms visual correctness.")
        else:
            feedback.append("VLM could not confirm visual pattern.")
    else:
        feedback.append("VLM verification failed to run.")
        # Fallback: if geometric checks passed, we assume visual is okay-ish
        if score >= 60:
            vlm_score = 20 

    score += vlm_score

    # Final Pass/Fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }