#!/usr/bin/env python3
import json
import os
import sys
import tempfile
import math

def verify_parametric_plate(traj, env_info, task_info):
    """
    Verify the parametric mounting plate task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expectations
    expected_aliases = task_info.get('metadata', {}).get('aliases', {
        "plate_width": 80.0,
        "plate_height": 50.0,
        "plate_thickness": 3.0,
        "hole_diameter": 4.0,
        "hole_edge_offset": 6.0,
        "corner_fillet": 3.0
    })
    
    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. File Existence & Validity (10 pts)
    if result.get("file_exists") and result.get("is_new_file"):
        score += 10
        feedback_parts.append("File created successfully.")
    elif result.get("file_exists"):
        score += 5
        feedback_parts.append("File exists but timestamp issue (modified old file?).")
    else:
        return {"passed": False, "score": 0, "feedback": "No output file found."}

    inspection = result.get("inspection", {})
    if not inspection.get("doc_open_success"):
        return {"passed": False, "score": score, "feedback": "File could not be opened by FreeCAD (corrupt?)."}

    # 2. Spreadsheet & Aliases (30 pts)
    if inspection.get("spreadsheet_found"):
        score += 10
        feedback_parts.append("Spreadsheet object found.")
        
        found_aliases = inspection.get("aliases_found", {})
        correct_aliases = 0
        for name, expected_val in expected_aliases.items():
            val = found_aliases.get(name)
            if val is not None and math.isclose(val, expected_val, abs_tol=0.1):
                correct_aliases += 1
        
        # 3 points per correct alias approx, up to 20
        alias_points = min(20, int(correct_aliases * (20/6)))
        score += alias_points
        feedback_parts.append(f"{correct_aliases}/6 aliases correct.")
    else:
        feedback_parts.append("No Spreadsheet found.")

    # 3. Geometric Features (20 pts)
    features_found = []
    if inspection.get("pad_found"): features_found.append("Pad")
    if inspection.get("pocket_or_hole_found"): features_found.append("Hole")
    if inspection.get("fillet_found"): features_found.append("Fillet")
    
    score += len(features_found) * 5  # Up to 15
    if inspection.get("body_found"):
        score += 5
        feedback_parts.append(f"Features found: {', '.join(features_found)}.")
    else:
        feedback_parts.append("No PartDesign Body found.")

    # 4. Geometric Accuracy (20 pts)
    # Check volume
    vol = inspection.get("volume", 0)
    # Approx volume: (80*50*3) - (4 * pi * 2^2 * 3) - corners...
    # Box: 12000. Holes: 4 * 37.7 = 150. Fillets remove material.
    # Expected range roughly 11500 - 12100
    if 11000 <= vol <= 12500:
        score += 10
        feedback_parts.append("Volume is correct.")
    elif vol > 0:
        feedback_parts.append(f"Volume {vol:.1f} out of expected range.")
    
    # Check Dimensions (Bounding Box)
    bbox = inspection.get("bbox", [])
    if bbox:
        # Sort dimensions to handle rotation
        dims = sorted(bbox)
        # Expect roughly 3, 50, 80
        if (math.isclose(dims[0], 3.0, abs_tol=1.0) and 
            math.isclose(dims[1], 50.0, abs_tol=2.0) and 
            math.isclose(dims[2], 80.0, abs_tol=2.0)):
            score += 10
            feedback_parts.append("Dimensions are correct.")
        else:
            feedback_parts.append(f"Dimensions incorrect: {dims}")

    # 5. Parametric Binding (20 pts)
    # This is the core of the task
    refs = inspection.get("spreadsheet_references", 0)
    if refs >= 4:
        score += 20
        feedback_parts.append("Strong parametric linking detected.")
    elif refs >= 1:
        score += 10
        feedback_parts.append("Some parametric linking detected.")
    else:
        feedback_parts.append("No parametric links to spreadsheet found.")

    passed = score >= 60 and inspection.get("spreadsheet_found") and inspection.get("pad_found")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }