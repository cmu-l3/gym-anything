#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_annotate_model_dimensions(traj, env_info, task_info):
    """
    Verify the annotation task by checking the exported JSON analysis.
    The analysis contains data extracted directly from FreeCAD files.
    """
    # 1. Setup & Read Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function missing"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Parse Basic Criteria
    score = 0
    feedback = []
    
    file_exists = result.get("file_exists", False)
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output file T8_annotated.FCStd not found."}
    
    score += 10
    feedback.append("File created (+10)")

    analysis = result.get("analysis", {})
    if not analysis.get("valid_doc", False):
        return {
            "passed": False, 
            "score": score, 
            "feedback": f"File exists but is not a valid FreeCAD document. Error: {analysis.get('error')}"
        }

    # 3. Analyze Ground Truth (Solid Geometry)
    bbox = analysis.get("solid_bbox", {})
    if not bbox:
        return {"passed": False, "score": score, "feedback": "Could not identify solid geometry in file."}
    
    # T8 Housing Bracket approx dimensions (tolerance +/- 2mm)
    # XLength is typically the long base (~60-100mm depending on model)
    # YLength is width
    # ZLength is height
    gt_length = bbox.get("XLength", 0)
    gt_width = bbox.get("YLength", 0)
    gt_height = bbox.get("ZLength", 0)
    
    # Identify hole diameter roughly (common T8 housing is ~30-40mm tall with a hole)
    # We will accept a dimension that matches reasonable hole sizes:
    # 8mm (screw), 10mm, 12mm, 16mm, 22mm (bearing)
    valid_hole_diameters = [8, 10, 12, 16, 22, 19, 20] 

    # 4. Analyze Dimensions
    dimensions = analysis.get("dimensions", [])
    dim_count = len(dimensions)
    
    if dim_count >= 3:
        score += 20
        feedback.append(f"Found {dim_count} dimension objects (+20)")
    elif dim_count > 0:
        score += 10
        feedback.append(f"Found {dim_count} dimension objects (expected 3) (+10)")
    else:
        feedback.append("No dimension objects found in document")
    
    # 5. Check Measurements
    # We look for dimensions that match the Length, Width, and a Hole Diameter
    # We allow 1.0mm tolerance for snapping errors
    
    found_length = False
    found_width = False
    found_hole = False
    found_red = False
    
    dim_values = [d["Value"] for d in dimensions]
    
    # Check Length (X)
    for val in dim_values:
        if abs(val - gt_length) < 1.0:
            found_length = True
            break
            
    # Check Width (Y) - Only if not used for length (unless square)
    for val in dim_values:
        if abs(val - gt_width) < 1.0:
            # If square, ensure we have two dimensions of this size
            if found_length and abs(gt_length - gt_width) < 1.0:
                if dim_values.count(val) >= 2:
                    found_width = True
            else:
                found_width = True
            break
            
    # Check Hole (Radius or Diameter)
    # Draft Dimensions often report distance. 
    # For diameter, it might report diameter OR radius depending on tool usage.
    # We check both against valid sizes.
    for val in dim_values:
        # Check against list of common bearing/shaft sizes for this part
        # Also check against the measured geometry bounds (hole < width)
        if val < min(gt_width, gt_length) and val > 2.0:
            # Check specific standard sizes +/- 1mm
            for d in valid_hole_diameters:
                if abs(val - d) < 1.0 or abs(val - (d/2)) < 1.0:
                    found_hole = True
                    break
    
    if found_length:
        score += 20
        feedback.append("Correct Length dimension found (+20)")
    else:
        feedback.append(f"Missing Length dimension (Expected approx {gt_length:.1f}mm)")
        
    if found_width:
        score += 20
        feedback.append("Correct Width dimension found (+20)")
    else:
        feedback.append(f"Missing Width dimension (Expected approx {gt_width:.1f}mm)")
        
    if found_hole:
        score += 20
        feedback.append("Correct Hole dimension found (+20)")
    else:
        feedback.append("Missing Hole dimension")

    # 6. Check Color (Red)
    # FreeCAD color red is (1.0, 0.0, 0.0)
    red_count = 0
    for dim in dimensions:
        c = dim["Color"]
        # Check if R is high, G/B are low
        if c[0] > 0.8 and c[1] < 0.2 and c[2] < 0.2:
            red_count += 1
            
    if red_count >= 3:
        score += 10
        feedback.append("All dimensions are Red (+10)")
    elif red_count > 0:
        score += 5
        feedback.append(f"Some dimensions ({red_count}) are Red (+5)")
    else:
        feedback.append("Dimensions are not Red")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }