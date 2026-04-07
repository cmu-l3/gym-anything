#!/usr/bin/env python3
"""
Verifier for new_facility_onboarding task.

The agent must:
1. Import champlain_plastics.xml and essex_chemical.xml into CAMEO
2. For Champlain Plastics and Composites:
   - Add contact James Kowalski (Corporate EHS Director, Fac. Emergency Coordinator, 802-555-0451)
   - Set fire district to "Burlington Central Fire Station 3"
3. For Essex Chemical and Coatings:
   - Add contact Sandra Obrecht (Site Safety Manager, Emergency Contact, 802-555-0523)
   - Set fire district to "Essex Fire District 1"
4. Export to C:\\Users\\Docker\\Documents\\CAMEO\\new_facilities.xml

Scoring (100 points):
  - 20 pts: Both Champlain Plastics and Essex Chemical present in export
  - 20 pts: Champlain fire district contains "Burlington Central" or "Fire Station 3"
  - 20 pts: Kowalski added with Fac. Emergency Coordinator type
  - 20 pts: Essex fire district contains "Essex Fire District 1"
  - 20 pts: Obrecht added with Emergency Contact type
Pass threshold: >= 70 points
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

CAMEO_NS = "https://cameo.noaa.gov/epcra_tier2/data_standard/v1"
EXPECTED_EXPORT = "C:\\Users\\Docker\\Documents\\CAMEO\\new_facilities.xml"
RESULT_JSON = "C:\\Windows\\Temp\\new_facility_onboarding_result.json"


def _get_facilities(xml_path):
    """Return list of {name, fireDistrict} dicts."""
    ns = {"t": CAMEO_NS}
    facilities = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for fac in root.findall(".//t:facility", ns):
            name = (fac.findtext("t:facilityName", default="", namespaces=ns) or "").strip()
            fd = (fac.findtext("t:fireDistrict", default="", namespaces=ns) or "").strip()
            facilities.append({"name": name, "fireDistrict": fd})
    except Exception as e:
        logger.warning("Error parsing facilities: %s", e)
    return facilities


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


def verify_new_facility_onboarding(traj, env_info, task_info):
    """Verify both facilities were onboarded with contacts and fire districts."""
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback = []
    subscores = {}

    # Step 1: Get result JSON from VM
    local_result_json = tempfile.mktemp(suffix="_onboarding_result.json")
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
            "feedback": "No export XML found at C:\\Users\\Docker\\Documents\\CAMEO\\new_facilities.xml. "
                        "Agent must export the onboarded facility data.",
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
    local_xml = tempfile.mktemp(suffix="_new_facilities.xml")
    try:
        copy_from_env(EXPECTED_EXPORT, local_xml)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not copy export XML from VM: {e}",
            "subscores": subscores,
        }

    # Step 4: Parse facilities and contacts
    facilities = _get_facilities(local_xml)
    contacts = _get_contacts(local_xml)

    fac_names_lower = [f["name"].lower() for f in facilities]
    has_champlain = any("champlain plastics" in n for n in fac_names_lower)
    has_essex_chem = any("essex chemical" in n for n in fac_names_lower)

    # Wrong-target gate
    if not has_champlain and not has_essex_chem:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Neither target facility found in export. "
                        f"Found: {[f['name'] for f in facilities]}",
            "subscores": subscores,
        }

    # Criterion 1: Both facilities present (20 pts)
    try:
        if has_champlain and has_essex_chem:
            score += 20
            subscores["both_facilities"] = True
            feedback.append("PASS: Both Champlain Plastics and Essex Chemical imported")
        else:
            subscores["both_facilities"] = False
            missing = []
            if not has_champlain:
                missing.append("Champlain Plastics and Composites")
            if not has_essex_chem:
                missing.append("Essex Chemical and Coatings")
            feedback.append(f"FAIL: Missing facilities: {missing}")
    except Exception as e:
        feedback.append(f"ERROR checking both facilities: {e}")

    # Criterion 2: Champlain fire district correct (20 pts)
    try:
        champlain_fac = next((f for f in facilities if "champlain plastics" in f["name"].lower()), None)
        if champlain_fac:
            fd = champlain_fac["fireDistrict"].lower()
            champlain_fd_correct = (
                "burlington central" in fd
                or "fire station 3" in fd
                or ("burlington" in fd and "3" in fd)
            )
            if champlain_fd_correct:
                score += 20
                subscores["champlain_fire_district"] = True
                feedback.append(f"PASS: Champlain fire district set correctly ('{champlain_fac['fireDistrict']}')")
            else:
                subscores["champlain_fire_district"] = False
                feedback.append(f"FAIL: Champlain fire district not set to Burlington Central Fire Station 3 (found: '{champlain_fac['fireDistrict']}')")
        else:
            subscores["champlain_fire_district"] = False
            feedback.append("FAIL: Champlain Plastics not found — cannot check fire district")
    except Exception as e:
        feedback.append(f"ERROR checking Champlain fire district: {e}")

    # Criterion 3: Kowalski added as Fac. Emergency Coordinator (20 pts)
    try:
        kowalski_contacts = [c for c in contacts if "kowalski" in c["last"].lower()]
        kowalski_is_fec = any(
            any("fac. emergency coordinator" in t.lower() or
                ("fac" in t.lower() and "emergency" in t.lower() and "coord" in t.lower())
                for t in c["types"])
            for c in kowalski_contacts
        )
        if kowalski_is_fec:
            score += 20
            subscores["kowalski_contact"] = True
            feedback.append("PASS: James Kowalski added as Fac. Emergency Coordinator")
        else:
            subscores["kowalski_contact"] = False
            if kowalski_contacts:
                feedback.append(f"FAIL: Kowalski found but not as Fac. Emergency Coordinator (types: {kowalski_contacts[0]['types']})")
            else:
                feedback.append("FAIL: James Kowalski not found in exported contacts")
    except Exception as e:
        feedback.append(f"ERROR checking Kowalski: {e}")

    # Criterion 4: Essex Chemical fire district correct (20 pts)
    try:
        essex_fac = next((f for f in facilities if "essex chemical" in f["name"].lower()), None)
        if essex_fac:
            fd = essex_fac["fireDistrict"].lower()
            essex_fd_correct = "essex fire district 1" in fd or ("essex" in fd and "1" in fd and "district" in fd)
            if essex_fd_correct:
                score += 20
                subscores["essex_fire_district"] = True
                feedback.append(f"PASS: Essex Chemical fire district set correctly ('{essex_fac['fireDistrict']}')")
            else:
                subscores["essex_fire_district"] = False
                feedback.append(f"FAIL: Essex Chemical fire district not set to 'Essex Fire District 1' (found: '{essex_fac['fireDistrict']}')")
        else:
            subscores["essex_fire_district"] = False
            feedback.append("FAIL: Essex Chemical and Coatings not found — cannot check fire district")
    except Exception as e:
        feedback.append(f"ERROR checking Essex fire district: {e}")

    # Criterion 5: Obrecht added as Emergency Contact (20 pts)
    try:
        obrecht_contacts = [c for c in contacts if "obrecht" in c["last"].lower()]
        obrecht_is_ec = any(
            any("emergency contact" in t.lower() for t in c["types"])
            for c in obrecht_contacts
        )
        if obrecht_is_ec:
            score += 20
            subscores["obrecht_contact"] = True
            feedback.append("PASS: Sandra Obrecht added as Emergency Contact")
        else:
            subscores["obrecht_contact"] = False
            if obrecht_contacts:
                feedback.append(f"FAIL: Obrecht found but not as Emergency Contact (types: {obrecht_contacts[0]['types']})")
            else:
                feedback.append("FAIL: Sandra Obrecht not found in exported contacts")
    except Exception as e:
        feedback.append(f"ERROR checking Obrecht: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "No checks completed",
        "subscores": subscores,
    }
