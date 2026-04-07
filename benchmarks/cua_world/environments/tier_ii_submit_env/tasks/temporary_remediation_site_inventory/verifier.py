#!/usr/bin/env python3
"""
Verifier for temporary_remediation_site_inventory task.

This verifier pulls the exported `.t2s` file (which is a ZIP archive), extracts the
internal `T2SData.xml`, and verifies that all specific requirements have been met.
"""

import json
import os
import tempfile
import zipfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def text_check(pattern, text):
    """Helper to do a case-insensitive regex search in XML text."""
    return bool(re.search(pattern, text, re.IGNORECASE))

def verify_temporary_remediation_site_inventory(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_json_path = metadata.get("result_file", "C:\\workspace\\site42_result.json")
    t2s_file_path = metadata.get("output_file", "C:\\workspace\\site42_update.t2s")
    pass_threshold = metadata.get("pass_threshold", 60)

    # 1. Copy JSON result
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_json_path, tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        try:
            os.unlink(tmp_json.name)
        except Exception:
            pass

    # Basic anti-gaming validations
    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Agent did not export the facility."}
    
    if not result.get("created_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Output file was modified before the task started (invalid timestamp)."}

    # 2. Copy the actual .t2s file for XML inspection
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    xml_content = ""
    try:
        copy_from_env(t2s_file_path, tmp_t2s.name)
        
        # Read the .t2s as a ZIP file
        with zipfile.ZipFile(tmp_t2s.name, 'r') as zip_ref:
            # Locate XML file (typically T2SData.xml)
            xml_files = [f for f in zip_ref.namelist() if f.lower().endswith('.xml')]
            if not xml_files:
                return {"passed": False, "score": 0, "feedback": "The exported .t2s file does not contain XML data."}
            
            with zip_ref.open(xml_files[0]) as xml_file:
                xml_content = xml_file.read().decode('utf-8', errors='ignore')
    except zipfile.BadZipFile:
        return {"passed": False, "score": 0, "feedback": "Exported file is not a valid ZIP/.t2s archive."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to extract/parse .t2s file: {e}"}
    finally:
        try:
            os.unlink(tmp_t2s.name)
        except Exception:
            pass

    score = 0
    fb = []

    # ---------------------------------------------------------
    # SCORING CRITERIA (100 Points Total)
    # ---------------------------------------------------------

    # 1. File Exported & Formatted properly (10 pts)
    if xml_content:
        score += 10
        fb.append("PASS: Exported valid Tier II XML (+10)")

    # 2. Facility Name Check (10 pts)
    if text_check(r'Site 42.*?Soil Remediation', xml_content):
        score += 10
        fb.append("PASS: Facility correctly named (+10)")
    else:
        fb.append("FAIL: Expected facility name 'Site 42 - Soil Remediation' not found")

    # 3. Location / Coordinates (15 pts)
    lat_ok = text_check(r'<[^>]*Latitude[^>]*>\s*35\.2456\s*<', xml_content)
    lon_ok = text_check(r'<[^>]*Longitude[^>]*>\s*-106\.589', xml_content)
    if lat_ok and lon_ok:
        score += 15
        fb.append("PASS: Coordinates matched exactly (+15)")
    else:
        fb.append("FAIL: Coordinates missing or incorrect (Expected Lat: 35.2456, Lon: -106.5890)")

    # 4. No Street Address flag & Unmanned (15 pts)
    # Different versions of Tier2Submit might structure these differently, so regex across tags
    nsa_ok = text_check(r'<[^>]*NoStreetAddress[^>]*>\s*(true|1|yes)\s*<', xml_content)
    manned_ok = text_check(r'<[^>]*Manned[^>]*>\s*(false|0|no)\s*<', xml_content) or text_check(r'Unmanned', xml_content)
    occ_ok = text_check(r'<[^>]*Occupants[^>]*>\s*0\s*<', xml_content)
    
    if nsa_ok and (manned_ok or occ_ok):
        score += 15
        fb.append("PASS: Marked as No Street Address / Unmanned / 0 Occupants (+15)")
    else:
        fb.append("FAIL: Missing Unmanned, 0 Occupants, or No Street Address flag")

    # 5. Chemical Identity (15 pts)
    cas_ok = text_check(r'6484-52-2', xml_content)
    chem_ok = text_check(r'Ammonium.*?Nitrate', xml_content)
    if cas_ok and chem_ok:
        score += 15
        fb.append("PASS: Chemical Ammonium Nitrate (CAS 6484-52-2) added (+15)")
    else:
        fb.append("FAIL: Chemical Ammonium Nitrate (CAS 6484-52-2) not found")

    # 6. Short-Term Storage Configuration (10 pts)
    days_ok = text_check(r'<[^>]*DaysOnSite[^>]*>\s*45\s*<', xml_content)
    if days_ok:
        score += 10
        fb.append("PASS: Days on-site successfully updated to 45 (+10)")
    else:
        fb.append("FAIL: Days on-site is incorrect (expected 45)")

    # 7. Hazard Profile (15 pts)
    ox_ok = text_check(r'Oxidizer', xml_content)
    exp_ok = text_check(r'Explosive', xml_content)
    eye_ok = text_check(r'Serious eye damage', xml_content)
    if ox_ok and exp_ok and eye_ok:
        score += 15
        fb.append("PASS: All 3 physical/health hazards verified (+15)")
    else:
        fb.append("FAIL: One or more hazard checkboxes (Oxidizer, Explosive, Eye Damage) missing")

    # 8. Storage Details (10 pts)
    bag_ok = text_check(r'Bag', xml_content)
    tent_ok = text_check(r'Tent A', xml_content)
    if bag_ok and tent_ok:
        score += 10
        fb.append("PASS: Storage location set to Bag inside Temporary Storage Tent A (+10)")
    else:
        fb.append("FAIL: Storage location description or type missing/incorrect")

    passed = score >= pass_threshold
    
    # Must have actually exported the file to pass
    if not result.get("file_exists", False):
        passed = False

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(fb)
    }