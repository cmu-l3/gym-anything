#!/usr/bin/env python3
"""
Verifier for rocket_construction_from_spec task.

Checks OpenRocket XML (.ork) for newly constructed components:
- File existence and created after task start (8 points)
- Rocket named "Phoenix" (5 points)
- Nose cone: Ogive shape, ~150mm length (15 points)
- Body tubes: >= 2 present (8 points)
- Body tube lengths: one ~120mm, one ~300mm (9 points)
- Fin set: 3 trapezoidal fins, root ~100mm, tip ~40mm, height ~65mm (17 points)
- Parachute: diameter ~610mm (10 points)
- Inner tube/Motor mount: ~25mm OD (8 points)
- Motor: Configuration present (5 points)
- Simulation: At least one uptodate simulation (15 points)

Pass threshold: 60 points
All dimensions checked with a +/- 20% tolerance to account for unit conversion rounding.
"""

import os
import json
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_float(element, tag_name, default=0.0):
    """Safely extract float values from XML elements."""
    text = element.findtext(tag_name)
    if text is None:
        return default
    try:
        return float(text)
    except (ValueError, TypeError):
        return default

def _parse_ork(local_path):
    """Parse .ork ZIP+XML and return (root_element, error_string)."""
    try:
        with zipfile.ZipFile(local_path, 'r') as z:
            xml_bytes = z.read('rocket.ork')
        root = ET.fromstring(xml_bytes.decode('utf-8'))
        return root, None
    except zipfile.BadZipFile:
        # Fallback if somehow saved as plain XML
        try:
            tree = ET.parse(local_path)
            return tree.getroot(), None
        except Exception as e:
            return None, f"Could not parse .ork as ZIP or XML: {e}"
    except Exception as e:
        return None, f"Failed to open .ork: {e}"

def verify_rocket_construction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    output_file_path = metadata.get('output_file_path', '/home/ga/Documents/rockets/phoenix_scout.ork')
    
    score = 0
    feedback_parts = []
    
    # ---- 1. Check Export Data ----
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_res.close()
    try:
        copy_from_env('/tmp/task_result.json', temp_res.name)
        with open(temp_res.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export data: {e}"}
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not export_data.get('ork_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file phoenix_scout.ork does not exist. The agent did not save the design correctly."
        }

    # Anti-gaming: Ensure file was created during the task
    task_start = export_data.get('task_start_ts', 0)
    ork_mtime = export_data.get('ork_mtime', 0)
    if ork_mtime > 0 and ork_mtime < task_start - 10:  # 10s grace period
        return {
            "passed": False,
            "score": 0,
            "feedback": "Target file was created before the task started (anti-gaming violation)."
        }
        
    score += 8
    feedback_parts.append("File saved successfully [8/8 pts]")

    # ---- 2. Parse OpenRocket File ----
    tmp_ork = tempfile.NamedTemporaryFile(delete=False, suffix='.ork')
    tmp_ork.close()
    ork_root = None
    try:
        copy_from_env(output_file_path, tmp_ork.name)
        ork_root, parse_err = _parse_ork(tmp_ork.name)
        if parse_err:
            feedback_parts.append(f"Could not parse .ork: {parse_err}")
    except Exception as e:
        feedback_parts.append(f"Could not retrieve .ork file: {e}")
    finally:
        if os.path.exists(tmp_ork.name):
            os.unlink(tmp_ork.name)

    if ork_root is None:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # ---- 3. Component Validations ----
    
    # Rocket Name (5 pts)
    rocket_name = ork_root.findtext('.//rocket/name', '').lower()
    if 'phoenix' in rocket_name:
        score += 5
        feedback_parts.append("Rocket named correctly [5/5 pts]")
    else:
        feedback_parts.append("Rocket name missing 'Phoenix' [0/5 pts]")

    # Nose Cone: length ~0.15m (15 pts)
    nose_cones = list(ork_root.iter('nosecone'))
    nc_passed = False
    for nc in nose_cones:
        shape = nc.findtext('shape', '').lower()
        length = get_float(nc, 'length')
        if 'ogive' in shape and 0.12 <= length <= 0.18:
            nc_passed = True
            break
    if nc_passed:
        score += 15
        feedback_parts.append("Nose cone configured correctly [15/15 pts]")
    else:
        feedback_parts.append("Missing/incorrect nose cone [0/15 pts]")

    # Body Tubes: >= 2, one ~120mm, one ~300mm (8 + 9 pts)
    body_tubes = list(ork_root.iter('bodytube'))
    if len(body_tubes) >= 2:
        score += 8
        feedback_parts.append("Multiple body tubes found [8/8 pts]")
    else:
        feedback_parts.append("Not enough body tubes found [0/8 pts]")

    bt_lengths = [get_float(bt, 'length') for bt in body_tubes]
    has_short = any(0.096 <= l <= 0.144 for l in bt_lengths)
    has_long = any(0.240 <= l <= 0.360 for l in bt_lengths)
    if has_short and has_long:
        score += 9
        feedback_parts.append("Body tube lengths correct [9/9 pts]")
    else:
        feedback_parts.append("Body tube lengths incorrect [0/9 pts]")

    # Fin Set: 3 fins, root~0.1m, tip~0.04m, height~0.065m (17 pts)
    fins = list(ork_root.iter('trapezoidfinset'))
    fins_passed = False
    for fin in fins:
        fc = get_float(fin, 'fincount')
        root_c = get_float(fin, 'rootchord')
        tip_c = get_float(fin, 'tipchord')
        height = get_float(fin, 'height')
        if (fc == 3 and 
            0.08 <= root_c <= 0.12 and 
            0.032 <= tip_c <= 0.048 and 
            0.052 <= height <= 0.078):
            fins_passed = True
            break
    if fins_passed:
        score += 17
        feedback_parts.append("Fins configured correctly [17/17 pts]")
    else:
        feedback_parts.append("Missing/incorrect fins [0/17 pts]")

    # Parachute: dia ~0.61m (10 pts)
    parachutes = list(ork_root.iter('parachute'))
    para_passed = False
    for para in parachutes:
        dia = get_float(para, 'diameter')
        if 0.488 <= dia <= 0.732:
            para_passed = True
            break
    if para_passed:
        score += 10
        feedback_parts.append("Parachute sized correctly [10/10 pts]")
    else:
        feedback_parts.append("Missing/incorrect parachute [0/10 pts]")

    # Motor Mount: inner tube OD ~25mm -> radius ~12.5mm (8 pts)
    inner_tubes = list(ork_root.iter('innertube'))
    mm_passed = False
    for it in inner_tubes:
        orad = get_float(it, 'outerradius')
        if 0.010 <= orad <= 0.015:  # radius between 10mm and 15mm
            mm_passed = True
            break
    if mm_passed:
        score += 8
        feedback_parts.append("Motor mount tube found [8/8 pts]")
    else:
        feedback_parts.append("Missing/incorrect motor mount tube [0/8 pts]")

    # Motor Configuration (5 pts)
    motors = list(ork_root.iter('motor'))
    if len(motors) > 0:
        score += 5
        feedback_parts.append("Motor configuration found [5/5 pts]")
    else:
        feedback_parts.append("No motor configured [0/5 pts]")

    # Simulation uptodate (15 pts)
    sims = ork_root.find('simulations')
    uptodate_found = False
    if sims is not None:
        for sim in sims.findall('simulation'):
            if sim.get('status') == 'uptodate':
                uptodate_found = True
                break
    if uptodate_found:
        score += 15
        feedback_parts.append("Simulation run successfully [15/15 pts]")
    else:
        feedback_parts.append("No successful simulations found [0/15 pts]")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }