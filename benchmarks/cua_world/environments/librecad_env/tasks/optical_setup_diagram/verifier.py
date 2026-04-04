#!/usr/bin/env python3
import json
import os
import tempfile
import math
import logging
from typing import Dict, Any, List, Tuple

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

def verify_optical_setup(traj, env_info, task_info):
    """
    Verifies the Optical Setup Diagram task in LibreCAD.
    
    Criteria:
    1. File Creation: DXF file exists and was created during task.
    2. Layers: COMPONENTS (Cyan), BEAM (Red), LABELS (White) exist.
    3. Beam Geometry: Polyline connecting (0,0)->(300,0)->(300,200)->(0,200).
    4. Components: Mirrors and Lens at correct coordinates/angles.
    5. Annotation: Text note with "800" for path length.
    6. VLM: Visual confirmation of schematic appearance.
    """
    
    # 1. Setup and Basic File Checks
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/LibreCAD/optical_setup.dxf')
    
    # Load task result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env("/tmp/task_result.json", f.name)
            f.seek(0)
            task_result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}

    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output DXF file was not found."}
        
    if not task_result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was not created or modified during the task session."}

    # 2. Download and Parse DXF
    score = 10 # Base score for file existence
    feedback_log = ["File created successfully."]
    
    dxf_temp = tempfile.NamedTemporaryFile(suffix='.dxf', delete=False)
    dxf_temp.close()
    
    try:
        copy_from_env(expected_path, dxf_temp.name)
        
        try:
            import ezdxf
            doc = ezdxf.readfile(dxf_temp.name)
            msp = doc.modelspace()
        except ImportError:
            return {"passed": False, "score": 0, "feedback": "Verifier configuration error: ezdxf not installed."}
        except Exception as e:
             return {"passed": False, "score": score, "feedback": f"Invalid DXF file: {str(e)}"}

        # 3. Verify Layers (15 points)
        # Specs: COMPONENTS (Cyan/4), BEAM (Red/1), LABELS (White/7)
        layer_specs = metadata.get('layer_specs', {})
        layers_found = 0
        total_layers = len(layer_specs)
        
        for layer_name, expected_color in layer_specs.items():
            if layer_name in doc.layers:
                layer = doc.layers.get(layer_name)
                # Check color (strict or flexible? Let's match exact index or accept close standard colors)
                if layer.color == expected_color:
                    layers_found += 1
                    feedback_log.append(f"Layer '{layer_name}' found with correct color.")
                else:
                    feedback_log.append(f"Layer '{layer_name}' found but wrong color (Got {layer.color}, Exp {expected_color}).")
                    layers_found += 0.5 # Partial credit for name
            else:
                feedback_log.append(f"Layer '{layer_name}' missing.")
        
        score += (layers_found / total_layers) * 15

        # 4. Verify Beam Geometry (25 points)
        # Expected: Polyline or Lines connecting (0,0) -> (300,0) -> (300,200) -> (0,200)
        # We will search for a RED entity that covers these points
        beam_points_met = 0
        expected_beam_points = [(0,0), (300,0), (300,200), (0,200)]
        
        # Collect all lines/polylines on BEAM layer
        beam_entities = msp.query(f'*[layer=="BEAM"]')
        beam_vertices = []
        
        for e in beam_entities:
            if e.dxftype() == 'LINE':
                beam_vertices.append(list(e.dxf.start)[:2])
                beam_vertices.append(list(e.dxf.end)[:2])
            elif e.dxftype() in ['LWPOLYLINE', 'POLYLINE']:
                # ezdxf handles polyline points differently
                try:
                    points = e.get_points() # format varies by type
                    for p in points:
                        beam_vertices.append(list(p)[:2])
                except:
                    # Fallback for LWPolyline
                    if hasattr(e, 'lwpoints'):
                        for p in e.lwpoints:
                            beam_vertices.append(list(p)[:2])

        # Check for proximity to expected points
        found_points = set()
        tolerance = 5.0 # mm
        
        for exp_p in expected_beam_points:
            for act_p in beam_vertices:
                dist = math.hypot(exp_p[0] - act_p[0], exp_p[1] - act_p[1])
                if dist < tolerance:
                    found_points.add(tuple(exp_p))
                    break
        
        if len(found_points) == 4:
            score += 25
            feedback_log.append("Beam path geometry correct.")
        elif len(found_points) >= 2:
            score += 10
            feedback_log.append(f"Partial beam path found ({len(found_points)}/4 points).")
        else:
            feedback_log.append("Beam path geometry incorrect or missing on BEAM layer.")

        # 5. Verify Mirrors (30 points - 15 each)
        # M1: Center (300,0), Angle ~135 or -45
        # M2: Center (300,200), Angle ~45 or 225
        # Helper to find lines near a center with specific angle
        def check_mirror(center, expected_angles, tolerance_pos=5.0, tolerance_ang=5.0):
            candidates = msp.query(f'LINE[layer=="COMPONENTS"]')
            for line in candidates:
                start = line.dxf.start
                end = line.dxf.end
                mid = ((start.x + end.x)/2, (start.y + end.y)/2)
                
                # Check position
                pos_dist = math.hypot(mid[0]-center[0], mid[1]-center[1])
                if pos_dist < tolerance_pos:
                    # Check angle
                    dx = end.x - start.x
                    dy = end.y - start.y
                    angle_deg = math.degrees(math.atan2(dy, dx)) % 360
                    
                    for exp_ang in expected_angles:
                        exp_norm = exp_ang % 360
                        if abs(angle_deg - exp_norm) < tolerance_ang or abs(angle_deg - exp_norm) > (360-tolerance_ang):
                            return True
            return False

        if check_mirror((300,0), [135, 315, -45]):
            score += 15
            feedback_log.append("Mirror 1 correct.")
        else:
            feedback_log.append("Mirror 1 missing or incorrect (check pos (300,0) and angle 135).")

        if check_mirror((300,200), [45, 225]):
            score += 15
            feedback_log.append("Mirror 2 correct.")
        else:
            feedback_log.append("Mirror 2 missing or incorrect (check pos (300,200) and angle 45).")

        # 6. Verify Lens (10 points)
        # Ellipse at (150, 200)
        lens_found = False
        ellipses = msp.query(f'ELLIPSE[layer=="COMPONENTS"]')
        for e in ellipses:
            center = e.dxf.center
            dist = math.hypot(center.x - 150, center.y - 200)
            if dist < 5.0:
                lens_found = True
                break
        
        if lens_found:
            score += 10
            feedback_log.append("Lens found.")
        else:
            feedback_log.append("Lens missing or misplaced.")

        # 7. Verify Annotation (10 points)
        # Text "800" on LABELS layer
        text_found = False
        texts = msp.query(f'TEXT MTEXT') # Query both types
        for t in texts:
            content = ""
            if t.dxftype() == 'TEXT':
                content = t.dxf.text
            elif t.dxftype() == 'MTEXT':
                content = t.text
            
            if "800" in content:
                text_found = True
                break
        
        if text_found:
            score += 10
            feedback_log.append("Path length annotation '800' found.")
        else:
            feedback_log.append("Path length annotation missing (expected '800').")

    except Exception as e:
        feedback_log.append(f"Error parsing DXF geometry: {str(e)}")
    finally:
        if os.path.exists(dxf_temp.name):
            os.unlink(dxf_temp.name)

    # 8. VLM Verification (Trajectory-based backup)
    # If program score is borderline, VLM can verify visual structure
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=3)
    final_shot = get_final_screenshot(traj)
    
    if final_shot:
        vlm_prompt = (
            "This is a CAD task to draw an optical schematic. "
            "Does the final image show a diagram with cyan components, "
            "a red beam path forming a 'Z' shape, and text annotations? "
            "Reply with JSON: {'is_schematic': bool, 'has_z_shape': bool}"
        )
        
        # Only verify last frame to save cost/latency, or fallback if programmatic failed
        # Here we use it as a sanity check if score > 50
        try:
            vlm_result = query_vlm(images=[final_shot], prompt=vlm_prompt)
            parsed = vlm_result.get('parsed', {})
            if parsed.get('is_schematic', False) and parsed.get('has_z_shape', False):
                # Bonus or validation
                if score < 100:
                    score = min(100, score + 5)
                    feedback_log.append("VLM confirms schematic appearance.")
        except Exception:
            pass # VLM fail shouldn't crash verifier if programmatic worked

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_log)
    }