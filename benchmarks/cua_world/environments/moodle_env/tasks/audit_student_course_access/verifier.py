#!/usr/bin/env python3
"""
Verifier for Audit Student Course Access task.
Checks:
1. Excel evidence file exists and is valid.
2. Excel file contains key strings ("Jane Smith", "BIO101" or "Introduction to Biology").
3. Verdict file exists and contains "CONFIRMED".
4. Files were created during the task.
"""

import json
import os
import tempfile
import logging
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_student_course_access(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_verdict = metadata.get('expected_verdict', 'CONFIRMED')
    target_student = metadata.get('target_student_name', 'Jane Smith')
    target_course = metadata.get('target_course_shortname', 'BIO101')

    # Load result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback = []

    # Criteria 1: Evidence File Exists & Fresh (30 pts)
    evidence_exists = result.get("evidence_exists", False)
    evidence_fresh = result.get("evidence_fresh", False)
    evidence_path_tmp = result.get("evidence_path_tmp", "")

    if evidence_exists and evidence_fresh:
        score += 30
        feedback.append("Evidence file created during task.")
    elif evidence_exists:
        score += 10
        feedback.append("Evidence file exists but timestamp is old.")
    else:
        feedback.append("Evidence file not found.")

    # Criteria 2: Verdict File Exists & Correct (30 pts)
    verdict_exists = result.get("verdict_exists", False)
    verdict_content = result.get("verdict_content", "").strip().upper()
    verdict_fresh = result.get("verdict_fresh", False)

    if verdict_exists and verdict_fresh:
        if expected_verdict in verdict_content:
            score += 30
            feedback.append(f"Verdict correct: {verdict_content}")
        else:
            score += 10 # Credit for creating file
            feedback.append(f"Verdict incorrect: got '{verdict_content}', expected '{expected_verdict}'")
    elif verdict_exists:
        feedback.append("Verdict file exists but is old.")
    else:
        feedback.append("Verdict file not found.")

    # Criteria 3: Content Verification of Excel File (40 pts)
    # We check if the student name and course name appear in the shared strings of the XLSX
    content_verified = False
    if evidence_exists and evidence_path_tmp:
        temp_xlsx = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        try:
            copy_from_env(evidence_path_tmp, temp_xlsx.name)
            
            # Simple XLSX validation: It's a zip file containing 'xl/sharedStrings.xml' or 'xl/worksheets/sheet1.xml'
            if zipfile.is_zipfile(temp_xlsx.name):
                try:
                    with zipfile.ZipFile(temp_xlsx.name, 'r') as z:
                        # Search in sharedStrings (where Excel stores repeated text)
                        # and sheet1.xml (inline strings)
                        found_student = False
                        found_course = False
                        
                        # Read relevant XML files content into one big string for loose searching
                        search_content = ""
                        for file_in_zip in z.namelist():
                            if file_in_zip.endswith('.xml'):
                                search_content += str(z.read(file_in_zip))
                        
                        if target_student in search_content:
                            found_student = True
                        if target_course in search_content or "Introduction to Biology" in search_content:
                            found_course = True
                        
                        if found_student and found_course:
                            score += 40
                            content_verified = True
                            feedback.append("Evidence file content verified (Student and Course found).")
                        elif found_student:
                            score += 20
                            feedback.append("Evidence file contains Student name but Course name not found.")
                        elif found_course:
                            score += 20
                            feedback.append("Evidence file contains Course name but Student name not found.")
                        else:
                            feedback.append("Evidence file appears valid but target data not found.")
                            
                except Exception as e:
                    feedback.append(f"Failed to parse XLSX: {e}")
            else:
                feedback.append("Evidence file is not a valid ZIP/XLSX.")
                
        except Exception as e:
            feedback.append(f"Failed to retrieve/verify XLSX content: {e}")
        finally:
            if os.path.exists(temp_xlsx.name):
                os.unlink(temp_xlsx.name)

    passed = (score >= 70) and content_verified and (expected_verdict in verdict_content)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }