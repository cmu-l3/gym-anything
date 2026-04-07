#!/usr/bin/env python3
"""
Verifier for Aviation Fuel EHS Mixture Reporting task.

Scoring System (100 points total):
  10 pts: File Generation (anti-gaming via modification time checked)
  15 pts: Parent Chemical Flags (Mixture and EHS flags on Avgas 100LL)
  20 pts: Component CAS Numbers (all 4 components present)
  15 pts: Component Percentages (exact matches)
  15 pts: Trace EHS Flagging (Tetraethyl Lead properly flagged)
  10 pts: Hazard Selection (Flammable, Carcinogenicity, Acute toxicity)
  15 pts: Storage Location Configuration

Pass Threshold: 75 points. MUST include parent flags and trace EHS flagging.
"""

import json
import os
import re
import tempfile
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_aviation_fuel_ehs_mixture(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\aviation_fuel_result.json")
    pass_threshold = metadata.get("pass_threshold", 75)

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Export file not found or unreadable: {e}"}
    finally:
        try:
            os.unlink(tmp.name)
        except Exception:
            pass

    # Basic file creation check
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Task was not completed."}

    # Anti-gaming: Ensure file was modified after the task began
    file_time_str = result.get("file_modified_time", "")
    task_start_str = result.get("task_start_time", "")
    try:
        if file_time_str and task_start_str:
            file_time = datetime.fromisoformat(file_time_str.replace("Z", "+00:00"))
            task_start = datetime.fromisoformat(task_start_str.replace("Z", "+00:00"))
            if file_time < task_start:
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": "Output file was not modified during the task (do-nothing detected)."
                }
    except Exception as e:
        logger.warning(f"Time parsing error: {e}")

    xml_content = result.get("xml_content", "")
    if not xml_content:
        return {"passed": False, "score": 0, "feedback": "No XML content found inside the saved .t2s file."}

    score = 10
    fb = ["PASS: File exported correctly (+10)"]
    xml_lower = xml_content.lower()

    # Determine if Avgas was added
    if "avgas" not in xml_lower and "100ll" not in xml_lower:
        return {"passed": False, "score": 10, "feedback": "Avgas 100LL chemical not found in XML. Did not add the chemical."}

    parent_flags_ok = False
    trace_ehs_ok = False

    # Check Parent Chemical Flags
    if re.search(r'mixture', xml_lower) and re.search(r'ehs', xml_lower):
        score += 15
        fb.append("PASS: Parent Mixture and EHS indicators present (+15)")
        parent_flags_ok = True
    else:
        fb.append("FAIL: Parent Mixture or EHS indicators not found.")

    # Check Component CAS Numbers
    cas_list = ["540-84-1", "78-78-4", "108-88-3", "78-00-2"]
    cas_found = [cas for cas in cas_list if cas in xml_lower]
    if len(cas_found) == 4:
        score += 20
        fb.append("PASS: All 4 component CAS numbers found (+20)")
    else:
        fb.append(f"FAIL: Missing component CAS numbers: {set(cas_list) - set(cas_found)}")

    # Check Component Percentages
    pct_list = ["74.9", "15", "10", "0.1"]
    pct_found = [p for p in pct_list if p in xml_lower]
    if len(pct_found) == 4:
        score += 15
        fb.append("PASS: All 4 component weight percentages correctly recorded (+15)")
    else:
        fb.append(f"FAIL: Missing or incorrect component percentages: {set(pct_list) - set(pct_found)}")

    # Check Trace EHS Flagging (Tetraethyl Lead)
    # Using a 250-character window check to match proximity in XML elements
    match = re.search(r'78-00-2.{0,250}?(?:ehs|extremely hazardous).{0,50}?(?:true|1|yes)', xml_lower, re.DOTALL)
    match_reverse = re.search(r'(?:ehs|extremely hazardous).{0,50}?(?:true|1|yes).{0,250}?78-00-2', xml_lower, re.DOTALL)
    
    if match or match_reverse:
        score += 15
        fb.append("PASS: Tetraethyl Lead (78-00-2) specifically flagged as EHS (+15)")
        trace_ehs_ok = True
    else:
        fb.append("FAIL: Tetraethyl Lead component not specifically flagged as an EHS hazard.")

    # Check Hazard Selection
    hazards = ["flammable", "carcinogenicity", "acute toxicity"]
    hazards_found = [h for h in hazards if h in xml_lower]
    if len(hazards_found) == 3:
        score += 10
        fb.append("PASS: Required hazard categories selected (+10)")
    else:
        fb.append(f"FAIL: Missing hazard categories: {set(hazards) - set(hazards_found)}")

    # Check Storage Location
    if "underground" in xml_lower and "tank 4" in xml_lower:
        score += 15
        fb.append("PASS: Underground storage location with Tank 4 description found (+15)")
    else:
        fb.append("FAIL: Underground storage type or 'Tank 4' description missing.")

    # Evaluate final passing conditions
    # Requires minimum score + mandatory EHS rule understanding (parent flags + trace component flag)
    passed = score >= pass_threshold and parent_flags_ok and trace_ehs_ok

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }