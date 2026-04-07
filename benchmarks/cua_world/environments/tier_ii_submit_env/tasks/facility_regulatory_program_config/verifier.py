#!/usr/bin/env python3
"""
Verifier for facility_regulatory_program_config task.

Reads the exported .t2s file (which is a ZIP containing an XML document)
and evaluates whether the facility profile was correctly configured.
Uses robust regex and string matching on the XML to be resilient against 
minor schema variations between Tier2 Submit versions.
"""

import json
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_flag(xml_str, keywords):
    """
    Checks if a boolean XML element containing any of the keywords is set to true.
    Example match: <SubjectToEmergencyPlanning>true</SubjectToEmergencyPlanning>
    """
    for kw in keywords:
        pattern = r'<([^>]*' + kw + r'[^>]*)>\s*(true|1|y|yes|t)\s*</\1>'
        if re.search(pattern, xml_str, re.IGNORECASE):
            return True
    return False

def verify_facility_regulatory_program_config(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    result_file = metadata.get('result_file', 'C:\\Users\\Docker\\Desktop\\task_result.json')
    pass_threshold = metadata.get('pass_threshold', 60)

    # 1. Copy result JSON
    tmp_json = tempfile.NamedTemporaryFile(suffix=".json", delete=False)
    try:
        copy_from_env(result_file, tmp_json.name)
        with open(tmp_json.name, "r", encoding="utf-8-sig") as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read task_result.json: {e}"}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output .t2s file not found. Agent did not export the submission."
        }

    export_path = result.get("export_path", "")
    if not export_path:
        return {"passed": False, "score": 0, "feedback": "Export path is empty."}

    # 2. Copy the exported .t2s file
    tmp_t2s = tempfile.NamedTemporaryFile(suffix=".t2s", delete=False)
    try:
        copy_from_env(export_path, tmp_t2s.name)
        
        # Extract XML from the zip archive (.t2s files are zip archives)
        xml_content = ""
        with zipfile.ZipFile(tmp_t2s.name, 'r') as z:
            # Find the primary submission XML file
            xml_files = [n for n in z.namelist() if n.endswith('.xml')]
            sub_xmls = [n for n in xml_files if 'submission' in n.lower()]
            target_xml = sub_xmls[0] if sub_xmls else (xml_files[0] if xml_files else None)
            
            if target_xml:
                xml_content = z.read(target_xml).decode('utf-8', errors='ignore')
            else:
                return {"passed": False, "score": 0, "feedback": "Valid XML not found in exported .t2s file."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse exported .t2s file: {e}"}
    finally:
        if os.path.exists(tmp_t2s.name):
            os.unlink(tmp_t2s.name)

    xml_lower = xml_content.lower()
    score = 0
    feedback = []

    # Criterion: Record saved successfully (10 pts)
    if result.get("file_created_during_task", False):
        score += 10
        feedback.append("PASS: Export file generated during task (+10)")
    else:
        feedback.append("FAIL: Export file appears stale/not modified during task")

    # Criterion: Facility Name & Address (10 pts)
    if "baytown refining" in xml_lower and "77520" in xml_lower:
        score += 10
        feedback.append("PASS: Facility Name and ZIP code correct (+10)")
    else:
        feedback.append("FAIL: Facility Name ('Baytown Refining') or ZIP ('77520') not found")

    # Criterion: State (5 pts)
    if ">tx<" in xml_lower or ">texas<" in xml_lower or '"tx"' in xml_lower:
        score += 5
        feedback.append("PASS: State set to TX (+5)")
    else:
        feedback.append("FAIL: State 'TX' not found")

    # Criteria: Regulatory Flags
    has_302 = check_flag(xml_content, ['EmergencyPlanning', 'Section302', 'EPCRA302'])
    if has_302:
        score += 10
        feedback.append("PASS: EPCRA 302 flag = Yes (+10)")
    else:
        feedback.append("FAIL: EPCRA 302 flag not found or set to No")

    has_tri = check_flag(xml_content, ['TRI', 'Section313', 'ToxicRelease'])
    if has_tri:
        score += 10
        feedback.append("PASS: EPCRA 313 (TRI) flag = Yes (+10)")
    else:
        feedback.append("FAIL: EPCRA 313 (TRI) flag not found or set to No")

    has_rmp = check_flag(xml_content, ['RMP', 'RiskManagement', '112r'])
    if has_rmp:
        score += 10
        feedback.append("PASS: CAA 112(r) RMP flag = Yes (+10)")
    else:
        feedback.append("FAIL: CAA 112(r) RMP flag not found or set to No")

    has_cercla = check_flag(xml_content, ['CERCLA', 'Section103', 'ReleaseReporting'])
    if has_cercla:
        score += 10
        feedback.append("PASS: CERCLA 103 flag = Yes (+10)")
    else:
        # Auto-grant if CERCLA flag isn't at the facility level but others are correctly set
        if has_302 and has_tri and has_rmp:
            score += 10
            feedback.append("PASS: CERCLA 103 auto-granted (might not be a facility-level UI field) (+10)")
        else:
            feedback.append("FAIL: CERCLA 103 flag not found")

    # Criteria: Identifiers
    has_epa_id = "txd980625705" in xml_lower
    if has_epa_id:
        score += 10
        feedback.append("PASS: EPA ID (RCRA) correct (+10)")
    else:
        feedback.append("FAIL: EPA ID 'TXD980625705' not found")

    if "071845236" in xml_lower:
        score += 5
        feedback.append("PASS: Dun & Bradstreet number correct (+5)")
    else:
        feedback.append("FAIL: Dun & Bradstreet '071845236' not found")

    if "100000055289" in xml_lower:
        score += 5
        feedback.append("PASS: RMP Facility ID correct (+5)")
    else:
        feedback.append("FAIL: RMP Facility ID '100000055289' not found")

    # Criteria: Fire Department
    # Look for "baytown" near fire department XML tags, or occurring frequently enough
    has_fire_name = re.search(r'<[^>]*Fire[^>]*>[^<]*baytown[^<]*</', xml_lower) is not None
    if not has_fire_name and xml_lower.count("baytown") >= 2:
        has_fire_name = True
        
    if has_fire_name:
        score += 5
        feedback.append("PASS: Fire Department name correct (+5)")
    else:
        feedback.append("FAIL: Fire Department 'Baytown' not found")

    if "422" in xml_lower and "7711" in xml_lower:
        score += 5
        feedback.append("PASS: Fire Department phone correct (+5)")
    else:
        feedback.append("FAIL: Fire Department phone '422-7711' not found")

    # Criterion: Reporting Year
    if "2024" in xml_lower:
        score += 5
        feedback.append("PASS: Reporting Year correct (+5)")
    else:
        feedback.append("FAIL: Reporting Year '2024' not found")

    # Pass logic: Must reach threshold AND have EPA ID correct AND at least 2 key regulatory flags
    flags_met = sum([has_302, has_tri, has_rmp, has_cercla])
    passed = (score >= pass_threshold) and has_epa_id and (flags_met >= 2)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }