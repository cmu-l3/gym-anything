#!/usr/bin/env python3
"""
Verifier for contact_network_rebuild task.

The agent must:
1. Import central_vt_facilities.xml (Montpelier Industrial Supply + Richmond Processing Plant)
2. Add Robert Flanagan as Fac. Emergency Coordinator to Montpelier Industrial Supply
3. Add Maria Santos as Fac. Emergency Coordinator + Emergency Contact to Richmond Processing Plant
4. Export to C:\\Users\\Docker\\Documents\\CAMEO\\contacts_updated.xml

Scoring (100 points):
  - 25 pts: Flanagan added to Montpelier with Fac. Emergency Coordinator type
  - 25 pts: Flanagan's phone number 802-555-0219 present in export
  - 25 pts: Santos added to Richmond with Fac. Emergency Coordinator type
  - 25 pts: Santos has Emergency Contact type AND phone 802-555-0347 present
Pass threshold: >= 70 points
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

CAMEO_NS = "https://cameo.noaa.gov/epcra_tier2/data_standard/v1"
EXPECTED_EXPORT = "C:\\Users\\Docker\\Documents\\CAMEO\\contacts_updated.xml"
RESULT_JSON = "C:\\Windows\\Temp\\contact_network_rebuild_result.json"


def _get_contacts_from_xml(xml_path):
    """Parse XML and return list of contact dicts."""
    ns = {"t": CAMEO_NS}
    contacts = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        for contact in root.findall(".//t:contact", ns):
            first = (contact.findtext("t:firstName", default="", namespaces=ns) or "").strip()
            last = (contact.findtext("t:lastName", default="", namespaces=ns) or "").strip()
            title = (contact.findtext("t:title", default="", namespaces=ns) or "").strip()
            types = [
                ct.text.strip()
                for ct in contact.findall("t:contactTypes/t:contactType", ns)
                if ct.text
            ]
            phones = [
                ph.findtext("t:phoneNumber", default="", namespaces=ns).strip()
                for ph in contact.findall("t:phones/t:phone", ns)
            ]
            contacts.append({
                "first": first,
                "last": last,
                "title": title,
                "types": types,
                "phones": phones,
            })
    except Exception as e:
        logger.warning("Error parsing contacts from XML: %s", e)
    return contacts


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


def verify_contact_network_rebuild(traj, env_info, task_info):
    """Verify that required contacts were added to both facilities."""
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback = []
    subscores = {}

    # Step 1: Get the result JSON from VM
    local_result_json = tempfile.mktemp(suffix="_contacts_result.json")
    try:
        copy_from_env(RESULT_JSON, local_result_json)
        with open(local_result_json, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.warning("Could not retrieve result JSON: %s", e)
        result = {}

    export_exists = result.get("export_xml_exists", False)
    export_is_new = result.get("export_xml_is_new", False)

    # Step 2: Gate checks on export file
    if not export_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No export XML found at C:\\Users\\Docker\\Documents\\CAMEO\\contacts_updated.xml. "
                        "Agent must export the updated Tier II data.",
            "subscores": subscores,
        }

    if not export_is_new:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export XML exists but was not created/modified during this task run.",
            "subscores": subscores,
        }

    # Step 3: Independently copy and parse the export XML
    local_xml = tempfile.mktemp(suffix="_contacts_updated.xml")
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
    has_montpelier = any("montpelier industrial" in n.lower() for n in facility_names)
    has_richmond = any("richmond processing" in n.lower() for n in facility_names)

    if not has_montpelier and not has_richmond:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong target. Export XML does not contain target facilities. "
                        f"Found: {facility_names}",
            "subscores": subscores,
        }

    # Step 5: Parse all contacts from the exported XML
    contacts = _get_contacts_from_xml(local_xml)
    contact_text = " ".join(
        f"{c['first']} {c['last']} {c['title']} {' '.join(c['types'])} {' '.join(c['phones'])}"
        for c in contacts
    ).lower()

    # Find Flanagan contact
    flanagan_contacts = [c for c in contacts if "flanagan" in c["last"].lower()]
    # Find Santos contact
    santos_contacts = [c for c in contacts if "santos" in c["last"].lower()]

    # Criterion 1: Flanagan added with Fac. Emergency Coordinator type (25 pts)
    try:
        flanagan_is_fac_ec = any(
            any("fac. emergency coordinator" in t.lower() or "fac.emergency" in t.lower()
                or ("fac" in t.lower() and "emergency" in t.lower() and "coord" in t.lower())
                for t in c["types"])
            for c in flanagan_contacts
        )
        if flanagan_is_fac_ec:
            score += 25
            subscores["flanagan_fac_ec"] = True
            feedback.append("PASS: Flanagan added as Fac. Emergency Coordinator")
        else:
            subscores["flanagan_fac_ec"] = False
            if flanagan_contacts:
                feedback.append(f"FAIL: Flanagan found but not as Fac. Emergency Coordinator (types: {flanagan_contacts[0]['types']})")
            else:
                feedback.append("FAIL: Robert Flanagan not found in exported contacts")
    except Exception as e:
        feedback.append(f"ERROR checking Flanagan coordinator: {e}")

    # Criterion 2: Flanagan phone 802-555-0219 (25 pts)
    try:
        flanagan_has_phone = any(
            any("802-555-0219" in ph or "8025550219" in ph.replace("-", "") for ph in c["phones"])
            for c in flanagan_contacts
        )
        if flanagan_has_phone:
            score += 25
            subscores["flanagan_phone"] = True
            feedback.append("PASS: Flanagan phone 802-555-0219 present")
        else:
            subscores["flanagan_phone"] = False
            if flanagan_contacts:
                feedback.append(f"FAIL: Flanagan found but phone 802-555-0219 not in record (phones: {flanagan_contacts[0]['phones']})")
            else:
                feedback.append("FAIL: Flanagan not found — cannot check phone")
    except Exception as e:
        feedback.append(f"ERROR checking Flanagan phone: {e}")

    # Criterion 3: Santos with Fac. Emergency Coordinator type (25 pts)
    try:
        santos_is_fac_ec = any(
            any("fac. emergency coordinator" in t.lower() or "fac.emergency" in t.lower()
                or ("fac" in t.lower() and "emergency" in t.lower() and "coord" in t.lower())
                for t in c["types"])
            for c in santos_contacts
        )
        if santos_is_fac_ec:
            score += 25
            subscores["santos_fac_ec"] = True
            feedback.append("PASS: Santos added as Fac. Emergency Coordinator")
        else:
            subscores["santos_fac_ec"] = False
            if santos_contacts:
                feedback.append(f"FAIL: Santos found but not as Fac. Emergency Coordinator (types: {santos_contacts[0]['types']})")
            else:
                feedback.append("FAIL: Maria Santos not found in exported contacts")
    except Exception as e:
        feedback.append(f"ERROR checking Santos coordinator: {e}")

    # Criterion 4: Santos has Emergency Contact type AND phone 802-555-0347 (25 pts)
    try:
        santos_is_ec = any(
            any("emergency contact" in t.lower() for t in c["types"])
            for c in santos_contacts
        )
        santos_has_phone = any(
            any("802-555-0347" in ph or "8025550347" in ph.replace("-", "") for ph in c["phones"])
            for c in santos_contacts
        )
        if santos_is_ec and santos_has_phone:
            score += 25
            subscores["santos_ec_and_phone"] = True
            feedback.append("PASS: Santos has Emergency Contact type and phone 802-555-0347")
        else:
            subscores["santos_ec_and_phone"] = False
            if not santos_contacts:
                feedback.append("FAIL: Maria Santos not found — cannot check Emergency Contact type/phone")
            elif not santos_is_ec:
                feedback.append(f"FAIL: Santos not marked as Emergency Contact (types: {santos_contacts[0]['types']})")
            else:
                feedback.append(f"FAIL: Santos Emergency Contact type present but phone 802-555-0347 missing")
    except Exception as e:
        feedback.append(f"ERROR checking Santos emergency contact: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "No checks completed",
        "subscores": subscores,
    }
