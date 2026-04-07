#!/usr/bin/env python3
"""
Verifier for serc_audit_response task.

The agent must read C:\\workspace\\data\\serc_audit_report.txt and fix all 4 findings
for Lakeside Chemical Supply in CAMEO, then export to:
  C:\\Users\\Docker\\Documents\\CAMEO\\lakeside_corrected.xml

Findings to correct:
1. Hydrogen Peroxide (7722-84-1): average amount 8500 -> 4200 lbs (code 05->04)
2. Sulfuric Acid (7664-93-9): storage location "Chemical Storage A" -> "Drum Storage Building B"
3. Contact: David Nguyen -> Patricia Okonkwo (802-555-0293, Fac. Emergency Coordinator + Emergency Contact)
4. Fire district: "Station 4 - Montpelier South" -> "Station 12 - Montpelier Central"

Scoring (100 points):
  - 25 pts: Hydrogen Peroxide average corrected (aveAmountCode="04" or aveAmount <= 5000)
  - 25 pts: Sulfuric Acid storage location = "Drum Storage Building B"
  - 25 pts: Patricia Okonkwo present in contacts with Fac. Emergency Coordinator type
  - 25 pts: Fire district contains "Station 12" or "Montpelier Central"
Pass threshold: >= 70 points
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

CAMEO_NS = "https://cameo.noaa.gov/epcra_tier2/data_standard/v1"
EXPECTED_EXPORT = "C:\\Users\\Docker\\Documents\\CAMEO\\lakeside_corrected.xml"
RESULT_JSON = "C:\\Windows\\Temp\\serc_audit_response_result.json"

H2O2_CAS = "7722-84-1"
H2SO4_CAS = "7664-93-9"


def _build_chemical_map(xml_path):
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
            storage_locs = [
                (sl.findtext("t:locationDescription", default="", namespaces=ns) or "").strip()
                for sl in chem.findall(".//t:storageLocation", ns)
            ]
            chem_map[cas] = {
                "aveAmount": ave_amt.strip(),
                "aveAmountCode": ave_code.strip(),
                "storageLocations": storage_locs,
            }
    except Exception as e:
        logger.warning("Error building chemical map: %s", e)
    return chem_map


def _get_contacts(xml_path):
    ns = {"t": CAMEO_NS}
    contacts = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for contact in root.findall(".//t:contact", ns):
            first = (contact.findtext("t:firstName", default="", namespaces=ns) or "").strip()
            last = (contact.findtext("t:lastName", default="", namespaces=ns) or "").strip()
            types = [
                ct.text.strip()
                for ct in contact.findall("t:contactTypes/t:contactType", ns)
                if ct.text
            ]
            phones = [
                (ph.findtext("t:phoneNumber", default="", namespaces=ns) or "").strip()
                for ph in contact.findall("t:phones/t:phone", ns)
            ]
            contacts.append({"first": first, "last": last, "types": types, "phones": phones})
    except Exception as e:
        logger.warning("Error parsing contacts: %s", e)
    return contacts


def _get_fire_district(xml_path):
    ns = {"t": CAMEO_NS}
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for fac in root.findall(".//t:facility", ns):
            fd = (fac.findtext("t:fireDistrict", default="", namespaces=ns) or "").strip()
            if fd:
                return fd
    except Exception:
        pass
    return ""


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


def verify_serc_audit_response(traj, env_info, task_info):
    """Verify all 4 SERC audit corrections were made."""
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback = []
    subscores = {}

    # Step 1: Get result JSON from VM
    local_result_json = tempfile.mktemp(suffix="_serc_result.json")
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
            "feedback": "No export XML found at C:\\Users\\Docker\\Documents\\CAMEO\\lakeside_corrected.xml. "
                        "Agent must export the corrected data.",
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
    local_xml = tempfile.mktemp(suffix="_lakeside_corrected.xml")
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
    has_lakeside = any("lakeside" in n.lower() for n in facility_names)
    if not has_lakeside:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong target. Export does not contain 'Lakeside Chemical Supply'. "
                        f"Found: {facility_names}",
            "subscores": subscores,
        }

    chem_map = _build_chemical_map(local_xml)
    contacts = _get_contacts(local_xml)
    fire_district = _get_fire_district(local_xml)

    # Criterion 1: Hydrogen Peroxide average corrected (25 pts)
    try:
        h2o2 = chem_map.get(H2O2_CAS, {})
        ave_code = h2o2.get("aveAmountCode", "")
        ave_amt_str = h2o2.get("aveAmount", "")
        ave_amt = 0
        try:
            ave_amt = int(ave_amt_str)
        except (ValueError, TypeError):
            pass
        # Original: code=05 (5k-9.9k), corrected: code=04 (1k-4.9k)
        # Accept code "04" OR numeric value <= 5000
        h2o2_corrected = (ave_code == "04") or (0 < ave_amt <= 5000)
        if h2o2_corrected:
            score += 25
            subscores["h2o2_quantity"] = True
            feedback.append(f"PASS: H2O2 average corrected (code={ave_code}, value={ave_amt})")
        else:
            subscores["h2o2_quantity"] = False
            if not h2o2:
                feedback.append(f"FAIL: Hydrogen Peroxide ({H2O2_CAS}) not found in export")
            else:
                feedback.append(f"FAIL: H2O2 average not corrected (code={ave_code}, value={ave_amt}; expected code=04 or value<=5000)")
    except Exception as e:
        feedback.append(f"ERROR checking H2O2: {e}")

    # Criterion 2: Sulfuric Acid storage location = "Drum Storage Building B" (25 pts)
    try:
        h2so4 = chem_map.get(H2SO4_CAS, {})
        storage_locs = h2so4.get("storageLocations", [])
        has_drum_storage = any("drum storage building b" in loc.lower() for loc in storage_locs)
        if has_drum_storage:
            score += 25
            subscores["h2so4_storage"] = True
            feedback.append("PASS: Sulfuric Acid storage location corrected to 'Drum Storage Building B'")
        else:
            subscores["h2so4_storage"] = False
            if not h2so4:
                feedback.append(f"FAIL: Sulfuric Acid ({H2SO4_CAS}) not found in export")
            else:
                feedback.append(f"FAIL: Sulfuric Acid storage not 'Drum Storage Building B' (found: {storage_locs})")
    except Exception as e:
        feedback.append(f"ERROR checking H2SO4 storage: {e}")

    # Criterion 3: Patricia Okonkwo added as Fac. Emergency Coordinator (25 pts)
    try:
        okonkwo_contacts = [c for c in contacts if "okonkwo" in c["last"].lower()]
        okonkwo_is_fec = any(
            any("fac. emergency coordinator" in t.lower() or
                ("fac" in t.lower() and "emergency" in t.lower() and "coord" in t.lower())
                for t in c["types"])
            for c in okonkwo_contacts
        )
        if okonkwo_is_fec:
            score += 25
            subscores["okonkwo_contact"] = True
            feedback.append("PASS: Patricia Okonkwo added as Fac. Emergency Coordinator")
        else:
            subscores["okonkwo_contact"] = False
            if okonkwo_contacts:
                feedback.append(f"FAIL: Okonkwo found but not as Fac. Emergency Coordinator (types: {okonkwo_contacts[0]['types']})")
            else:
                feedback.append("FAIL: Patricia Okonkwo not found in exported contacts (David Nguyen not replaced)")
    except Exception as e:
        feedback.append(f"ERROR checking Okonkwo contact: {e}")

    # Criterion 4: Fire district corrected to Station 12 / Montpelier Central (25 pts)
    try:
        fd_lower = fire_district.lower()
        fire_district_corrected = "station 12" in fd_lower or "montpelier central" in fd_lower
        if fire_district_corrected:
            score += 25
            subscores["fire_district"] = True
            feedback.append(f"PASS: Fire district corrected ('{fire_district}')")
        else:
            subscores["fire_district"] = False
            feedback.append(f"FAIL: Fire district not corrected (current: '{fire_district}'; expected 'Station 12 - Montpelier Central')")
    except Exception as e:
        feedback.append(f"ERROR checking fire district: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "No checks completed",
        "subscores": subscores,
    }
