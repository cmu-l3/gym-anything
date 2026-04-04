#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_parametric_standoff(traj, env_info, task_info):
    """
    Verifies the FreeCAD parametric standoff task.
    
    Critera:
    1. File exists and is valid FCStd (8 pts)
    2. Spreadsheet exists (10 pts)
    3. Correct Aliases (12 pts)
    4. Correct Values (10 pts)
    5. Part Design Body geometry exists (8 pts)
    6. Parametric Expressions used (20-27 pts)
    7. Geometric Dimensions correct (15 pts)
    8. Through-hole feature (10 pts)
    """
    
    # 1. Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 2. Retrieve result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Parse Internal Analysis
    internal = result.get("internal_analysis", {})
    
    score = 0
    feedback = []
    
    # Criterion 1: File Existence (8 pts)
    if result.get("file_exists") and result.get("file_created_during_task"):
        score += 8
        feedback.append("File created successfully.")
    elif result.get("file_exists"):
        score += 4
        feedback.append("File exists but timestamp verification failed.")
    else:
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    if internal.get("valid_doc"):
        # Criterion 2: Spreadsheet (10 pts)
        if internal.get("spreadsheet_found"):
            score += 10
            feedback.append("Spreadsheet object found.")
        else:
            feedback.append("No Spreadsheet found.")

        # Criterion 3: Aliases (12 pts)
        aliases_found = internal.get("aliases_found", [])
        required_aliases = ["outer_diameter", "inner_diameter", "height", "flange_diameter", "flange_height"]
        found_count = len(set(aliases_found) & set(required_aliases))
        if found_count == 5:
            score += 12
            feedback.append("All 5 aliases found.")
        else:
            score += int((found_count / 5) * 12)
            feedback.append(f"Found {found_count}/5 aliases.")

        # Criterion 4: Values (10 pts)
        aliases_correct = internal.get("aliases_correct", [])
        correct_count = len(set(aliases_correct) & set(required_aliases))
        if correct_count == 5:
            score += 10
            feedback.append("All parameter values correct.")
        else:
            score += int((correct_count / 5) * 10)
            feedback.append(f"Found {correct_count}/5 correct values.")

        # Criterion 5: Body Geometry (8 pts)
        if internal.get("body_found"):
            score += 8
            feedback.append("PartDesign Body found.")
        else:
            feedback.append("No Body geometry found.")

        # Criterion 6: Expressions (27 pts max)
        expr_count = internal.get("expression_count", 0)
        if expr_count >= 5:
            score += 27
            feedback.append(f"Excellent parametric linking ({expr_count} expressions).")
        elif expr_count >= 3:
            score += 20
            feedback.append(f"Good parametric linking ({expr_count} expressions).")
        elif expr_count >= 1:
            score += 10
            feedback.append("Minimal parametric linking (only 1-2 expressions).")
        else:
            feedback.append("No expressions found (dimensions likely hardcoded).")

        # Criterion 7: Geometric Dimensions (15 pts)
        # Height ~ 11.5mm (10 post + 1.5 flange)
        h = internal.get("bbox_height", 0)
        max_d = internal.get("bbox_max_dim", 0)
        
        dims_ok = 0
        if 10.5 <= h <= 12.5:
            dims_ok += 1
            feedback.append(f"Height correct ({h:.2f}mm).")
        else:
            feedback.append(f"Height incorrect ({h:.2f}mm).")
            
        if 11.0 <= max_d <= 13.0:
            dims_ok += 1
            feedback.append(f"Diameter correct ({max_d:.2f}mm).")
        else:
            feedback.append(f"Diameter incorrect ({max_d:.2f}mm).")
            
        if dims_ok == 2:
            score += 15
        elif dims_ok == 1:
            score += 7

        # Criterion 8: Through Hole (10 pts)
        if internal.get("has_through_hole"):
            score += 10
            feedback.append("Through-hole detected.")
        else:
            feedback.append("No through-hole detected.")

    else:
        feedback.append("File is not a valid FreeCAD document.")

    # Pass Threshold
    # Must have Spreadsheet AND Expressions >= 3 to pass (proving parametric workflow)
    passed = score >= 55 and internal.get("spreadsheet_found") and internal.get("expression_count", 0) >= 3

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }