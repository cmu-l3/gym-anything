#!/usr/bin/env python3
"""
Verifier for ehs_pure_chemical_classification task.

Evaluates the raw XML dumped from the agent's .t2s export.
Robust checks using ElementTree to tolerate schema namespace variations.
"""

import os
import json
import tempfile
import xml.etree.ElementTree as ET
import logging
import sys

# Configure path for VLM utilities
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '../../scripts'))
try:
    from vlm_utils import sample_trajectory_frames, query_vlm
except ImportError:
    sample_trajectory_frames = None
    query_vlm = None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH = "C:\\Users\\Docker\\Desktop\\ehs_task_result.json"


def get_active_flags(xml_str):
    """Extracts all tags that have a 'true' / 'yes' value inside the XML chunk."""
    active = []
    try:
        root = ET.fromstring(xml_str)
        for elem in root.iter():
            text = str(elem.text).strip().lower() if elem.text else ""
            if text in ['true', '1', 'y', 'yes']:
                active.append(elem.tag.lower())
    except Exception:
        pass
    return active


def get_node_texts(xml_str, target_substr):
    """Extracts text from all nodes whose tag contains the target substring."""
    texts = []
    try:
        root = ET.fromstring(xml_str)
        for elem in root.iter():
            if target_substr.lower() in elem.tag.lower() and elem.text:
                texts.append(str(elem.text).strip().lower())
    except Exception:
        pass
    return texts


def verify_ehs_classification(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", RESULT_PATH)
    pass_threshold = metadata.get("pass_threshold", 60)

    # Copy result JSON from container
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read export file: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # 1. Anti-gaming: Check if file exists and modification time
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Agent did not export."}

    mtime = result.get("file_mtime", 0)
    stime = result.get("start_time", 0)
    if mtime > 0 and stime > 0 and mtime < stime:
        return {"passed": False, "score": 0, "feedback": "Exported file is older than task start. Invalid submission."}

    chemicals = result.get("chemicals", [])
    if not chemicals:
        return {"passed": False, "score": 0, "feedback": "No chemicals found in the exported facility data."}

    # Find target chemical in the XML dumps
    target_chem = None
    target_xml = ""
    for chem in chemicals:
        xml_str = chem.get("RawXML", "")
        cas_texts = get_node_texts(xml_str, "cas")
        if any("7664-41-7" in t for t in cas_texts):
            target_chem = chem
            target_xml = xml_str
            break

    if not target_chem:
        return {"passed": False, "score": 0, "feedback": "Anhydrous Ammonia (CAS 7664-41-7) was not added to the facility."}

    score = 0
    fb = ["Chemical CAS found (+15)"]
    score += 15  # CAS / Identity Baseline

    # 2. Extract Active Flags and Texts
    active_flags = get_active_flags(target_xml)
    
    # EHS Flag Check
    ehs_texts = get_node_texts(target_xml, "ehs")
    is_ehs = any(t in ['true', '1', 'y', 'yes'] for t in ehs_texts) or any('ehs' in t for t in active_flags)
    if is_ehs:
        score += 10
        fb.append("EHS flag is True (+10)")
    else:
        fb.append("EHS flag missing/False")

    # Pure Flag Check
    pure_texts = get_node_texts(target_xml, "pure")
    is_pure = any(t in ['true', '1', 'y', 'yes'] for t in pure_texts) or any('pure' in t for t in active_flags)
    if is_pure:
        score += 5
        fb.append("Pure chemical selected (+5)")
    else:
        fb.append("Pure chemical flag missing")

    # 3. Hazard Checks
    # Physical
    if any('flammable' in t for t in active_flags): score += 5; fb.append("Hazard: Flammable (+5)")
    else: fb.append("Missing Hazard: Flammable")
    
    if any('pressure' in t for t in active_flags): score += 5; fb.append("Hazard: Gas under pressure (+5)")
    else: fb.append("Missing Hazard: Gas under pressure")
    
    if any('corrosive' in t for t in active_flags): score += 5; fb.append("Hazard: Corrosive to metal (+5)")
    else: fb.append("Missing Hazard: Corrosive to metal")

    # Health
    if any('acute' in t or 'toxicity' in t for t in active_flags): score += 5; fb.append("Hazard: Acute toxicity (+5)")
    else: fb.append("Missing Hazard: Acute toxicity")

    if any('skin' in t for t in active_flags): score += 5; fb.append("Hazard: Skin corrosion (+5)")
    else: fb.append("Missing Hazard: Skin corrosion")

    if any('eye' in t for t in active_flags): score += 5; fb.append("Hazard: Eye damage (+5)")
    else: fb.append("Missing Hazard: Eye damage")

    if any('stot' in t or 'organ' in t for t in active_flags): score += 5; fb.append("Hazard: STOT (+5)")
    else: fb.append("Missing Hazard: STOT")

    # Extraneous Hazard check (e.g., oxidizer shouldn't be checked)
    if any('oxidizer' in t for t in active_flags):
        fb.append("Extraneous Hazard: Oxidizer checked (no points awarded)")
    else:
        score += 5
        fb.append("No extraneous oxidizer hazard (+5)")

    # 4. Quantity Range Codes
    max_texts = get_node_texts(target_xml, "max")
    if any('04' in t for t in max_texts):
        score += 5
        fb.append("Max amount code 04 (+5)")
    else:
        fb.append("Max amount code incorrect")

    avg_texts = get_node_texts(target_xml, "avg") + get_node_texts(target_xml, "ave") + get_node_texts(target_xml, "average")
    if any('04' in t for t in avg_texts):
        score += 5
        fb.append("Avg amount code 04 (+5)")
    else:
        fb.append("Avg amount code incorrect")

    days_texts = get_node_texts(target_xml, "days")
    if any('365' in t for t in days_texts):
        score += 3
        fb.append("Days on site 365 (+3)")

    # 5. Storage Location
    pressure_texts = get_node_texts(target_xml, "pressure")
    if any('greater' in t for t in pressure_texts):
        score += 7
        fb.append("Storage pressure correct (+7)")
    else:
        fb.append("Storage pressure incorrect/missing")

    # 6. VLM Trajectory Verification
    if sample_trajectory_frames and query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """Analyze these trajectory frames of an agent using EPA Tier2 Submit.
Did the agent navigate to the Chemical Inventory section and interact with the physical/health hazard classification checkboxes?
Reply in JSON format: {"interacted_with_hazards": true/false}"""
            
            vlm_resp = query_vlm(prompt=prompt, images=frames)
            if vlm_resp and vlm_resp.get("parsed", {}).get("interacted_with_hazards"):
                score += 10
                fb.append("VLM Verification: Hazard interaction observed (+10)")
            else:
                fb.append("VLM Verification: No hazard interaction observed")

    # Enforce mandatory criteria for passing
    key_criteria_met = (target_chem is not None) and is_ehs
    passed = (score >= pass_threshold) and key_criteria_met

    if not key_criteria_met and score >= pass_threshold:
        fb.append("FAILED: Met points threshold but missing required CAS entry or EHS designation.")

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(fb)
    }