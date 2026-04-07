#!/usr/bin/env python3
"""
Verifier for ammonia_refrigeration_rmp_update task.

Scoring (100 pts total, pass threshold: 70):
  10 pts - Valid output file created
  15 pts - Regulatory Status: Subject to CAA 112(r) is True
  20 pts - Facility IDs: Both RMP and TRI Facility IDs entered correctly
  25 pts - Chemical Quantities: Max and Avg Daily Amounts updated (12500 and 11000)
  30 pts - Storage Locations: Second location added correctly
  -15 pts - (Penalty) Original "Engine Room 1" location was deleted
"""

import json
import os
import tempfile
import re

def verify_ammonia_refrigeration_rmp_update(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}
        
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\ammonia_task_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        os.unlink(tmp.name)
        
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file arctic_cold_storage_2025_updated.t2s not found."}
        
    if not result.get("is_valid_zip"):
        return {"passed": False, "score": 0, "feedback": "Output file is not a valid Tier2 Submit archive (not a valid ZIP)."}
        
    raw_xml = result.get("raw_xml", "")
    if not raw_xml:
        return {"passed": False, "score": 0, "feedback": "No XML content found inside the .t2s file."}
        
    score = 10
    feedback = ["Valid .t2s file created (+10)"]
    
    # 1. Subject to CAA 112(r) Check
    if re.search(r'Caa112r[^>]*>(true|yes|1)', raw_xml, re.IGNORECASE) or re.search(r'Subject to CAA 112[^>]*>(true|yes|1)', raw_xml, re.IGNORECASE):
        score += 15
        feedback.append("Subject to CAA 112(r) is True (+15)")
    else:
        feedback.append("Subject to CAA 112(r) not marked True")
        
    # 2. Facility IDs Check
    rmp_found = "1000 0012 3456" in raw_xml or "100000123456" in raw_xml
    tri_found = "99501ARCTC123CO" in raw_xml
    if rmp_found and tri_found:
        score += 20
        feedback.append("Both RMP and TRI IDs found (+20)")
    elif rmp_found or tri_found:
        score += 10
        feedback.append("Only one of RMP or TRI ID found (+10)")
    else:
        feedback.append("RMP and TRI IDs not found")
        
    # 3. Chemical Quantities Check
    max_found = "12500" in raw_xml
    avg_found = "11000" in raw_xml
    if max_found and avg_found:
        score += 25
        feedback.append("Max and Avg Daily Amounts updated (+25)")
    elif max_found or avg_found:
        score += 12
        feedback.append("Only one of Max or Avg Amount updated (+12)")
    else:
        feedback.append("Chemical quantities not updated")
        
    # 4. Storage Locations Check
    if "Engine Room 2 Receiver" in raw_xml:
        # Verify related parameters using text or code presence
        has_pressure = re.search(r'Greater than ambient pressure', raw_xml, re.IGNORECASE) or re.search(r'Greater than ambient', raw_xml, re.IGNORECASE) or "03" in raw_xml
        has_temp = re.search(r'Less than ambient temperature', raw_xml, re.IGNORECASE) or "05" in raw_xml
        
        if has_pressure and has_temp:
            score += 30
            feedback.append("New storage location added with correct details (+30)")
        else:
            score += 15
            feedback.append("New storage location description found, but pressure/temp may be incorrect (+15)")
    else:
        feedback.append("New storage location 'Engine Room 2 Receiver' not found")
        
    # Anti-gaming: Ensure original location wasn't accidentally or intentionally deleted
    if "Engine Room 1" not in raw_xml:
        score = max(0, score - 15)
        feedback.append("Original storage location was deleted (-15 penalty)")
        
    passed = score >= 70
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback)}