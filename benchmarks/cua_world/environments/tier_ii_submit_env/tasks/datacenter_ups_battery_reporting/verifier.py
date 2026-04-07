#!/usr/bin/env python3
"""
Verifier for datacenter_ups_battery_reporting task.
"""

import json
import os
import tempfile
import base64
import re
import xml.etree.ElementTree as ET

def verify_datacenter_ups_battery_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\tmp\\task_result.json")
    pass_threshold = metadata.get("pass_threshold", 75)

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    file_exists = result.get("file_exists", False)
    xml_base64 = result.get("xml_base64", "")

    score = 0
    feedback_parts = []
    
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "Output file peak_datacenter_ups.t2s not found."}
        
    score += 10
    feedback_parts.append("File created (+10)")
    
    if not xml_base64:
        return {"passed": False, "score": score, "feedback": "File found but no XML could be extracted."}
        
    try:
        xml_content = base64.b64decode(xml_base64).decode('utf-8')
        # Remove namespace for easier un-prefixed parsing
        xml_content = re.sub(r'\sxmlns="[^"]+"', '', xml_content, count=1)
        root = ET.fromstring(xml_content)
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to parse EPA XML schema: {e}"}

    # Find Sulfuric Acid Entry
    sulfuric_acid = None
    for chem in root.findall(".//Chemical"):
        cas_node = chem.find(".//CAS")
        if cas_node is not None and "7664-93-9" in cas_node.text:
            sulfuric_acid = chem
            break
            
    if sulfuric_acid is None:
        feedback_parts.append("Sulfuric Acid (CAS 7664-93-9) not found in submission")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    score += 10
    feedback_parts.append("Sulfuric Acid found (+10)")
    
    # Cast entire node string to lower for safe, namespace-agnostic checking of fields
    xml_str_lower = ET.tostring(sulfuric_acid, encoding='unicode').lower()
    
    # EHS Flag
    ehs_node = sulfuric_acid.find(".//EHS")
    if ehs_node is not None and str(ehs_node.text).lower() in ["true", "1", "yes"]:
        score += 10
        feedback_parts.append("EHS correctly checked (+10)")
    else:
        feedback_parts.append("EHS not checked")
        
    # Exact Amounts
    amount_correct = False
    if "2500" in xml_str_lower and "365" in xml_str_lower:
        score += 25
        feedback_parts.append("Exact amounts (2500 lbs) and days on site (365) found (+25)")
        amount_correct = True
    else:
        feedback_parts.append("Exact quantities missing or incorrect (Range Codes used instead?)")
        
    # Hazards Verification
    hazards_correct = 0
    if "corrosive to metal" in xml_str_lower:
        hazards_correct += 1
    if "skin corrosion" in xml_str_lower or "irritation" in xml_str_lower:
        hazards_correct += 1
    if "serious eye damage" in xml_str_lower or "eye irritation" in xml_str_lower:
        hazards_correct += 1
        
    if hazards_correct >= 3:
        score += 20
        feedback_parts.append("Hazards fully correct (+20)")
    else:
        score += (hazards_correct * 5)
        feedback_parts.append(f"Hazards partially correct (+{hazards_correct * 5})")
        
    # Storage Details Verification
    storage_correct = 0
    if "battery" in xml_str_lower:
        storage_correct += 1
    if "ambient pressure" in xml_str_lower:
        storage_correct += 1
    if "ambient temperature" in xml_str_lower:
        storage_correct += 1
    if "ups room b" in xml_str_lower:
        storage_correct += 1
        
    if storage_correct >= 4:
        score += 25
        feedback_parts.append("Storage configuration fully correct (+25)")
    else:
        score += (storage_correct * 5)
        feedback_parts.append(f"Storage details partially correct (+{storage_correct * 5})")

    passed = score >= pass_threshold and amount_correct
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }