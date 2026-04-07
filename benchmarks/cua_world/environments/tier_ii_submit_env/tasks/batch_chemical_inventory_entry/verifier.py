#!/usr/bin/env python3
"""
Verifier for Batch Chemical Inventory Entry task.

Verification Strategy:
Parses the extracted XML payload from the agent's exported .t2s file.
Performs programmatic validation on:
- File existence and timestamps (anti-gaming)
- Chemical CAS numbers
- EHS flags
- Max/Ave quantity range codes
- Days on site
- Physical & Health Hazards
- Storage locations (Types, Temp, Pressure)
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_tag_val(xml_str, tag_pattern):
    """Helper to extract inner text of a specific XML tag using regex."""
    m = re.search(f'<{tag_pattern}[^>]*>(.*?)</', xml_str, re.IGNORECASE | re.DOTALL)
    return m.group(1).strip() if m else ""

def check_chemical(xml_str, label, expected_cas, expected_ehs, expected_max, expected_ave, expected_hazards, expected_storage_keywords):
    """Evaluate a single chemical entry."""
    points = 0
    fb = []

    # Clean XML: remove namespaces for simpler regex searches
    clean_xml = re.sub(r'xmlns(:\w+)?="[^"]+"', '', xml_str)
    xml_lower = clean_xml.lower()

    # 1. CAS Check (5 pts)
    cas_val = get_tag_val(clean_xml, r'(?:CAS|CASNumber)')
    if expected_cas in cas_val or expected_cas in xml_lower:
        points += 5
        fb.append(f"PASS: {label} (CAS {expected_cas}) found (+5)")
    else:
        fb.append(f"FAIL: {label} (CAS {expected_cas}) missing")
        return points, fb  # Return early if it's the wrong chemical

    # 2. EHS Flag Check (5 pts)
    ehs_val = get_tag_val(clean_xml, r'(?:EHS|EHSIndicator)')
    is_ehs = ehs_val.lower() in ['true', '1', 'y', 'yes']
    if is_ehs == expected_ehs:
        points += 5
        fb.append(f"PASS: {label} EHS flag correct (+5)")
    else:
        fb.append(f"FAIL: {label} EHS flag incorrect (Expected {expected_ehs}, got {is_ehs})")

    # 3. Quantities Check (5 pts total: 2.5 max, 2.5 ave)
    max_val = get_tag_val(clean_xml, r'Max(?:Daily)?Amount(?:Code)?')
    ave_val = get_tag_val(clean_xml, r'Average(?:Daily)?Amount(?:Code)?')
    
    if expected_max in max_val:
        points += 2.5
    else:
        fb.append(f"FAIL: {label} Max amount incorrect (Expected {expected_max}, got {max_val})")
        
    if expected_ave in ave_val:
        points += 2.5
        fb.append(f"PASS: {label} Amounts correct (+5)")
    else:
        fb.append(f"FAIL: {label} Ave amount incorrect (Expected {expected_ave}, got {ave_val})")

    # 4. Hazards Check (5 pts)
    hazards_ok = True
    missing_hazards = []
    for haz in expected_hazards:
        # Just check if the hazard keyword exists in the chemical block
        if haz.lower() not in xml_lower:
            hazards_ok = False
            missing_hazards.append(haz)
            
    if hazards_ok:
        points += 5
        fb.append(f"PASS: {label} hazards match specifications (+5)")
    else:
        fb.append(f"FAIL: {label} missing hazards: {', '.join(missing_hazards)}")

    # 5. Storage Location Check (5 pts)
    storage_ok = True
    missing_storage = []
    for st in expected_storage_keywords:
        if st.lower() not in xml_lower:
            storage_ok = False
            missing_storage.append(st)
            
    if storage_ok:
        points += 5
        fb.append(f"PASS: {label} storage configuration correct (+5)")
    else:
        fb.append(f"FAIL: {label} missing storage configuration: {', '.join(missing_storage)}")

    return points, fb


def verify_batch_chemical_entry(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\batch_chemical_entry_result.json")
    pass_threshold = metadata.get("pass_threshold", 60)

    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read/parse result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # Base checks
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Task not completed."}
        
    if not result.get("file_created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file predates task start (Anti-gaming triggered)."}

    chemicals_xml = result.get("chemicals_xml", [])
    if not chemicals_xml:
        return {"passed": False, "score": 0, "feedback": "No chemical records found in exported file."}

    score = 10 # Base points for exporting a valid file with chemicals during the task
    feedback_parts = ["PASS: Valid new submission file exported (+10)"]
    
    # Days on site check (All should be 365)
    all_365 = True
    for xml_str in chemicals_xml:
        days = get_tag_val(xml_str, r'DaysOnSite')
        if days != "365":
            all_365 = False
    
    if all_365 and len(chemicals_xml) >= 3:
        score += 15
        feedback_parts.append("PASS: All chemicals have 365 days on-site (+15)")
    else:
        feedback_parts.append("FAIL: Not all chemicals have 365 days on-site, or too few chemicals.")

    # Target chemical configurations
    expected_chemicals = [
        {
            "label": "Chlorine",
            "cas": "7782-50-5",
            "ehs": True,
            "max": "05", "ave": "04",
            "hazards": ["gas under pressure", "oxidizer", "acute toxicity", "eye damage"],
            "storage": ["cylinder", "above ambient"]
        },
        {
            "label": "Sulfuric Acid",
            "cas": "7664-93-9",
            "ehs": True,
            "max": "06", "ave": "05",
            "hazards": ["corrosive to metals", "acute toxicity", "skin", "eye"],
            "storage": ["tank", "ambient"]
        },
        {
            "label": "Sodium Hypochlorite",
            "cas": "7681-52-9",
            "ehs": False,
            "max": "05", "ave": "04",
            "hazards": ["oxidizer", "corrosive to metals", "acute toxicity", "skin", "eye"],
            "storage": ["tank", "ambient"]
        }
    ]

    # Evaluate each target against all exported chemicals (find best match)
    for target in expected_chemicals:
        best_points = 0
        best_fb = [f"FAIL: {target['label']} not found"]
        
        for xml_str in chemicals_xml:
            pts, fb = check_chemical(
                xml_str, target["label"], target["cas"], target["ehs"], 
                target["max"], target["ave"], target["hazards"], target["storage"]
            )
            if pts > best_points:
                best_points = pts
                best_fb = fb
                
        score += best_points
        feedback_parts.extend(best_fb)

    # Penalize for duplicate or junk entries
    unique_cas = set()
    for xml_str in chemicals_xml:
        cas = get_tag_val(xml_str, r'(?:CAS|CASNumber)')
        if cas: unique_cas.add(cas)
        
    if len(unique_cas) > 3 or len(chemicals_xml) > len(unique_cas):
        score = max(0, score - 15)
        feedback_parts.append("PENALTY: Duplicate or extra unrequested chemicals found (-15)")

    passed = score >= pass_threshold
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }