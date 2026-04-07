#!/usr/bin/env python3
"""
Verifier for ehs_chemical_correction task.

The agent must:
1. Import ehs_audit_data.xml into CAMEO Data Manager
2. Identify 3 chemicals with incorrect EHS=false designations
3. Correct EHS to true for each (Chlorine Dioxide, Ammonia, Hydrofluoric Acid)
4. Export corrected data to C:\\Users\\Docker\\Documents\\CAMEO\\ehs_corrected.xml

Scoring (100 points):
  - 35 pts: Chlorine Dioxide (CAS 10049-04-4) EHS corrected to true
  - 30 pts: Ammonia, Anhydrous (CAS 7664-41-7) EHS corrected to true
  - 35 pts: Hydrofluoric Acid (CAS 7664-39-3) EHS corrected to true
Pass threshold: >= 70 points
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logger = logging.getLogger(__name__)

CAMEO_NS = "https://cameo.noaa.gov/epcra_tier2/data_standard/v1"
EXPECTED_EXPORT = "C:\\Users\\Docker\\Documents\\CAMEO\\ehs_corrected.xml"
RESULT_JSON = "C:\\Windows\\Temp\\ehs_chemical_correction_result.json"

# EHS chemicals that must be corrected (CAS -> points)
EHS_CORRECTIONS = {
    "10049-04-4": ("Chlorine Dioxide", 35),
    "7664-41-7":  ("Ammonia, Anhydrous", 30),
    "7664-39-3":  ("Hydrofluoric Acid", 35),
}


def _parse_xml_ehs(xml_path):
    """Parse exported XML and return dict of CAS -> ehs_bool for all chemicals."""
    ns = {"t": CAMEO_NS}
    ehs_by_cas = {}
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        # Check top-level chemicals
        for chem in root.findall(".//t:chemical", ns):
            cas = (chem.findtext("t:casNumber", default="", namespaces=ns) or "").strip()
            ehs_str = (chem.findtext("t:ehs", default="false", namespaces=ns) or "false").strip().lower()
            if cas:
                ehs_by_cas[cas] = (ehs_str == "true")
        # Also check mixture components
        for comp in root.findall(".//t:mixtureComponent", ns):
            cas = (comp.findtext("t:casNumber", default="", namespaces=ns) or "").strip()
            ehs_str = (comp.findtext("t:ehs", default="false", namespaces=ns) or "false").strip().lower()
            if cas and cas not in ehs_by_cas:
                ehs_by_cas[cas] = (ehs_str == "true")
    except ET.ParseError as e:
        logger.warning("XML parse error: %s", e)
    except Exception as e:
        logger.warning("Error reading XML: %s", e)
    return ehs_by_cas


def _get_facility_names(xml_path):
    """Return list of facility names in the XML."""
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


def verify_ehs_chemical_correction(traj, env_info, task_info):
    """Verify EHS designation corrections in the exported Tier II XML."""
    copy_from_env = env_info.get("copy_from_env")
    score = 0
    feedback = []
    subscores = {}

    # Step 1: Get the result JSON from the VM
    local_result_json = tempfile.mktemp(suffix="_ehs_result.json")
    try:
        copy_from_env(RESULT_JSON, local_result_json)
        with open(local_result_json, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.warning("Could not retrieve result JSON: %s", e)
        result = {}

    export_exists = result.get("export_xml_exists", False)
    export_is_new = result.get("export_xml_is_new", False)

    # Step 2: Check that the export file exists and was created during task
    if not export_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "No export XML found at C:\\Users\\Docker\\Documents\\CAMEO\\ehs_corrected.xml. "
                        "Agent must export the corrected Tier II data.",
            "subscores": subscores,
        }

    if not export_is_new:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Export XML exists but was not created/modified during this task run. "
                        "Agent must export AFTER making corrections.",
            "subscores": subscores,
        }

    # Step 3: Independently copy and parse the export XML
    local_xml = tempfile.mktemp(suffix="_ehs_corrected.xml")
    try:
        copy_from_env(EXPECTED_EXPORT, local_xml)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Export XML exists in result JSON but could not be copied from VM: {e}",
            "subscores": subscores,
        }

    # Step 4: Validate the export contains both target facilities (wrong-target gate)
    facility_names = _get_facility_names(local_xml)
    facility_text = " ".join(facility_names).lower()
    has_northfield = any("northfield" in n.lower() for n in facility_names)
    has_essex = any("essex wire" in n.lower() or "essex" in n.lower() for n in facility_names)

    if not has_northfield and not has_essex:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"CRITICAL: Wrong target. Export XML does not contain Northfield Paper Mill or "
                        f"Essex Wire and Cable. Found facilities: {facility_names}",
            "subscores": subscores,
        }

    # Step 5: Parse EHS designations
    ehs_by_cas = _parse_xml_ehs(local_xml)

    if not ehs_by_cas:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not parse any chemical data from the exported XML.",
            "subscores": subscores,
        }

    # Step 6: Score each required EHS correction
    for cas, (name, points) in EHS_CORRECTIONS.items():
        try:
            if ehs_by_cas.get(cas, False):
                score += points
                subscores[cas] = True
                feedback.append(f"PASS: {name} ({cas}) correctly designated EHS=true")
            else:
                subscores[cas] = False
                if cas not in ehs_by_cas:
                    feedback.append(f"FAIL: {name} ({cas}) not found in exported XML")
                else:
                    feedback.append(f"FAIL: {name} ({cas}) still marked EHS=false — not corrected")
        except Exception as e:
            logger.warning("Error checking CAS %s: %s", cas, e)
            feedback.append(f"ERROR checking {name} ({cas}): {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "No checks completed",
        "subscores": subscores,
    }
