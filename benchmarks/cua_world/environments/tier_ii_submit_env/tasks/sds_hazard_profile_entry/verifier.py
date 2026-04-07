#!/usr/bin/env python3
"""
Verifier for SDS-Based Chemical Hazard Profile Entry task.

Programmatic verification of the exported .t2s (XML) file:
1. File exists and created during task.
2. Phosphoric Acid (CAS 7664-38-2) was added.
3. Identity/state parameters correct.
4. Legacy OSHA hazard flags correctly configured.
5. HCS 2012 GHS hazard categories correctly configured.
6. Inventory values populated.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sds_hazard_profile_entry(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', "C:\\Users\\Docker\\Desktop\\sds_hazard_profile_entry_result.json")
    pass_threshold = metadata.get('pass_threshold', 65)

    # 1. Retrieve the exported JSON result from the environment
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_file, temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Check file existence
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Target .t2s export file was not created."}

    xml_content = result.get('xml_content', '')
    if not xml_content:
        return {"passed": False, "score": 5, "feedback": ".t2s file exists but contains no parseable XML data."}

    score = 10
    feedback = ["Output file exists"]

    # 3. Parse XML content for the target chemical (CAS 7664-38-2)
    # Split document by elements that typically encapsulate a single chemical entry
    chem_blocks = re.split(r'<(?:Chemical|FacilityChemical|ChemicalInventory|ChemDetail)\b', xml_content, flags=re.IGNORECASE)
    
    target_block = None
    for block in chem_blocks:
        if '7664-38-2' in block:
            target_block = block
            break

    if not target_block:
        feedback.append("FAIL: Phosphoric Acid (CAS 7664-38-2) not found in submission")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback)}

    score += 10
    feedback.append("PASS: Chemical CAS 7664-38-2 found")

    # Clean text block for robust substring matching (ignore XML tags)
    text_clean = re.sub(r'<[^>]+>', ' ', target_block).lower()
    text_clean = re.sub(r'\s+', ' ', text_clean)

    # 4. Check Identity and Physical State
    if 'phosphoric acid' in text_clean:
        score += 5
        feedback.append("PASS: Chemical Name correct")
    
    # EHS is tricky, check if <EHS>true</EHS> exists, if not assume False
    if bool(re.search(r'<EHS[^>]*>\s*(true|1|yes)\s*</EHS>', target_block, re.IGNORECASE)):
        feedback.append("FAIL: EHS set to True (Expected False)")
    else:
        score += 5
        feedback.append("PASS: EHS = False")

    if 'liquid' in text_clean:
        score += 5
        feedback.append("PASS: State = Liquid")

    # 5. Check Legacy OSHA Hazards
    legacy_acute = bool(re.search(r'<Acute[^>]*>\s*(true|1|yes)\s*</Acute>', target_block, re.IGNORECASE))
    legacy_chronic = bool(re.search(r'<Chronic[^>]*>\s*(true|1|yes)\s*</Chronic>', target_block, re.IGNORECASE))
    legacy_fire = bool(re.search(r'<Fire[^>]*>\s*(true|1|yes)\s*</Fire>', target_block, re.IGNORECASE))
    legacy_pressure = bool(re.search(r'<Pressure[^>]*>\s*(true|1|yes)\s*</Pressure>', target_block, re.IGNORECASE))
    legacy_reactive = bool(re.search(r'<Reactive[^>]*>\s*(true|1|yes)\s*</Reactive>', target_block, re.IGNORECASE))

    if legacy_acute:
        score += 5
        feedback.append("PASS: Legacy Acute = True")
    else:
        feedback.append("FAIL: Legacy Acute missing")

    if not any([legacy_chronic, legacy_fire, legacy_pressure, legacy_reactive]):
        score += 5
        feedback.append("PASS: Legacy Other Hazards correctly unselected")
    else:
        feedback.append("FAIL: Extra Legacy Hazards improperly selected")

    # 6. Check HCS 2012 GHS Hazards
    ghs_corrosive = 'corrosive to metal' in text_clean
    ghs_acute_tox = 'acute toxicity' in text_clean
    ghs_skin_corr = 'skin corrosion' in text_clean
    ghs_eye_dam = 'serious eye damage' in text_clean or 'eye irritation' in text_clean
    ghs_stot_se = 'single exposure' in text_clean or 'stot-se' in text_clean
    
    # Negative checks
    ghs_flammable = 'flammable' in text_clean
    ghs_carcinogen = 'carcinogen' in text_clean
    ghs_mutagen = 'mutagen' in text_clean
    ghs_reproductive = 'reproductive' in text_clean
    
    if ghs_corrosive:
        score += 10
        feedback.append("PASS: GHS Corrosive to Metal = True")
    else:
        feedback.append("FAIL: Missing GHS Corrosive to Metal")

    health_hazards_count = 0
    if ghs_acute_tox: health_hazards_count += 1
    if ghs_skin_corr: health_hazards_count += 1
    if ghs_eye_dam: health_hazards_count += 1
    if ghs_stot_se: health_hazards_count += 1
    
    score += (health_hazards_count * 5)
    feedback.append(f"PASS: {health_hazards_count}/4 GHS Health Hazards correct")

    if not any([ghs_flammable, ghs_carcinogen, ghs_mutagen, ghs_reproductive]):
        score += 10
        feedback.append("PASS: Unrelated GHS Hazards correctly unselected")
    else:
        feedback.append("FAIL: False positive GHS Hazards detected")

    # 7. Check Inventory Quantities
    if re.search(r'75\s*,?\s*000', text_clean):
        score += 5
        feedback.append("PASS: Max Amount = 75000")
    if re.search(r'50\s*,?\s*000', text_clean):
        score += 5
        feedback.append("PASS: Ave Amount = 50000")
    if re.search(r'365', text_clean):
        score += 5
        feedback.append("PASS: Days on site = 365")

    passed = score >= pass_threshold
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }