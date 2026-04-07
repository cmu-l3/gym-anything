#!/usr/bin/env python3
"""
Verifier for openvsp_vtail_butterfly_config task.

Verifies the creation of a V-tail component in a saved OpenVSP model.
Uses multi-signal verification including programmatic XML parsing and a VLM visual check.

Scoring breakdown (100 points):
- File exists, valid XML, and created after start: 15 pts
- Original components preserved (>2 Geoms): 5 pts
- VTail WingGeom component found by name: 20 pts
- Section dihedral in [25, 50] deg: 20 pts
- Total span in [2.5, 6.0] m: 10 pts
- X location > 20.0 m: 10 pts
- Root chord in [0.7, 2.0] m: 10 pts
- VLM confirmation of V-tail visibly added: 10 pts
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Verification Prompt ---
VLM_PROMPT = """You are verifying an aerospace engineering task in OpenVSP.
The user was asked to add a "V-tail" (butterfly tail) to the aft of the aircraft model.
A V-tail consists of two angled tail surfaces forming a 'V' shape, replacing standard horizontal and vertical stabilizers.

Look at this final screenshot of the OpenVSP workspace.
1. Is a 3D aircraft model visible?
2. Does the model have a V-tail configuration at the rear (two surfaces angled strongly upwards/outwards)?

Respond with a JSON object:
{
    "has_3d_model": true/false,
    "vtail_visible": true/false,
    "reasoning": "Brief explanation of what is visible at the tail"
}
"""

def _extract_param_value(geom_element, param_tags):
    """
    Helper to extract a numeric parameter value from an OpenVSP XML element.
    Checks multiple possible tag names (e.g. TotalSpan or Span).
    """
    if isinstance(param_tags, str):
        param_tags = [param_tags]
        
    for tag in param_tags:
        # OpenVSP params can be nested anywhere under the Geom's ParmContainer
        for elem in geom_element.iter(tag):
            val = elem.attrib.get('Value')
            if val is not None:
                try:
                    return float(val)
                except ValueError:
                    continue
    return None

def verify_openvsp_vtail_butterfly_config(traj, env_info, task_info):
    # Initialize verifier variables
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available in environment."}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', '/tmp/openvsp_vtail_result.json')
    
    # Tolerances from metadata
    span_range = metadata.get('span_range', [2.5, 6.0])
    dihedral_range = metadata.get('dihedral_range', [25.0, 50.0])
    x_loc_min = metadata.get('x_loc_min', 20.0)
    root_chord_range = metadata.get('root_chord_range', [0.7, 2.0])

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    local_tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json").name
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result file: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    # 2. Basic File Checks (15 pts)
    if not data.get('file_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file eCRM001_vtail_study.vsp3 does not exist. The model was not saved correctly."
        }
        
    mtime = data.get('file_mtime', 0)
    start_time = data.get('task_start_time', 0)
    
    if mtime < start_time:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Anti-gaming check failed: Saved file timestamp is older than task start time."
        }
        
    content = data.get('file_content', '')
    
    # 3. Parse XML
    try:
        root = ET.fromstring(content)
        score += 15
        feedback_parts.append("Valid OpenVSP XML found (+15)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"The saved .vsp3 file is corrupted or not valid XML: {e}"
        }

    # 4. Check for original components (5 pts)
    # The original eCRM-001 has multiple components (Fuselage, Wing, HTail, VTail).
    # We just want to make sure they didn't delete the whole plane to make a single wing.
    all_geoms = root.findall('.//Geom')
    if len(all_geoms) > 2:
        score += 5
        feedback_parts.append(f"Original model components preserved ({len(all_geoms)} Geoms found) (+5)")
    else:
        feedback_parts.append("WARNING: Model contains too few components. Original aircraft may have been deleted.")

    # 5. Identify the added VTail component (20 pts)
    vtail_geom = None
    for geom in all_geoms:
        if geom.attrib.get('Type') == 'Wing':
            name_elem = geom.find('Name')
            if name_elem is not None and name_elem.text and 'vtail' in name_elem.text.lower():
                vtail_geom = geom
                break
                
    if vtail_geom is not None:
        score += 20
        feedback_parts.append("New VTail Wing component found (+20)")
        
        # 6. Extract and Verify Parameters
        
        # Dihedral (20 pts)
        dihedral = _extract_param_value(vtail_geom, 'Dihedral')
        if dihedral is not None and dihedral_range[0] <= dihedral <= dihedral_range[1]:
            score += 20
            feedback_parts.append(f"Dihedral set to {dihedral} deg (+20)")
        else:
            feedback_parts.append(f"Dihedral is {dihedral} deg (Target: {dihedral_range})")

        # Span (10 pts)
        span = _extract_param_value(vtail_geom, ['TotalSpan', 'Span'])
        if span is not None and span_range[0] <= span <= span_range[1]:
            score += 10
            feedback_parts.append(f"Span set to {span} m (+10)")
        else:
            feedback_parts.append(f"Span is {span} m (Target: {span_range})")

        # X Location (10 pts)
        x_loc = _extract_param_value(vtail_geom, 'X_Rel_Location')
        if x_loc is not None and x_loc >= x_loc_min:
            score += 10
            feedback_parts.append(f"Positioned at aft fuselage, X={x_loc} (+10)")
        else:
            feedback_parts.append(f"X Location is {x_loc} (Should be >= {x_loc_min})")

        # Root Chord (10 pts)
        root_chord = _extract_param_value(vtail_geom, 'Root_Chord')
        if root_chord is not None and root_chord_range[0] <= root_chord <= root_chord_range[1]:
            score += 10
            feedback_parts.append(f"Root Chord set to {root_chord} m (+10)")
        else:
            feedback_parts.append(f"Root Chord is {root_chord} m (Target: {root_chord_range})")
            
    else:
        feedback_parts.append("No Wing component containing 'VTail' in its name was found.")

    # 7. VLM Visual Verification (10 pts)
    if query_vlm:
        from gym_anything.vlm import get_final_screenshot
        final_img = get_final_screenshot(traj)
        
        if final_img:
            try:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, image=final_img)
                if vlm_resp and vlm_resp.get('success'):
                    parsed = vlm_resp.get('parsed', {})
                    if parsed.get('vtail_visible', False):
                        score += 10
                        feedback_parts.append("VLM visual check: V-tail clearly visible (+10)")
                    else:
                        feedback_parts.append(f"VLM visual check failed: {parsed.get('reasoning', 'No V-tail seen')}")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
    
    passed = score >= 60 and vtail_geom is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }