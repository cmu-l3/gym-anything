#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_adjustable_motor_base(traj, env_info, task_info):
    """
    Verifies the adjustable motor base plate task.
    
    Criteria:
    1. File creation and validity (10 pts)
    2. Layer Setup (PLATE=White, SLOTS=Cyan) (10 pts)
    3. Plate Geometry (300x250 rect) (30 pts)
    4. Slot Geometry (Correct count and bounds) (30 pts)
    5. Anti-gaming (File modified during task) (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # Check 1: File Exists & Created During Task
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
    
    if result.get("file_created_during_task"):
        score += 20
        feedback.append("File created during task.")
    else:
        feedback.append("File timestamp indicates it was not created during this session.")

    dxf = result.get("dxf_analysis", {})
    if not dxf.get("valid_dxf"):
        return {"passed": False, "score": score, "feedback": "File exists but is not a valid DXF."}
    
    score += 10 # Valid DXF
    feedback.append("Valid DXF file.")

    # Check 2: Layers
    layers = dxf.get("layers", {})
    plate_layer = layers.get("PLATE")
    slots_layer = layers.get("SLOTS")
    
    layer_score = 0
    if plate_layer and plate_layer.get("color") == 7: # White
        layer_score += 5
    if slots_layer and slots_layer.get("color") == 4: # Cyan
        layer_score += 5
    
    if layer_score == 10:
        feedback.append("Layers PLATE and SLOTS configured correctly.")
    else:
        feedback.append(f"Layer configuration incomplete (Score: {layer_score}/10).")
    score += layer_score

    # Check 3: Plate Geometry
    # Expect bounds close to 0,0 and 300,250
    plate_bounds = dxf.get("plate_bounds")
    if plate_bounds:
        min_x, min_y, max_x, max_y = plate_bounds
        # Allow small tolerance
        valid_min = abs(min_x) < 2 and abs(min_y) < 2
        valid_max = abs(max_x - 300) < 2 and abs(max_y - 250) < 2
        
        if valid_min and valid_max:
            score += 30
            feedback.append("Plate outline geometry correct (300x250).")
        else:
            score += 10 # Partial credit for having something on the layer
            feedback.append(f"Plate dimensions incorrect. Found: ({min_x:.1f},{min_y:.1f}) to ({max_x:.1f},{max_y:.1f}).")
    else:
        feedback.append("No geometry found on layer PLATE.")

    # Check 4: Slot Geometry
    # Expect 4 slots. If drawn as Arcs+Lines: 8 Arcs, 8 Lines.
    # Slot bounds:
    #   Min X: 50 (center) - 7 (radius) = 43
    #   Max X: 250 (center) + 7 (radius) = 257
    #   Min Y: 50 (center) - 7 (radius) = 43
    #   Max Y: 200 (center) + 7 (radius) = 207
    slot_bounds = dxf.get("slot_bounds")
    slot_score = 0
    
    if slot_bounds:
        s_min_x, s_min_y, s_max_x, s_max_y = slot_bounds
        
        # Check overall bounds of the slots layer
        bounds_ok = (abs(s_min_x - 43) < 5 and abs(s_min_y - 43) < 5 and
                     abs(s_max_x - 257) < 5 and abs(s_max_y - 207) < 5)
        
        entities = dxf.get("slot_entities", {})
        arc_count = entities.get("ARC", 0)
        line_count = entities.get("LINE", 0)
        lw_count = entities.get("LWPOLYLINE", 0)
        
        # Criteria: Either 8 arcs + 8 lines, OR 4 closed polylines
        structure_ok = False
        if arc_count >= 8 and line_count >= 8:
            structure_ok = True
        elif lw_count >= 4:
            structure_ok = True
            
        if bounds_ok:
            slot_score += 15
            feedback.append("Slot positioning correct.")
        else:
            feedback.append(f"Slot bounds incorrect. Found: ({s_min_x:.1f},{s_min_y:.1f}) to ({s_max_x:.1f},{s_max_y:.1f}).")
            
        if structure_ok:
            slot_score += 15
            feedback.append("Slot geometry structure looks correct (sufficient entities).")
        else:
            feedback.append("Slot geometry incomplete (missing arcs/lines).")
    else:
        feedback.append("No geometry found on layer SLOTS.")
    
    score += slot_score

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }