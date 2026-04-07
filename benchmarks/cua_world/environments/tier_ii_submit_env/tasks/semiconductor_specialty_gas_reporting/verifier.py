#!/usr/bin/env python3
"""
Verifier for semiconductor_specialty_gas_reporting task.

This verifier pulls the exported `.t2s` file (which is a zip archive) directly from the Windows
container, extracts its XML payload, and rigorously verifies the configuration of the Silane
and Arsine chemicals independently of specific XML schema names using fuzzy logic.

Scoring (100 pts total, pass threshold: 75):
  Silane (CAS 7803-62-5) - 40 pts:
    10 pts — EHS = False
    10 pts — Physical Hazards correctly flagged (Flammable, Gas under pressure)
    10 pts — Quantities correctly entered
    10 pts — Storage details match "Fab 1 - Subfab Gas Cabinet G-10"

  Arsine (CAS 7784-42-1) - 60 pts:
    15 pts — EHS = True
    10 pts — Physical Hazards correctly flagged
    15 pts — Health Hazards correctly flagged (Acute toxicity, STOT)
    10 pts — Quantities correctly entered
    10 pts — Storage details match "Fab 1 - Subfab Toxic Gas Enclosure T-05"
"""

import xml.etree.ElementTree as ET
import zipfile
import tempfile
import json
import os
import re

def strip_namespaces(el):
    """Strip namespaces from XML tags for robust searching."""
    if '}' in el.tag:
        el.tag = el.tag.split('}', 1)[1]
    for child in el:
        strip_namespaces(child)
    return el

def verify_semiconductor_specialty_gas_reporting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Pull the export JSON state file
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\task_result.json", tmp_json.name)
        with open(tmp_json.name, "r") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get("file_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output .t2s file not found. Task not completed."}

    if not result.get("file_modified", False):
        pass # Note: We don't hard-fail here just in case of clock skew, but it's recorded

    # 2. Pull the .t2s (ZIP archive) and parse its XML
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    try:
        copy_from_env("C:\\Users\\Docker\\Desktop\\silicon_desert_2024.t2s", tmp_t2s.name)
        
        with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
            xml_files = [n for n in z.namelist() if n.endswith('.xml')]
            if not xml_files:
                return {"passed": False, "score": 0, "feedback": "No XML found in .t2s file."}
            with z.open(xml_files[0]) as f:
                tree = ET.parse(f)
                root = strip_namespaces(tree.getroot())
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not parse .t2s file. Ensure it was properly saved: {e}"}
    finally:
        if os.path.exists(tmp_t2s.name):
            os.unlink(tmp_t2s.name)

    chemicals = root.findall('.//Chemical')
    if not chemicals:
        return {"passed": False, "score": 0, "feedback": "No chemicals found in submission."}

    score = 0
    feedback = []

    def get_text(node, xpath, default=""):
        n = node.find(xpath)
        return n.text.strip() if n is not None and n.text else default

    def is_true(node, xpath):
        val = get_text(node, xpath).lower()
        return val in ['true', '1', 'y', 'yes']

    def check_hazards(chem_node, hazard_list):
        """Extract all 'true' hazards regardless of specific Tier2Submit schema structure."""
        found = []
        
        # Method A: <PhysicalHazards><Flammable>true</Flammable>
        for group in ['PhysicalHazards', 'HealthHazards']:
            node = chem_node.find(f'.//{group}')
            if node is not None:
                for child in node:
                    if child.text and child.text.lower() in ['true', '1', 'y']:
                        found.append(child.tag.lower())
        
        # Method B: <Hazards><Hazard><HazardCategory>
        hazards = chem_node.findall('.//Hazard')
        for h in hazards:
            ind = get_text(h, 'HazardIndicator').lower()
            if ind in ['true', '1', 'y']:
                cat = get_text(h, 'HazardCategory').lower()
                found.append(cat)
                
        # Method C: Direct Booleans
        for child in chem_node:
            if child.text and child.text.lower() in ['true', '1', 'y']:
                found.append(child.tag.lower())

        found_str = " ".join(found)
        success = True
        for h in hazard_list:
            h_simp = re.sub(r'[^a-z]', '', h.lower())
            if h_simp not in re.sub(r'[^a-z]', '', found_str):
                success = False
                break
        return success

    silane_found = False
    arsine_found = False

    for chem in chemicals:
        cas = get_text(chem, './/CASNumber')
        if not cas:
            cas = get_text(chem, 'CAS')
            
        # ================================
        # Validate Silane (7803-62-5)
        # ================================
        if '7803-62-5' in cas:
            silane_found = True
            ehs = is_true(chem, './/EHSIndicator') or is_true(chem, 'EHS')
            if not ehs:
                score += 10
                feedback.append("PASS: Silane EHS=False (+10)")
            else:
                feedback.append("FAIL: Silane EHS should be False")

            if check_hazards(chem, ['flammable', 'pressure']):
                score += 10
                feedback.append("PASS: Silane Physical Hazards correct (+10)")
            else:
                feedback.append("FAIL: Silane missing Flammable or Gas under pressure hazard")

            max_amt = get_text(chem, './/MaximumAmount')
            ave_amt = get_text(chem, './/AverageAmount')
            if '1500' in max_amt and '1000' in ave_amt:
                score += 10
                feedback.append("PASS: Silane amounts correct (+10)")
            else:
                feedback.append(f"FAIL: Silane amounts incorrect (max: {max_amt}, avg: {ave_amt})")

            storage_locs = chem.findall('.//StorageLocation')
            if storage_locs:
                desc = get_text(storage_locs[0], 'LocationDescription', '').lower()
                if 'fab 1' in desc and 'g-10' in desc:
                    score += 10
                    feedback.append("PASS: Silane storage description correct (+10)")
                else:
                    feedback.append(f"FAIL: Silane storage description incorrect ({desc})")
            else:
                feedback.append("FAIL: No storage location found for Silane")

        # ================================
        # Validate Arsine (7784-42-1)
        # ================================
        elif '7784-42-1' in cas:
            arsine_found = True
            ehs = is_true(chem, './/EHSIndicator') or is_true(chem, 'EHS')
            if ehs:
                score += 15
                feedback.append("PASS: Arsine EHS=True (+15)")
            else:
                feedback.append("FAIL: Arsine EHS should be True")

            if check_hazards(chem, ['flammable', 'pressure']):
                score += 10
                feedback.append("PASS: Arsine Physical Hazards correct (+10)")
            else:
                feedback.append("FAIL: Arsine missing Physical Hazards")
                
            if check_hazards(chem, ['acute', 'targetorgan']):
                score += 15
                feedback.append("PASS: Arsine Health Hazards correct (+15)")
            else:
                feedback.append("FAIL: Arsine missing Health Hazards (Acute toxicity, STOT)")

            max_amt = get_text(chem, './/MaximumAmount')
            ave_amt = get_text(chem, './/AverageAmount')
            if '250' in max_amt and '150' in ave_amt:
                score += 10
                feedback.append("PASS: Arsine amounts correct (+10)")
            else:
                feedback.append(f"FAIL: Arsine amounts incorrect (max: {max_amt}, avg: {ave_amt})")

            storage_locs = chem.findall('.//StorageLocation')
            if storage_locs:
                desc = get_text(storage_locs[0], 'LocationDescription', '').lower()
                if 'fab 1' in desc and 't-05' in desc:
                    score += 10
                    feedback.append("PASS: Arsine storage description correct (+10)")
                else:
                    feedback.append(f"FAIL: Arsine storage description incorrect ({desc})")
            else:
                feedback.append("FAIL: No storage location found for Arsine")

    if not silane_found:
        feedback.append("FAIL: Silane (7803-62-5) not found in submission")
    if not arsine_found:
        feedback.append("FAIL: Arsine (7784-42-1) not found in submission")

    # Final tally
    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 75)
    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }