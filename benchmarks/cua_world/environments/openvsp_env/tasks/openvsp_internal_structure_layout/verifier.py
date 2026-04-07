#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_openvsp_internal_structure_layout(traj, env_info, task_info):
    """
    Verifies that the agent successfully configured the internal structure
    of the main Wing component with appropriate front/rear spars and ribs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_spar1 = metadata.get('spar_1_loc', 0.22)
    expected_spar2 = metadata.get('spar_2_loc', 0.68)
    expected_ribs = metadata.get('rib_count', 34)
    tolerance = metadata.get('tolerance', 0.01)

    # Copy the result payload from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Verify File Creation & Anti-Gaming
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file eCRM001_structural.vsp3 not found. Agent did not save the output correctly."
        }
    
    start_time = result.get('task_start_time', 0)
    file_mtime = result.get('file_mtime', 0)

    if file_mtime < start_time:
        feedback.append("Warning: File modification time is before task start time (Gaming attempt suspected).")

    score += 20
    feedback.append("File exported successfully (+20)")

    # Parse XML Content
    content = result.get('file_content', '')
    try:
        root = ET.fromstring(content)
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"Saved file is not valid XML: {e}"
        }

    # 2. Verify Assembly Integrity (ensures original model wasn't just deleted and recreated)
    has_fuselage = False
    for comp in root.findall(".//Geom"):
        type_name = comp.find("TypeName")
        if type_name is not None and type_name.text in ["Fuselage", "Pod", "BodyOfRevolution"]:
            has_fuselage = True
            break
            
    if has_fuselage:
        score += 20
        feedback.append("Assembly integrity verified (Fuselage present) (+20)")
    else:
        feedback.append("Original assembly destroyed (Fuselage missing). Agent failed to edit the existing model properly.")

    # Locate the Main Wing component
    wing_geom = None
    for comp in root.findall(".//Geom"):
        type_name = comp.find("TypeName")
        if type_name is not None and type_name.text == "Wing":
            wing_geom = comp
            break

    if wing_geom is None:
        feedback.append("No Wing component found.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    # 3. Check Spar Definitions
    structure = wing_geom.find(".//Structure")
    spars_found = 0
    if structure is not None:
        spars = structure.findall("Spar")
        spars_found = len(spars)
    elif "Spar" in content:
        # Fallback raw count for different VSP versions
        spars_found = content.count("<Spar>")
    
    if spars_found >= 2:
        score += 20
        feedback.append(f"Found {spars_found} Spar definitions (+20)")
    else:
        feedback.append(f"Found {spars_found} Spar definitions (Expected at least 2).")

    # 4 & 5. Check Spar Locations and Rib Counts
    spar1_found = False
    spar2_found = False
    ribs_found = False

    # Extract all parameters directly associated with the Wing geometry
    for parm in wing_geom.findall(".//Parm"):
        val_str = parm.get("Value", "")
        if not val_str:
            continue
        try:
            val = float(val_str)
            
            # Check for Front Spar
            if abs(val - expected_spar1) <= tolerance:
                spar1_found = True
                
            # Check for Rear Spar
            if abs(val - expected_spar2) <= tolerance:
                spar2_found = True
                
            # Check for Rib Count (Look for value 34)
            if abs(val - expected_ribs) <= 0.01:
                name = parm.get("Name", "").lower()
                # Confirm it's likely a Rib or Number parameter
                if "rib" in name or "num" in name or "count" in name:
                    ribs_found = True
        except ValueError:
            pass

    if spar1_found and spar2_found:
        score += 20
        feedback.append("Both Spar locations (0.22, 0.68) configured correctly (+20)")
    elif spar1_found:
        score += 10
        feedback.append("Only Spar 1 location (0.22) configured correctly (+10)")
    elif spar2_found:
        score += 10
        feedback.append("Only Spar 2 location (0.68) configured correctly (+10)")
    else:
        feedback.append("Spar chordwise locations not configured correctly.")

    # Fallback rib check mapping if structure parameter naming varied
    if not ribs_found and structure is not None:
         for parm in structure.findall(".//Parm"):
             try:
                 val = float(parm.get("Value", ""))
                 if abs(val - expected_ribs) <= 0.01:
                     ribs_found = True
                     break
             except ValueError:
                 pass

    if ribs_found:
        score += 20
        feedback.append("Rib count (34) configured correctly (+20)")
    else:
        feedback.append("Rib count not configured correctly.")

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }