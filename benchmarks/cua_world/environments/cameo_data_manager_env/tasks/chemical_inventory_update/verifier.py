#!/usr/bin/env python3
"""
Verifier for chemical_inventory_update task.

The agent must update Green Valley Water Facility in CAMEO:
1. Chlorine (7782-50-5): max amount updated to 60,000 lbs (amount code 07: 50k-99.9k)
2. Fluorosilic Acid (16961-83-4): average amount updated to 55,000 lbs (amount code 07)
3. Sodium Hypochlorite (7681-52-9) added: liquid, non-EHS, ave=8500, max=15000,
   storage location "Chemical Injection Room"
Export to C:\\Users\\Docker\\Documents\\CAMEO\\green_valley_2024.xml

Scoring (100 points):
  - 25 pts: Chlorine maxAmountCode = "07" (50,000-99,999 lbs range)
  - 25 pts: Fluorosilic Acid aveAmountCode = "07" (50,000-99,999 lbs range)
  - 25 pts: Sodium Hypochlorite (CAS 7681-52-9) present in export XML
  - 25 pts: Sodium Hypochlorite storage location contains "Chemical Injection Room"
Pass threshold: >= 70 points
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

CAMEO_NS = "https://cameo.noaa.gov/epcra_tier2/data_standard/v1"
EXPECTED_EXPORT = "C:\\Users\\Docker\\Documents\\CAMEO\\green_valley_2024.xml"
RESULT_JSON = "C:\\Windows\\Temp\\chemical_inventory_update_result.json"

# Amount code 07 = 50,000-99,999 lbs
CHLORINE_CAS = "7782-50-5"
FLUOROSILIC_CAS = "16961-83-4"
NAOCL_CAS = "7681-52-9"


def _build_chemical_map(xml_path):
    """Return dict: CAS -> {aveAmount, aveAmountCode, maxAmount, maxAmountCode, storageLocations}."""
    ns = {"t": CAMEO_NS}
    chem_map = {}
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for chem in root.findall(".//t:chemical", ns):
            cas = (chem.findtext("t:casNumber", default="", namespaces=ns) or "").strip()
            if not cas:
                continue
            ave_amt = chem.findtext("t:aveAmount", default="", namespaces=ns) or ""
            ave_code = chem.findtext("t:aveAmountCode", default="", namespaces=ns) or ""
            max_amt = chem.findtext("t:maxAmount", default="", namespaces=ns) or ""
            max_code = chem.findtext("t:maxAmountCode", default="", namespaces=ns) or ""
            storage_locs = [
                (sl.findtext("t:locationDescription", default="", namespaces=ns) or "").strip()
                for sl in chem.findall(".//t:storageLocation", ns)
            ]
            chem_map[cas] = {
                "aveAmount": ave_amt.strip(),
                "aveAmountCode": ave_code.strip(),
                "maxAmount": max_amt.strip(),
                "maxAmountCode": max_code.strip(),
                "storageLocations": storage_locs,
            }
    except Exception as e:
        logger.warning("Error building chemical map: %s", e)
    return chem_map


def _get_facility_names(xml_path):
    ns = {"t": CAMEO_NS}
    names = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for fac in root.findall(".//t:facility", ns):
            name = (fac.findtext("t:facilityName", default="", namespaces=ns) or "").strip()
            if name:
                names.append(name)
    except Exception:
        pass
    return names


def verify_chemical_inventory_update(traj, env_info, task_info):
    """Verify inventory updates to Green Valley Water Facility."""
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback = []
    subscores = {}

    # Step 1: Get result JSON from VM
    local_result_json = tempfile.mktemp(suffix="_inv_result.json")
    try:
        copy_from_env(RESULT_JSON, local_result_json)
        with open(local_result_json, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.warning("Could not retrieve result JSON: %s", e)
        result = {}

    export_exists = result.get("export_xml_exists", False)
    export_is_new = result.get("export_xml_is_new", False)

    # Step 2: Gate checks
    if not export_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No export XML found at C:\\Users\\Docker\\Documents\\CAMEO\\green_valley_2024.xml. "
                        "Agent must export the updated data.",
            "subscores": subscores,
        }

    if not export_is_new:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export XML was not created/modified during this task run.",
            "subscores": subscores,
        }

    # Step 3: Independently copy and parse the XML
    local_xml = tempfile.mktemp(suffix="_gv_2024.xml")
    try:
        copy_from_env(EXPECTED_EXPORT, local_xml)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not copy export XML from VM: {e}",
            "subscores": subscores,
        }

    # Step 4: Wrong-target gate
    facility_names = _get_facility_names(local_xml)
    has_green_valley = any("green valley" in n.lower() for n in facility_names)
    if not has_green_valley:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong target. Export XML does not contain 'Green Valley Water Facility'. "
                        f"Found: {facility_names}",
            "subscores": subscores,
        }

    # Step 5: Build chemical map
    chem_map = _build_chemical_map(local_xml)

    # Criterion 1: Chlorine maxAmountCode = "07" (50k-99.9k range) (25 pts)
    try:
        chlorine = chem_map.get(CHLORINE_CAS, {})
        max_code = chlorine.get("maxAmountCode", "")
        max_amt_str = chlorine.get("maxAmount", "")
        max_amt = 0
        try:
            max_amt = int(max_amt_str)
        except (ValueError, TypeError):
            pass

        # Accept code "07" OR numeric value >= 50000
        chlorine_updated = (max_code == "07") or (max_amt >= 50000)
        if chlorine_updated:
            score += 25
            subscores["chlorine_max"] = True
            feedback.append(f"PASS: Chlorine max quantity updated (code={max_code}, value={max_amt})")
        else:
            subscores["chlorine_max"] = False
            if not chlorine:
                feedback.append(f"FAIL: Chlorine ({CHLORINE_CAS}) not found in export XML")
            else:
                feedback.append(f"FAIL: Chlorine max not updated to 50k+ range (code={max_code}, value={max_amt})")
    except Exception as e:
        feedback.append(f"ERROR checking Chlorine max: {e}")

    # Criterion 2: Fluorosilic Acid aveAmountCode = "07" (50k-99.9k range) (25 pts)
    try:
        fluorosilic = chem_map.get(FLUOROSILIC_CAS, {})
        ave_code = fluorosilic.get("aveAmountCode", "")
        ave_amt_str = fluorosilic.get("aveAmount", "")
        ave_amt = 0
        try:
            ave_amt = int(ave_amt_str)
        except (ValueError, TypeError):
            pass

        fluorosilic_updated = (ave_code == "07") or (ave_amt >= 50000)
        if fluorosilic_updated:
            score += 25
            subscores["fluorosilic_ave"] = True
            feedback.append(f"PASS: Fluorosilic Acid average updated (code={ave_code}, value={ave_amt})")
        else:
            subscores["fluorosilic_ave"] = False
            if not fluorosilic:
                feedback.append(f"FAIL: Fluorosilic Acid ({FLUOROSILIC_CAS}) not found in export XML")
            else:
                feedback.append(f"FAIL: Fluorosilic Acid average not updated to 50k+ range (code={ave_code}, value={ave_amt})")
    except Exception as e:
        feedback.append(f"ERROR checking Fluorosilic Acid average: {e}")

    # Criterion 3: Sodium Hypochlorite (7681-52-9) present (25 pts)
    try:
        naocl = chem_map.get(NAOCL_CAS, {})
        if naocl:
            score += 25
            subscores["naocl_present"] = True
            feedback.append(f"PASS: Sodium Hypochlorite ({NAOCL_CAS}) found in export XML")
        else:
            subscores["naocl_present"] = False
            feedback.append(f"FAIL: Sodium Hypochlorite ({NAOCL_CAS}) not found in export XML — chemical not added")
    except Exception as e:
        feedback.append(f"ERROR checking Sodium Hypochlorite presence: {e}")

    # Criterion 4: Sodium Hypochlorite storage location = "Chemical Injection Room" (25 pts)
    try:
        naocl = chem_map.get(NAOCL_CAS, {})
        storage_locs = naocl.get("storageLocations", [])
        has_injection_room = any(
            "chemical injection" in loc.lower() or "injection room" in loc.lower()
            for loc in storage_locs
        )
        if has_injection_room:
            score += 25
            subscores["naocl_storage_loc"] = True
            feedback.append(f"PASS: Sodium Hypochlorite storage location 'Chemical Injection Room' present")
        else:
            subscores["naocl_storage_loc"] = False
            if naocl:
                feedback.append(f"FAIL: Sodium Hypochlorite present but storage location not 'Chemical Injection Room' (found: {storage_locs})")
            else:
                feedback.append(f"FAIL: Sodium Hypochlorite not found — cannot check storage location")
    except Exception as e:
        feedback.append(f"ERROR checking NaOCl storage location: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "No checks completed",
        "subscores": subscores,
    }
