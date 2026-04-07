#!/usr/bin/env python3
"""
Verifier for cryogenic_asphyxiant_gas_reporting task.

Scoring System (Total 100 points, Pass Threshold: 70):
- File Creation (10 pts): university_gases.t2s created during task.
- Nitrogen Record Exists (10 pts): CAS 7727-37-9 found.
- Nitrogen State & Hazards (15 pts): Liquid, Gas under pressure, Simple Asphyxiant.
- Nitrogen Storage Config (15 pts): Cryogenic tank, Cryogenic conditions.
- Argon Record Exists (10 pts): CAS 7440-37-1 found.
- Argon State & Hazards (15 pts): Gas, Gas under pressure, Simple Asphyxiant.
- Argon Storage Config (15 pts): Cylinder, Ambient temperature.
- Clean Configuration (10 pts): No extraneous hazards (e.g., Flammable) on these inert gases.
"""

import os
import json
import tempfile
import zipfile
import re
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to load VLM trajectory utilities for anti-gaming verification
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False


def verify_cryogenic_asphyxiant_gas_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', "C:\\Users\\Docker\\Desktop\\export_result.json")
    output_t2s = metadata.get('output_file', "C:\\Users\\Docker\\Documents\\university_gases.t2s")
    
    score = 0
    feedback_parts = []
    
    # 1. Copy JSON Result
    res_tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, res_tmp.name)
        with open(res_tmp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(res_tmp.name):
            os.unlink(res_tmp.name)

    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "university_gases.t2s not found. Task not completed."
        }

    # Base points for creating the file properly during the task
    if result.get("file_created_during_task", False):
        score += 10
        feedback_parts.append("File created during task (+10)")
    else:
        # Give partial credit if it exists but timestamps are off
        score += 5
        feedback_parts.append("File exists but creation timestamp check failed (+5)")

    # 2. Copy the actual T2S file to parse its internal XML
    t2s_tmp = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    try:
        copy_from_env(output_t2s, t2s_tmp.name)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to copy T2S file: {e}"}

    xml_content = ""
    try:
        with zipfile.ZipFile(t2s_tmp.name, 'r') as z:
            for fname in z.namelist():
                if fname.endswith('.xml'):
                    xml_content = z.read(fname).decode('utf-8', errors='ignore')
                    break
    except Exception as e:
        os.unlink(t2s_tmp.name)
        return {"passed": False, "score": score, "feedback": f"Failed to unzip T2S file (Invalid ZIP): {e}"}
    finally:
        if os.path.exists(t2s_tmp.name):
            os.unlink(t2s_tmp.name)

    if not xml_content:
        feedback_parts.append("No valid XML data found in T2S ZIP archive")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 3. Extract Chemical Data
    # Strip namespaces for robust parsing
    import io
    it = ET.iterparse(io.StringIO(xml_content))
    for _, el in it:
        _, _, el.tag = el.tag.rpartition('}')
    root = it.root

    n2_str = ""
    ar_str = ""
    
    # Try finding independent Chemical nodes first
    for tag in ['Chemical', 'InventoryItem', 'ChemInventory', 'ChemicalInventory', 'FacilityChemical']:
        for chem in root.iter(tag):
            content = ET.tostring(chem, encoding='unicode').lower()
            # Ensure the block is reasonably sized (not the entire root document)
            if '7727-37-9' in content and len(content) < 8000:
                n2_str = content
            if '7440-37-1' in content and len(content) < 8000:
                ar_str = content

    # Regex fallback if ElementTree hierarchy mapping fails
    if not n2_str:
        match = re.search(r'<([a-zA-Z0-9_-]+)[^>]*>.*?7727-37-9.*?</\1>', xml_content, re.IGNORECASE | re.DOTALL)
        if match and len(match.group(0)) < 8000:
            n2_str = match.group(0).lower()
            
    if not ar_str:
        match = re.search(r'<([a-zA-Z0-9_-]+)[^>]*>.*?7440-37-1.*?</\1>', xml_content, re.IGNORECASE | re.DOTALL)
        if match and len(match.group(0)) < 8000:
            ar_str = match.group(0).lower()

    # 4. Verification Logic
    has_asphyx_n2 = False
    has_asphyx_ar = False

    # A) Nitrogen (CAS 7727-37-9)
    if n2_str:
        score += 10
        feedback_parts.append("Nitrogen record exists (+10)")
        
        has_liquid = 'liquid' in n2_str
        has_pressure = 'gas under pressure' in n2_str or 'compressed' in n2_str
        has_asphyx_n2 = 'simple asphyxiant' in n2_str or 'asphyxiant' in n2_str
        
        if has_liquid and has_pressure and has_asphyx_n2:
            score += 15
            feedback_parts.append("Nitrogen state and hazards correct (+15)")
        else:
            feedback_parts.append(f"Nitrogen config incomplete (Liquid:{has_liquid}, Pressure:{has_pressure}, Asphyx:{has_asphyx_n2})")
            
        has_cryo_tank = 'cryogenic tank' in n2_str
        has_cryo_cond = 'cryogenic condition' in n2_str or 'cryogenic' in n2_str
        
        if has_cryo_tank and has_cryo_cond:
            score += 15
            feedback_parts.append("Nitrogen storage correct (+15)")
        else:
            feedback_parts.append("Nitrogen storage incorrect or missing")
    else:
        feedback_parts.append("Nitrogen (7727-37-9) record NOT found")

    # B) Argon (CAS 7440-37-1)
    if ar_str:
        score += 10
        feedback_parts.append("Argon record exists (+10)")
        
        has_gas = 'gas' in ar_str and not ('liquid' in ar_str and not 'gas under pressure' in ar_str)
        has_pressure = 'gas under pressure' in ar_str or 'compressed' in ar_str
        has_asphyx_ar = 'simple asphyxiant' in ar_str or 'asphyxiant' in ar_str
        
        if has_gas and has_pressure and has_asphyx_ar:
            score += 15
            feedback_parts.append("Argon state and hazards correct (+15)")
        else:
            feedback_parts.append(f"Argon config incomplete (Gas:{has_gas}, Pressure:{has_pressure}, Asphyx:{has_asphyx_ar})")
            
        has_cylinder = 'cylinder' in ar_str
        has_ambient = 'ambient' in ar_str
        
        if has_cylinder and has_ambient:
            score += 15
            feedback_parts.append("Argon storage correct (+15)")
        else:
            feedback_parts.append("Argon storage incorrect or missing")
    else:
        feedback_parts.append("Argon (7440-37-1) record NOT found")

    # C) Clean Configuration (Anti-gaming / precision check)
    clean_config = True
    extraneous = []
    
    if n2_str and ('flammable' in n2_str or 'toxic' in n2_str):
        clean_config = False
        extraneous.append("Nitrogen")
    if ar_str and ('flammable' in ar_str or 'toxic' in ar_str):
        clean_config = False
        extraneous.append("Argon")
        
    if clean_config and (n2_str or ar_str):
        score += 10
        feedback_parts.append("No extraneous hazards found (+10)")
    elif not clean_config:
        feedback_parts.append(f"Extraneous hazards (Flammable/Toxic) found on: {', '.join(extraneous)}")

    # 5. VLM Trajectory Verification (Optional / Anti-gaming enhancement)
    vlm_feedback = ""
    if VLM_AVAILABLE and traj:
        frames = sample_trajectory_frames(traj, n=3)
        if frames:
            prompt = (
                "You are auditing an agent performing a chemical inventory task in EPA Tier2 Submit. "
                "Look at these screenshots. Can you confirm the agent was interacting with the Tier2 Submit application, "
                "and specifically navigating chemical entry screens with hazard checkboxes (like 'Simple Asphyxiant')? "
                "Respond in JSON format: {\"app_interaction_confirmed\": true/false, \"checkboxes_seen\": true/false}"
            )
            vlm_res = query_vlm(prompt=prompt, images=frames)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("app_interaction_confirmed"):
                    vlm_feedback = " [VLM confirmed app interaction]"
                else:
                    vlm_feedback = " [WARNING: VLM could not confirm Tier2 Submit interaction]"

    # Final Evaluation
    key_criteria_met = bool(n2_str and ar_str and has_asphyx_n2 and has_asphyx_ar)
    passed = score >= metadata.get('pass_threshold', 70) and key_criteria_met

    feedback_string = " | ".join(feedback_parts) + vlm_feedback
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_string
    }