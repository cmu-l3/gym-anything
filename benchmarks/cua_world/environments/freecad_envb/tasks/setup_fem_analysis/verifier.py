#!/usr/bin/env python3
import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_setup_fem_analysis(traj, env_info, task_info):
    """
    Verify the FEM setup task by inspecting the saved FreeCAD file.
    
    Checks for:
    1. File existence and creation time (anti-gaming).
    2. Fem::FemAnalysis object (Analysis container).
    3. Material object referencing Steel.
    4. Fem::ConstraintFixed object.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_file = metadata.get('expected_output_file', '/home/ga/Documents/FreeCAD/T8_bracket_fem.FCStd')

    # Load task result metadata
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file T8_bracket_fem.FCStd not found."}
    
    if not task_result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file was not saved during the task execution."}

    # Inspect the FCStd file (it's a ZIP archive containing Document.xml)
    temp_fcstd = tempfile.NamedTemporaryFile(delete=False, suffix='.zip')
    try:
        copy_from_env(expected_output_file, temp_fcstd.name)
        
        has_analysis = False
        has_material = False
        is_steel = False
        has_constraint = False
        
        if zipfile.is_zipfile(temp_fcstd.name):
            with zipfile.ZipFile(temp_fcstd.name, 'r') as z:
                if 'Document.xml' in z.namelist():
                    with z.open('Document.xml') as f:
                        tree = ET.parse(f)
                        root = tree.getroot()
                        
                        # Iterate through all Objects in the document
                        for obj in root.findall(".//Object"):
                            obj_type = obj.get('type')
                            obj_name = obj.get('name')
                            
                            # Check for Analysis Container
                            if obj_type == 'Fem::FemAnalysis':
                                has_analysis = True
                            
                            # Check for Constraint
                            if obj_type == 'Fem::ConstraintFixed':
                                has_constraint = True
                                
                            # Check for Material
                            # Materials can be App::MaterialObjectPython or Fem::FemMaterial depending on version/workflow
                            if 'Material' in str(obj_type) or 'App::MaterialObjectPython' in str(obj_type):
                                # Check properties to see if it's steel
                                has_material = True
                                properties = obj.findall(".//Property")
                                for prop in properties:
                                    # Look for string value containing "Steel" in any property
                                    # Often stored in "Label" or specific material card properties
                                    for child in prop:
                                        if child.text and 'Steel' in child.text:
                                            is_steel = True
                                        # Also check encoded attributes if present
                                        if prop.get('name') == 'Material':
                                            # Sometimes material data is inside
                                            pass
    
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to inspect FreeCAD file: {e}"}
    finally:
        if os.path.exists(temp_fcstd.name):
            os.unlink(temp_fcstd.name)

    # Scoring
    score = 10 # Base for saving file
    feedback = ["File saved successfully."]

    if has_analysis:
        score += 30
        feedback.append("FEM Analysis container created.")
    else:
        feedback.append("Missing FEM Analysis container.")

    if has_constraint:
        score += 30
        feedback.append("Fixed Constraint applied.")
    else:
        feedback.append("Missing Fixed Constraint.")

    if has_material:
        score += 20
        if is_steel:
            score += 10
            feedback.append("Material 'Steel' assigned.")
        else:
            feedback.append("Material object found, but could not verify it is Steel.")
    else:
        feedback.append("Missing Material assignment.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }