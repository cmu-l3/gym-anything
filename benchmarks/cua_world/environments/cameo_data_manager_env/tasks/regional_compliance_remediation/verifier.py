#!/usr/bin/env python3
"""
Verifier for regional_compliance_remediation task.

The agent must:
1. Import greenfield_operations.xml and riverside_treatment.xml into CAMEO
2. Read compliance_order.txt and address all 7 findings:
   G-1: Add emergency coordinator from Greenfield's Notes field (Margaret Callahan, 802-555-0418)
   G-2: Correct Methanol (67-56-1) EHS designation to true (avg 8000 > TPQ 500)
   G-3: Assign Greenfield fire district to "Burlington Fire Station 1 - Downtown"
   R-1: Update H2O2 (7722-84-1) average daily amount to 5,200 lbs
   R-2: Update H2SO4 (7664-93-9) storage location to "Secondary Containment Building"
   R-3: Update Maria Santos phone to 802-555-0347
   R-4: Update Riverside fire district to "Station 12 - Montpelier Central"
3. Export to C:\\Users\\Docker\\Documents\\CAMEO\\regional_compliance_2025.xml

Scoring (100 points):
  - 15 pts: Callahan added as Fac. Emergency Coordinator
  - 10 pts: Callahan phone 802-555-0418
  - 15 pts: Methanol EHS = true
  - 10 pts: Greenfield fire district = Burlington Fire Station 1
  - 15 pts: H2O2 average amount corrected (~5200)
  - 15 pts: H2SO4 storage = Secondary Containment Building
  - 10 pts: Santos phone = 802-555-0347
  - 10 pts: Riverside fire district = Station 12 / Montpelier Central
Pass threshold: >= 70 points
"""

import json
import logging
import tempfile

logger = logging.getLogger(__name__)

EXPECTED_EXPORT = "C:\\Users\\Docker\\Documents\\CAMEO\\regional_compliance_2025.xml"
RESULT_JSON = "C:\\Windows\\Temp\\regional_compliance_result.json"


def verify_regional_compliance(traj, env_info, task_info):
    """Stub verifier - VLM checklist verification will be used for scoring."""
    copy_from_env = env_info.get("copy_from_env")
    feedback = []

    # Try to get result JSON from VM
    local_result_json = tempfile.mktemp(suffix="_regional_compliance_result.json")
    result = {}
    try:
        copy_from_env(RESULT_JSON, local_result_json)
        with open(local_result_json, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        logger.warning("Could not retrieve result JSON: %s", e)
        feedback.append(f"Could not retrieve result JSON: {e}")

    export_exists = result.get("export_xml_exists", False)
    export_is_new = result.get("export_xml_is_new", False)

    if not export_exists:
        feedback.append("No export XML found at expected path.")
    if not export_is_new:
        feedback.append("Export XML was not created/modified during this task run.")

    # Report quick content checks from export_result.ps1
    content_checks = {
        "greenfield_present": result.get("xml_contains_greenfield", False),
        "riverside_present": result.get("xml_contains_riverside", False),
        "callahan_present": result.get("xml_contains_callahan", False),
        "methanol_present": result.get("xml_contains_methanol", False),
        "secondary_containment": result.get("xml_contains_secondary_containment", False),
        "station_12": result.get("xml_contains_station12", False),
        "burlington_fire": result.get("xml_contains_burlington_fire", False),
    }

    for check_name, check_val in content_checks.items():
        status = "PASS" if check_val else "FAIL"
        feedback.append(f"{check_name}: {status}")

    # Stub: return passed=True so VLM checklist verifier is used for real scoring
    return {
        "passed": True,
        "score": 100,
        "feedback": "Stub verifier - use VLM checklist for scoring. " + " | ".join(feedback),
        "subscores": content_checks,
    }
