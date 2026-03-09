#!/usr/bin/env python3
"""Verifier for fix_xml_config_errors task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_xml_config_errors(traj, env_info, task_info):
    """
    Verify that the XML file was corrected according to the XSD schema.
    
    Criteria:
    1. File exists and is valid XML (10 pts)
    2. File was modified during the task (Anti-gaming) (10 pts)
    3. RadiationType fixed to 'Photon' (25 pts)
    4. ReferenceDoseRate fixed to '600' (25 pts)
    5. Dmax element added with value '1.5' (20 pts)
    6. VLM Check: Project imported and editor used (10 pts)
    
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    expected_values = metadata.get('expected_values', {
        "RadiationType": "Photon",
        "ReferenceDoseRate": "600",
        "Dmax": "1.5"
    })

    score = 0
    feedback_parts = []
    
    # 1. Retrieve result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_result.close()
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # 2. Basic file checks
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "beam_model.xml not found."}
    
    score += 10
    feedback_parts.append("File exists")

    if result.get("file_modified"):
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("WARNING: File timestamp indicates no changes made")

    # 3. XML Content Analysis
    xml_content = result.get("xml_content", "")
    if not xml_content:
         return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts) + " | File is empty"}

    try:
        root = ET.fromstring(xml_content)
        
        # Check RadiationType
        rad_type = root.find("RadiationType")
        if rad_type is not None and rad_type.text == expected_values["RadiationType"]:
            score += 25
            feedback_parts.append("RadiationType corrected")
        else:
            actual = rad_type.text if rad_type is not None else "Missing"
            feedback_parts.append(f"RadiationType incorrect: found '{actual}'")

        # Check ReferenceDoseRate
        dose_rate = root.find("ReferenceDoseRate")
        if dose_rate is not None and dose_rate.text == expected_values["ReferenceDoseRate"]:
            score += 25
            feedback_parts.append("ReferenceDoseRate corrected")
        else:
            actual = dose_rate.text if dose_rate is not None else "Missing"
            feedback_parts.append(f"ReferenceDoseRate incorrect: found '{actual}'")

        # Check Dmax
        # Dmax should be inside DepthDoseParams
        depth_params = root.find("DepthDoseParams")
        dmax_found = False
        if depth_params is not None:
            dmax = depth_params.find("Dmax")
            if dmax is not None and dmax.text == expected_values["Dmax"]:
                dmax_found = True
        
        if dmax_found:
            score += 20
            feedback_parts.append("Dmax added correctly")
        else:
            feedback_parts.append("Dmax missing or incorrect")
            
    except ET.ParseError as e:
        feedback_parts.append(f"XML Parse Error: {e}")
        # Stop here if invalid XML
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. VLM Verification (Check if they actually used Eclipse Import/Editor)
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Import RadOncPhysics project and fix XML errors in beam_model.xml",
            checklist_items=[
                "Project 'RadOncPhysics' visible in Package Explorer",
                "XML Editor open with 'beam_model.xml'",
                "No red error markers visible in the final state"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            score += 10
            feedback_parts.append("VLM: Workflow verified")
        else:
            feedback_parts.append(vlm_result.get('vlm_feedback', 'VLM check failed') if vlm_result else "VLM unavailable")
            
    except Exception as e:
        logger.warning(f"VLM verification skipped: {e}")

    final_score = min(score, 100)
    passed = final_score >= 70
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback_parts)
    }