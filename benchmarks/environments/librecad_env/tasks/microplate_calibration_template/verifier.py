#!/usr/bin/env python3
import json
import os
import tempfile
import math
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_microplate_template(traj, env_info, task_info):
    """
    Verifies the Microplate Calibration Template task.
    
    Criteria:
    1. File exists and valid DXF (10 pts)
    2. Correct Layers created (15 pts)
    3. Outline dimensions correct (15 pts)
    4. Well count correct (20 pts)
    5. A1 Position correct (10 pts)
    6. Array/Pitch correct (checked via H12 position) (20 pts)
    7. Well Diameter correct (5 pts)
    8. Labels present (5 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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

    # Parsing analysis from container
    dxf = result.get("dxf_analysis", {})
    if not dxf.get("valid_dxf"):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "DXF file not found or invalid. Make sure to save as /home/ga/Documents/LibreCAD/microplate_template.dxf"
        }

    score = 0
    feedback = []
    
    # 1. File Validity (10 pts)
    if result.get("file_created_during_task") and dxf.get("valid_dxf"):
        score += 10
        feedback.append("File created and valid")
    
    # 2. Layers (15 pts)
    layers = dxf.get("layers", {})
    required_layers = {"OUTLINE", "WELLS", "LABELS"}
    found_layers = set(layers.keys())
    # Case insensitive check
    found_upper = {l.upper() for l in found_layers}
    
    if required_layers.issubset(found_upper):
        score += 15
        feedback.append("All required layers found")
    else:
        missing = required_layers - found_upper
        feedback.append(f"Missing layers: {missing}")

    # 3. Outline (15 pts)
    outline = dxf.get("outline_analysis", {})
    width = outline.get("width", 0)
    height = outline.get("height", 0)
    # Expected: 127.76 x 85.48
    if abs(width - 127.76) < 0.5 and abs(height - 85.48) < 0.5:
        score += 15
        feedback.append("Plate outline dimensions correct")
    elif width > 0:
        score += 5
        feedback.append(f"Outline dimensions incorrect (got {width:.1f}x{height:.1f})")
    else:
        feedback.append("No outline found")

    # 4. Well Count (20 pts)
    wells = dxf.get("wells_analysis", {})
    count = wells.get("count", 0)
    if count == 96:
        score += 20
        feedback.append("Correct well count (96)")
    elif count > 0:
        score += 5
        feedback.append(f"Incorrect well count ({count})")
    else:
        feedback.append("No wells found")

    # 5. A1 Position (10 pts)
    # Expected: (14.38, -11.24)
    # Note: LibreCAD users might use positive Y going up, so Y could be 11.24 depending on origin placement
    # But instruction said (0,0) is Top-Left and extend to Y=-85.48.
    a1 = wells.get("a1_center")
    if a1:
        x, y = a1
        if abs(x - 14.38) < 0.2 and abs(y - (-11.24)) < 0.2:
            score += 10
            feedback.append("A1 position correct")
        else:
            feedback.append(f"A1 position incorrect (got {x:.2f}, {y:.2f})")

    # 6. Array/Pitch Check via H12 (20 pts)
    # H12 Expected: X = 14.38 + 11*9 = 113.38
    #               Y = -11.24 - 7*9 = -74.24
    h12 = wells.get("h12_center")
    if h12:
        x, y = h12
        if abs(x - 113.38) < 0.5 and abs(y - (-74.24)) < 0.5:
            score += 20
            feedback.append("Grid array/pitch correct")
        else:
            feedback.append(f"Grid endpoint (H12) incorrect (got {x:.2f}, {y:.2f})")

    # 7. Well Diameter (5 pts)
    # Radius 3.25
    radius = wells.get("avg_radius", 0)
    if abs(radius - 3.25) < 0.1:
        score += 5
        feedback.append("Well diameter correct")
    
    # 8. Labels (5 pts)
    label_count = dxf.get("entity_counts", {}).get("LABELS", 0)
    if label_count >= 4:
        score += 5
        feedback.append("Labels present")
    
    passed = score >= 60 and count == 96
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }