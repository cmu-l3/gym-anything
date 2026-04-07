#!/usr/bin/env python3
"""
Verifier for remote_unmanned_facility_geodata_update task.

Programmatically validates the contents of the exported EPA Tier II XML file.
Tier II uses XML tags like <Manned>, <MaxOccupants>, <Latitude>, etc. 
We use robust regex parsing to verify the data regardless of slight XML schema versions.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_remote_unmanned_facility_geodata_update(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get("metadata", {})
    result_file = metadata.get("result_file", "C:\\Users\\Docker\\Desktop\\task_result.json")

    # Retrieve the exported JSON securely
    tmp = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp.name)
        with open(tmp.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result JSON: {e}"}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

    # 1. Do-Nothing Check & Timestamps
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Submission file apex_station7_updated.t2s was not found. Do-nothing detected."
        }
    
    if not result.get("file_created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Submission file exists but predates the task start. Anti-gaming check failed."
        }

    xml = result.get("xml_content", "")
    if not xml:
        return {
            "passed": False,
            "score": 10,
            "feedback": "Submission file created, but no valid XML payload found inside the .t2s archive."
        }

    score = 20  # Base points for creating the valid .t2s file during the task
    feedback_parts = ["File created (+20)"]

    # 2. Validate Latitude & Longitude (20 pts)
    has_lat = "31.8456" in xml
    has_lon = "-103.5892" in xml
    if has_lat and has_lon:
        score += 20
        feedback_parts.append("Coordinates are correct (+20)")
    else:
        feedback_parts.append(f"Coordinates incorrect (Found Lat: {has_lat}, Lon: {has_lon})")

    # 3. Validate Unmanned Status (15 pts)
    # Different versions of Tier2 Submit might export "false", "0", "N", or "No"
    has_unmanned = bool(re.search(r'<[^>]*[Mm]anned[^>]*>\s*(false|0|N|No|Unmanned)\s*</', xml, re.IGNORECASE))
    if has_unmanned:
        score += 15
        feedback_parts.append("Manned status set to Unmanned (+15)")
    else:
        feedback_parts.append("Manned status missing or still set to Yes")

    # 4. Validate Occupants (15 pts)
    # Looking for tags like <MaxOccupants>4</MaxOccupants> or <MaximumNoOccupants>4</MaximumNoOccupants>
    has_occupants = bool(re.search(r'<[^>]*[Oo]ccupant[^>]*>\s*0*4\s*</', xml, re.IGNORECASE))
    if not has_occupants:
        # Fallback unstructured regex checking if "4" is near "occupant"
        if re.search(r'[Oo]ccupant', xml, re.IGNORECASE) and re.search(r'>\s*4\s*<', xml):
            has_occupants = True
            
    if has_occupants:
        score += 15
        feedback_parts.append("Max occupants set to 4 (+15)")
    else:
        feedback_parts.append("Max occupants incorrect or missing")

    # 5. Validate Geodata Methodology and Description (10 pts)
    has_gps = bool(re.search(r'(GPS|Global Positioning)', xml, re.IGNORECASE))
    has_gate = bool(re.search(r'(Entrance|Gate)', xml, re.IGNORECASE))
    
    if has_gps and has_gate:
        score += 10
        feedback_parts.append("Geodata collection method and description correct (+10)")
    elif has_gps or has_gate:
        score += 5
        feedback_parts.append("Partial geodata methodology (+5)")
    else:
        feedback_parts.append("Geodata methodology/description missing")

    # 6. Validate Emergency Access Notes (20 pts)
    has_notes = bool(re.search(r'Knox-Box', xml, re.IGNORECASE))
    if has_notes:
        score += 20
        feedback_parts.append("Emergency access Knox-Box note found (+20)")
    else:
        feedback_parts.append("Emergency access note missing")

    pass_threshold = 70
    passed = score >= pass_threshold and has_lat and has_lon and has_unmanned

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }