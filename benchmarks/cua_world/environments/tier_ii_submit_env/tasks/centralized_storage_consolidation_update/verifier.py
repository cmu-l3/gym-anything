#!/usr/bin/env python3
"""
Verifier for centralized_storage_consolidation_update task.

Scoring (100 pts total, pass threshold: 80):
  10 pts - File Export: Output .t2s file is successfully saved to correct path
  30 pts - Old Location Deletion: "Shed A" & "Shed B" absent from Acetone, Methanol, Isopropanol (10 pts per chemical)
  30 pts - New Location Addition: "Central Hazmat Bunker" added to all three (10 pts per chemical)
  20 pts - Correct Storage Conditions: New location has Steel Drum, Ambient Pressure, Ambient Temperature
  10 pts - Data Integrity: Distractor chemical (Sulfuric Acid) remains unmodified
"""

import json
import os
import tempfile
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_centralized_storage_consolidation_update(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', "C:\\Users\\Docker\\Desktop\\consolidation_update_result.json")
    output_file = metadata.get('output_file', "C:\\Users\\Docker\\Desktop\\Tier2Output\\rmi_consolidated_2024.t2s")

    # 1. Fetch JSON result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(result_file, tmp_json.name)
        with open(tmp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file was not created. Task failed."}

    # Anti-gaming check: Enforce the file was generated/modified during the task window
    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp predates task start (Anti-gaming check failed)."}

    # 2. Fetch and extract .t2s file
    tmp_t2s = tempfile.NamedTemporaryFile(delete=False, suffix=".t2s")
    try:
        copy_from_env(output_file, tmp_t2s.name)

        xml_data = None
        if zipfile.is_zipfile(tmp_t2s.name):
            with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
                xml_files = [n for n in z.namelist() if n.endswith('.xml')]
                if xml_files:
                    xml_data = z.read(xml_files[0])
        else:
            # Fallback if the agent directly saved an XML file but named it .t2s
            with open(tmp_t2s.name, 'rb') as f:
                xml_data = f.read()

        if not xml_data:
            return {"passed": False, "score": 10, "feedback": "Exported file is not a valid zip or missing internal XML."}

        root = ET.fromstring(xml_data)

    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse exported file: {e}"}
    finally:
        if os.path.exists(tmp_t2s.name):
            os.unlink(tmp_t2s.name)

    # XML extraction helpers mapping around dynamic EPA namespaces
    def strip_ns(tag):
        return tag.split('}', 1)[1] if '}' in tag else tag

    def get_descendants(el, tag_name):
        return [child for child in el.iter() if strip_ns(child.tag) == tag_name]

    # Map chemicals by CAS
    chemicals_map = {}
    for chem in get_descendants(root, "Chemical"):
        cas_nodes = get_descendants(chem, "CASNumber")
        if cas_nodes and cas_nodes[0].text:
            cas = cas_nodes[0].text.strip()
            chemicals_map[cas] = chem

    score = 10
    feedback = ["File Export: Passed (+10)"]

    targets = ["67-64-1", "67-56-1", "67-63-0"]
    old_loc_pts = 0
    new_loc_pts = 0
    conditions_correct = True

    # 3. Assess Target Chemicals
    for cas in targets:
        chem = chemicals_map.get(cas)
        if not chem:
            feedback.append(f"Chemical {cas} missing entirely from export.")
            conditions_correct = False
            continue

        locations = get_descendants(chem, "StorageLocation")
        has_old = False
        has_new = False
        bunker_correct = False

        for loc in locations:
            desc_nodes = get_descendants(loc, "LocationDescription")
            desc = desc_nodes[0].text.strip().lower() if desc_nodes and desc_nodes[0].text else ""

            if "shed a" in desc or "shed b" in desc:
                has_old = True

            if "central hazmat bunker" in desc or "hazmat bunker" in desc:
                has_new = True

                type_nodes = get_descendants(loc, "StorageType")
                stype = type_nodes[0].text.strip().lower() if type_nodes and type_nodes[0].text else ""

                press_nodes = get_descendants(loc, "Pressure")
                press = press_nodes[0].text.strip().lower() if press_nodes and press_nodes[0].text else ""

                temp_nodes = get_descendants(loc, "Temperature")
                temp = temp_nodes[0].text.strip().lower() if temp_nodes and temp_nodes[0].text else ""

                # Tier2Submit uses code letters or words (e.g. "C", "Steel", "1", "Ambient")
                type_ok = "c" in stype or "steel" in stype
                press_ok = "1" in press or "ambient" in press
                temp_ok = "4" in temp or "ambient" in temp

                if type_ok and press_ok and temp_ok:
                    bunker_correct = True

        if not has_old:
            old_loc_pts += 10
        if has_new:
            new_loc_pts += 10
        if not bunker_correct:
            conditions_correct = False

    score += old_loc_pts
    feedback.append(f"Old Location Deletion: {old_loc_pts}/30 points")

    score += new_loc_pts
    feedback.append(f"New Location Addition: {new_loc_pts}/30 points")

    if conditions_correct and new_loc_pts == 30:
        score += 20
        feedback.append("Correct Storage Conditions: Passed (+20)")
    else:
        feedback.append("Correct Storage Conditions: Failed (0/20)")

    # 4. Data Integrity - Check distractor
    distractor = chemicals_map.get("7664-93-9")  # Sulfuric Acid
    distractor_ok = False
    if distractor:
        locs = get_descendants(distractor, "StorageLocation")
        for loc in locs:
            desc_nodes = get_descendants(loc, "LocationDescription")
            desc = desc_nodes[0].text.strip().lower() if desc_nodes and desc_nodes[0].text else ""
            if "shed c" in desc:
                distractor_ok = True
                break

    if distractor_ok:
        score += 10
        feedback.append("Data Integrity: Passed (+10)")
    else:
        feedback.append("Data Integrity: Failed (Distractor chemical missing or modified) (0/10)")

    pass_threshold = metadata.get("pass_threshold", 80)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }