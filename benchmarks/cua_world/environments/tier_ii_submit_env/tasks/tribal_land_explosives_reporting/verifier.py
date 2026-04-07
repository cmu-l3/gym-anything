#!/usr/bin/env python3
"""
Verifier for the tribal_land_explosives_reporting task.

Scoring (100 pts total, pass threshold: 70):
  10 pts - File exists and is exported correctly
  05 pts - Facility 'Red Rock Quarry' created
  15 pts - Indian Country Flag correctly set to TRUE
  15 pts - Tribe selection contains 'Navajo'
  15 pts - Primary NAICS code 212312 assigned
  10 pts - Chemical 'ANFO' added
  05 pts - ANFO marked as a Mixture (or pure flag removed)
  05 pts - ANFO marked with 'Explosive' physical hazard
  05 pts - Max amount code 06 set
  05 pts - Avg amount code 05 set
  05 pts - Days on site 365 set
  05 pts - Storage location description 'Blasting Magazine Alpha'

We perform regex-based auditing on the extracted Tier2Submit XML structure.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tribal_land_explosives_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier error: copy_from_env not available."}

    # Fetch extraction payload created by export_result.ps1
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\tribal_land_result.json", tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or parse result payload: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # Do-nothing detection check
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target submission file not found at C:\\Users\\Docker\\Desktop\\Tier2Output\\RedRock_TERC_2025.t2s."
        }

    xml = result.get("raw_xml", "")
    if not xml:
        return {
            "passed": False, 
            "score": 10, 
            "feedback": "Submission file exists, but it contained no valid XML data."
        }

    score = 10
    fb = ["File exported correctly (+10)"]

    # 1. Facility Setup Checks
    if re.search(r"Red Rock Quarry", xml, re.IGNORECASE):
        score += 5
        fb.append("Facility 'Red Rock Quarry' present (+5)")
    else:
        fb.append("Facility 'Red Rock Quarry' missing")

    # Indian Country field (typically <IndianCountryFlag>true</IndianCountryFlag> or 1)
    if re.search(r"IndianCountry[^>]*>(true|1|yes)", xml, re.IGNORECASE):
        score += 15
        fb.append("Indian Country flag = TRUE (+15)")
    else:
        fb.append("Indian Country flag is missing or false")

    if re.search(r"Navajo", xml, re.IGNORECASE):
        score += 15
        fb.append("Tribe Navajo Nation selected (+15)")
    else:
        fb.append("Tribe Navajo Nation not selected")

    if re.search(r"212312", xml):
        score += 15
        fb.append("NAICS 212312 assigned (+15)")
    else:
        fb.append("NAICS 212312 missing")

    # 2. Chemical Identity Checks
    if re.search(r"ANFO", xml, re.IGNORECASE):
        score += 10
        fb.append("Chemical 'ANFO' present (+10)")
    else:
        fb.append("Chemical 'ANFO' missing")

    if re.search(r"(Mixture|IsMixture)[^>]*>(true|1|yes)", xml, re.IGNORECASE) or \
       re.search(r"(Pure|IsPure)[^>]*>(false|0|no)", xml, re.IGNORECASE):
        score += 5
        fb.append("ANFO marked as Mixture (+5)")
    else:
        fb.append("ANFO not marked as Mixture")

    if re.search(r"Explosive[^>]*>(true|1|yes)", xml, re.IGNORECASE):
        score += 5
        fb.append("Explosive physical hazard checked (+5)")
    else:
        fb.append("Explosive physical hazard missing")

    # 3. Inventory Quantities
    if re.search(r"06", xml):
        score += 5
        fb.append("Max amount code '06' assigned (+5)")
    else:
        fb.append("Max amount code '06' missing")

    if re.search(r"05", xml):
        score += 5
        fb.append("Avg amount code '05' assigned (+5)")
    else:
        fb.append("Avg amount code '05' missing")

    if re.search(r"365", xml):
        score += 5
        fb.append("365 days on site assigned (+5)")
    else:
        fb.append("Days on site missing or incorrect")

    # 4. Storage Location Checks
    if re.search(r"Blasting Magazine Alpha", xml, re.IGNORECASE):
        score += 5
        fb.append("Storage location 'Blasting Magazine Alpha' added (+5)")
    else:
        fb.append("Storage location 'Blasting Magazine Alpha' missing")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 70)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(fb)
    }