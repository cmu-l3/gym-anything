#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_export_patient_ccda(traj, env_info, task_info):
    """
    Verifies that the agent exported the correct C-CDA/CCR XML file.
    1. File existence and validity checks (Primary)
    2. XML content verification (Patient name match)
    3. VLM trajectory verification (Workflow check)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Initialize scoring
    score = 0
    feedback = []
    max_score = 100
    
    # 1. Retrieve Task Result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=True) as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            tmp.seek(0)
            task_result = json.load(tmp)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}

    target_patient = task_result.get("target_patient", {})
    expected_fname = target_patient.get("fname", "").lower()
    expected_lname = target_patient.get("lname", "").lower()

    # 2. Check File Existence and Creation Time (30 pts)
    if not task_result.get("file_exists"):
        feedback.append("Export file not found at expected location.")
    else:
        score += 15
        if task_result.get("file_created_during_task"):
            score += 15
            feedback.append("New export file created successfully.")
        else:
            feedback.append("Export file exists but was not modified during task (stale data).")

    # 3. Content Verification (XML Parsing) (40 pts)
    # We need to copy the actual XML file out to verify its content
    xml_content_valid = False
    patient_match = False
    
    if task_result.get("file_exists"):
        with tempfile.NamedTemporaryFile(delete=True, suffix=".xml") as xml_tmp:
            try:
                copy_from_env("/home/ga/Documents/Transfer/export.xml", xml_tmp.name)
                xml_tmp.seek(0)
                
                # Parse XML
                try:
                    tree = ET.parse(xml_tmp.name)
                    root = tree.getroot()
                    xml_content_valid = True
                    score += 20  # Valid XML format
                    feedback.append("File is valid XML.")
                    
                    # Search for patient name in standard C-CDA/CCR locations
                    # Namespace handling can be tricky, so we'll convert to string and search text 
                    # or search recursively ignoring namespaces for simplicity in this context
                    xml_str = ET.tostring(root, encoding='utf8', method='xml').decode().lower()
                    
                    if expected_fname in xml_str and expected_lname in xml_str:
                        patient_match = True
                        score += 20
                        feedback.append(f"Correct patient ({expected_fname} {expected_lname}) found in XML.")
                    else:
                        feedback.append(f"XML does not contain expected patient name: {expected_fname} {expected_lname}.")
                        
                except ET.ParseError:
                    feedback.append("File is not valid XML.")
            except Exception as e:
                feedback.append(f"Error checking XML content: {str(e)}")

    # 4. VLM Verification (30 pts)
    # Check if agent navigated to report/export section
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        final_screen = get_final_screenshot(traj)
        
        # Prompt checking for workflow steps
        prompt = (
            "Analyze these screenshots of an Electronic Health Record system. "
            "Did the user: "
            "1. Search for a patient? "
            "2. Navigate to a 'Reports', 'Export', 'CCR', or 'C-CDA' section? "
            "3. Initiate a download or save action? "
            "Provide a score from 0 to 30 based on evidence of these steps."
        )
        
        vlm_result = query_vlm(images=frames + [final_screen], prompt=prompt)
        
        # Simple heuristic parsing of VLM score (assuming VLM returns a number or we infer success)
        # For robustness, we'll assume the VLM returns a JSON or text we can parse.
        # Here we'll default to a pass/fail check if score parsing is complex.
        if "CCR" in str(vlm_result) or "export" in str(vlm_result).lower():
            vlm_score = 30
        else:
            vlm_score = 10 # Give some points for effort if screenshots exist
            
        score += vlm_score
        feedback.append(f"VLM Workflow Analysis: {vlm_score}/30 points.")
        
    except Exception as e:
        feedback.append(f"VLM verification skipped due to error: {str(e)}")
        # Fallback: if XML is valid and correct, give full points regardless of VLM
        if xml_content_valid and patient_match:
            score += 30

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " ".join(feedback)
    }