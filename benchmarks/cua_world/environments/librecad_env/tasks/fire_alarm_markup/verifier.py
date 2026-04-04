#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fire_alarm_markup(traj, env_info, task_info):
    """
    Verifies the Fire Alarm Markup task by analyzing the JSON report 
    generated inside the container by ezdxf.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve task result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Parsing results
    dxf_analysis = result.get("dxf_analysis", {})
    output_exists = result.get("output_exists", False)
    file_created_during = result.get("file_created_during_task", False)
    initial_count = result.get("initial_entity_count", 0)
    
    # ---------------------------------------------------------
    # SCORING CRITERIA
    # ---------------------------------------------------------
    score = 0
    feedback = []

    # 1. File Basics (15 pts)
    if output_exists and result.get("output_size_bytes", 0) > 100000:
        score += 5
        feedback.append("Output file exists and has reasonable size.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file missing or empty."}

    if file_created_during:
        score += 10
        feedback.append("File was modified/created during task.")
    else:
        feedback.append("File timestamp indicates no modification during task.")

    if not dxf_analysis.get("valid_dxf", False):
         return {"passed": False, "score": score, "feedback": "Output is not a valid DXF file."}

    # 2. Entity Preservation (10 pts)
    final_count = dxf_analysis.get("entity_count", 0)
    if final_count >= initial_count:
        score += 10
        feedback.append("Original entities preserved.")
    else:
        feedback.append(f"Entity count dropped ({initial_count} -> {final_count}). Original drawing may be damaged.")

    # 3. Layers (15 pts)
    layers = dxf_analysis.get("layers_found", [])
    layer_names = [l["name"] for l in layers]
    
    # Check Devices Layer
    dev_layer = next((l for l in layers if l["name"] == "FIRE-ALARM-DEVICES"), None)
    if dev_layer:
        if dev_layer["color"] == 1: # Red
            score += 8
            feedback.append("Layer 'FIRE-ALARM-DEVICES' correct (Red).")
        else:
            score += 4
            feedback.append("Layer 'FIRE-ALARM-DEVICES' exists but wrong color.")
    else:
        feedback.append("Layer 'FIRE-ALARM-DEVICES' missing.")

    # Check Wiring Layer
    wire_layer = next((l for l in layers if l["name"] == "FIRE-ALARM-WIRING"), None)
    if wire_layer:
        if wire_layer["color"] == 2: # Yellow
            score += 7
            feedback.append("Layer 'FIRE-ALARM-WIRING' correct (Yellow).")
        else:
            score += 3
            feedback.append("Layer 'FIRE-ALARM-WIRING' exists but wrong color.")
    else:
        feedback.append("Layer 'FIRE-ALARM-WIRING' missing.")

    # 4. Smoke Detectors (20 pts)
    # Target: 4 circles
    circles_found = dxf_analysis.get("circles_found", 0)
    score += min(circles_found * 5, 20)
    feedback.append(f"Found {circles_found}/4 smoke detectors at correct locations.")

    # 5. Control Panel (10 pts)
    rects_found = dxf_analysis.get("rectangles_found", 0)
    if rects_found >= 1:
        score += 10
        feedback.append("Control Panel rectangle found.")
    else:
        feedback.append("Control Panel rectangle missing or misplaced.")

    # 6. Wiring (15 pts)
    polylines = dxf_analysis.get("polylines_found", 0)
    if polylines >= 2:
        score += 15
        feedback.append("Wiring runs found.")
    elif polylines == 1:
        score += 7
        feedback.append("Partial wiring found.")
    else:
        feedback.append("No wiring polylines found on correct layer.")

    # 7. Text Labels (15 pts)
    # Expecting: SD-1, SD-2, SD-3, SD-4, FACP
    found_texts = dxf_analysis.get("text_found", [])
    expected_labels = ["SD-1", "SD-2", "SD-3", "SD-4", "FACP"]
    labels_matched = 0
    
    # Normalize for comparison
    found_normalized = [t.upper().strip() for t in found_texts]
    
    for label in expected_labels:
        if any(label in t for t in found_normalized):
            labels_matched += 1
            
    score += labels_matched * 3
    feedback.append(f"Found {labels_matched}/5 correct labels.")

    # ---------------------------------------------------------
    # FINAL EVALUATION
    # ---------------------------------------------------------
    passed = score >= 60 and circles_found >= 2 and dev_layer and wire_layer
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }