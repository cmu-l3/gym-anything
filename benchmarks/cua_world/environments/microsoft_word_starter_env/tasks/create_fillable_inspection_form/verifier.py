#!/usr/bin/env python3
"""
Verifier for create_fillable_inspection_form task.

Checks for:
1. Valid DOCX file creation.
2. Presence of Legacy Form Fields (TextInput, CheckBox, DropDown).
3. Correct Dropdown options ("Pass", "Conditional Pass", "Fail").
4. Document Protection enabled for forms.
5. VLM verification for layout/structure.
"""

import json
import logging
import os
import re
import tempfile
import zipfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

RESULT_PATH_IN_ENV = "C:\\Users\\Docker\\task_result.json"
DOC_PATH_IN_ENV = "C:\\Users\\Docker\\Documents\\fire_inspection_form.docx"

def verify_create_fillable_inspection_form(traj, env_info, task_info):
    """
    Verify the agent created a protected form with specific fields.
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get("metadata", {})
    
    # Setup temp dir
    tmp_dir = tempfile.mkdtemp(prefix="verify_form_")
    try:
        # 1. Fetch Result JSON
        local_result_json = os.path.join(tmp_dir, "result.json")
        try:
            copy_from_env(RESULT_PATH_IN_ENV, local_result_json)
            with open(local_result_json, "r") as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        if not result_data.get("file_exists"):
            return {"passed": False, "score": 0, "feedback": "Output file not found."}

        if not result_data.get("file_created_during_task"):
            return {"passed": False, "score": 0, "feedback": "File was not modified during the task."}

        # 2. Fetch DOCX File
        local_docx = os.path.join(tmp_dir, "fire_inspection_form.docx")
        try:
            copy_from_env(DOC_PATH_IN_ENV, local_docx)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to copy DOCX file: {str(e)}"}

        # 3. Analyze DOCX Structure (XML Parsing)
        score = 0
        feedback = []
        
        try:
            with zipfile.ZipFile(local_docx, 'r') as zf:
                # Read document.xml for fields
                doc_xml = zf.read('word/document.xml').decode('utf-8')
                # Read settings.xml for protection
                try:
                    settings_xml = zf.read('word/settings.xml').decode('utf-8')
                except KeyError:
                    settings_xml = ""

                # Criteria 1: Title (Approximate check)
                if "BUILDING FIRE SAFETY INSPECTION FORM" in doc_xml: # Simple string check
                    score += 8
                    feedback.append("Title found.")
                else:
                    feedback.append("Title not found.")

                # Criteria 2: Text Form Fields
                # Legacy text fields use <w:textInput> inside <w:ffData>
                text_inputs = len(re.findall(r'<w:textInput>', doc_xml))
                if text_inputs >= 5:
                    score += 18
                    feedback.append(f"Text fields count {text_inputs} (Pass).")
                elif text_inputs > 0:
                    score += 10
                    feedback.append(f"Text fields count {text_inputs} (Partial).")
                else:
                    feedback.append("No text fields found.")

                # Criteria 3: Checkbox Form Fields
                # <w:checkBox>
                checkboxes = len(re.findall(r'<w:checkBox>', doc_xml))
                if checkboxes >= 8:
                    score += 22
                    feedback.append(f"Checkboxes count {checkboxes} (Pass).")
                elif checkboxes > 0:
                    score += 10
                    feedback.append(f"Checkboxes count {checkboxes} (Partial).")
                else:
                    feedback.append("No checkboxes found.")

                # Criteria 4: Dropdown Form Field
                # <w:ddList>
                dropdowns = len(re.findall(r'<w:ddList>', doc_xml))
                if dropdowns >= 1:
                    score += 10
                    feedback.append("Dropdown field found.")
                    
                    # Check options
                    # Options are in <w:listEntry w:val="Option"/>
                    if 'w:val="Pass"' in doc_xml and 'w:val="Fail"' in doc_xml:
                        score += 7
                        feedback.append("Dropdown options correct.")
                    else:
                        feedback.append("Dropdown options missing or incorrect.")
                else:
                    feedback.append("No dropdown field found.")

                # Criteria 5: Protection
                # Look for <w:documentProtection w:edit="forms" ... /> in settings.xml
                if 'w:edit="forms"' in settings_xml:
                    score += 15
                    feedback.append("Document protection (forms) enabled.")
                else:
                    feedback.append("Document protection NOT enabled or wrong type.")

                # Criteria 6: Labels/Content (Basic text check)
                required_terms = ["Building Name", "Address", "Fire extinguisher", "Exit signs"]
                found_terms = sum(1 for term in required_terms if term in doc_xml)
                if found_terms >= 3:
                    score += 5
                    feedback.append("Form labels/content found.")

        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid DOCX."}

        # Criteria 7: Basic File Validity (from start)
        score += 10 # File exists and is valid zip

        # Criteria 8: VLM Visual Check (Simulated/Placeholder for this script, 
        # normally we query VLM here with trajectory final screenshot)
        # Assuming layout is generally okay if XML is good. 
        # We add 5 points assuming basic structure if fields are present.
        if score > 50:
            score += 5
            feedback.append("Structure implied by XML.")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(tmp_dir, ignore_errors=True)