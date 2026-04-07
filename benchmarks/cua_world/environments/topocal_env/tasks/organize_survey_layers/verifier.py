#!/usr/bin/env python3
"""
Verifier for organize_survey_layers task in TopoCal.

Verification criteria:
1. DXF file exported properly.
2. Layers V-TREE, V-FENCE, V-ROAD exist with correct colors.
3. Entities correctly segregated onto layers based on descriptions (checked via bounding boxes).
4. VLM verifies TopoCal UI manipulation.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Dynamically ensure ezdxf is installed for verification
try:
    import ezdxf
    EZDXF_AVAILABLE = True
except ImportError:
    EZDXF_AVAILABLE = False

def ensure_dependencies():
    global EZDXF_AVAILABLE
    if not EZDXF_AVAILABLE:
        import subprocess
        import sys
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "ezdxf"])
            global ezdxf
            import ezdxf
            EZDXF_AVAILABLE = True
        except Exception as e:
            logger.error(f"Failed to install ezdxf: {e}")
            return False
    return True

def verify_organize_survey_layers(traj, env_info, task_info):
    if not ensure_dependencies():
        return {"passed": False, "score": 0, "feedback": "Verifier failed to install dependency (ezdxf)"}

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback = []

    # 1. Retrieve the Task Result JSON
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_result:
        try:
            copy_from_env(r"C:\Users\Docker\AppData\Local\Temp\task_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
        finally:
            os.unlink(temp_result.name)

    # Validate DXF Creation
    if not result.get('dxf_exists'):
        return {"passed": False, "score": 0, "feedback": "DXF output file was not created"}
    if not result.get('dxf_created_during_task'):
        feedback.append("Warning: DXF file timestamp precedes task start (possible anti-gaming violation)")
    else:
        score += 10
        feedback.append("File Exported Successfully")

    # 2. Retrieve Ground Truth Coordinates
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as temp_truth:
        try:
            copy_from_env(r"C:\Users\Docker\AppData\Local\Temp\ground_truth.json", temp_truth.name)
            with open(temp_truth.name, 'r') as f:
                truth = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {e}"}
        finally:
            os.unlink(temp_truth.name)

    # 3. Retrieve DXF File for parsing
    dxf_local_path = tempfile.NamedTemporaryFile(delete=False, suffix='.dxf').name
    try:
        copy_from_env(r"C:\Users\Docker\Documents\layered_delivery.dxf", dxf_local_path)
        doc = ezdxf.readfile(dxf_local_path)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse DXF file: {e}"}
    finally:
        if os.path.exists(dxf_local_path):
            os.unlink(dxf_local_path)

    msp = doc.modelspace()
    layers = doc.layers

    # Check Layer Existence and Colors
    target_layers = {
        "V-TREE": {"color": 3, "points": 15},  # Green
        "V-FENCE": {"color": 2, "points": 15}, # Yellow
        "V-ROAD": {"color": 1, "points": 15}   # Red
    }

    layers_exist = 0
    colors_correct = 0

    for layer_name, specs in target_layers.items():
        if layers.has(layer_name):
            layers_exist += 1
            layer_obj = layers.get(layer_name)
            if layer_obj.color == specs["color"]:
                colors_correct += 1
            else:
                feedback.append(f"Layer {layer_name} has wrong color (Got {layer_obj.color}, expected {specs['color']})")
        else:
            feedback.append(f"Missing required layer: {layer_name}")

    score += (layers_exist * 5)
    score += (colors_correct * 5)
    if layers_exist == 3: feedback.append("All layers created")
    if colors_correct == 3: feedback.append("All layer colors correct")

    # 4. Check Data Segregation via Spatial Bounds
    # Since CAD tools export points as POINTS, BLOCKS, or TEXT, bounding box checks are robust
    for category, spec in [("TREE", "V-TREE"), ("FENCE", "V-FENCE"), ("ROAD", "V-ROAD")]:
        expected_points = truth.get(category, [])
        if not expected_points: continue

        min_x = min(p['x'] for p in expected_points) - 5
        max_x = max(p['x'] for p in expected_points) + 5
        min_y = min(p['y'] for p in expected_points) - 5
        max_y = max(p['y'] for p in expected_points) + 5

        # Find all entities on this layer
        entities = msp.query(f'*[layer=="{spec}"]')
        
        # If no entities on this layer, fail this category
        if not len(entities):
            feedback.append(f"No entities found on layer {spec}")
            continue

        # Check if the entities lie within the expected geographical cluster
        valid_entities = 0
        for e in entities:
            # Check DXF specific coordinates depending on entity type
            pt = None
            if e.dxftype() == 'POINT':
                pt = e.dxf.location
            elif e.dxftype() == 'INSERT':
                pt = e.dxf.insert
            elif e.dxftype() == 'TEXT' or e.dxftype() == 'MTEXT':
                pt = e.dxf.insert

            if pt and (min_x <= pt.x <= max_x) and (min_y <= pt.y <= max_y):
                valid_entities += 1
        
        if valid_entities > 0:
            pts = 15 if category in ["TREE", "ROAD"] else 10
            score += pts
            feedback.append(f"Points successfully segregated into {spec}")
        else:
            feedback.append(f"Entities on {spec} do not match coordinates for {category}")

    # 5. Visual Trajectory Verification (VLM)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            vlm_prompt = """
            Look at these frames of an agent using TopoCal. 
            Did the agent open the Layer Manager (Gestor de Capas) or use the point selection/filtering interface to assign survey points to layers?
            Respond with ONLY 'YES' or 'NO'.
            """
            vlm_res = query_vlm(prompt=vlm_prompt, images=frames)
            if vlm_res.get("success") and "YES" in vlm_res.get("response", "").upper():
                vlm_score += 20
                feedback.append("VLM verified use of TopoCal UI for layers")
            else:
                feedback.append("VLM did not detect layer management UI usage")
    
    score += vlm_score

    # Passing conditions: At least two layers properly segregated + UI usage verified
    passed = score >= 70

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }