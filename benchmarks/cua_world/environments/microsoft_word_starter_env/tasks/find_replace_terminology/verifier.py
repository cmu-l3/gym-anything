#!/usr/bin/env python3
"""
Verifier for find_replace_terminology task.

Criteria:
1. File exists and was created during task (anti-gaming).
2. "disaster recovery" (case-insensitive) replaced with "Disaster Recovery".
3. "BCP" replaced with "Business Continuity Plan".
4. Double spaces replaced with single spaces.
5. "e-mail" replaced with "email".
6. "back-up" replaced with "backup".
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

def verify_find_replace_terminology(traj, env_info, task_info):
    """
    Verifies that the agent correctly used Find and Replace to standardize the document.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check 1: File Existence & Timestamp (10 points)
    if not result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file 'DR_Plan_Final.docx' not found."}
    
    if not result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified/created during the task."}

    # Copy the output document for content analysis
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')
    docx_path = temp_docx.name
    temp_docx.close()

    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\DR_Plan_Final.docx", docx_path)
        
        if not zipfile.is_zipfile(docx_path):
            return {"passed": False, "score": 10, "feedback": "Output file exists but is not a valid DOCX file."}
        
        # Extract text from document.xml
        text_content = ""
        with zipfile.ZipFile(docx_path, 'r') as zf:
            if 'word/document.xml' in zf.namelist():
                xml_content = zf.read('word/document.xml').decode('utf-8')
                # Simple XML tag stripping to get text
                text_content = re.sub(r'<[^>]+>', '', xml_content)
            else:
                return {"passed": False, "score": 10, "feedback": "Invalid DOCX structure: missing word/document.xml"}

    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to analyze document content: {str(e)}"}
    finally:
        if os.path.exists(docx_path):
            os.unlink(docx_path)

    # Scoring content
    score = 10 # Base score for file existing
    feedback = ["File created successfully."]
    
    # Check 2: "Disaster Recovery" standardization (20 points)
    # Failure if we find "disaster recovery" (lower/mixed) that ISN'T "Disaster Recovery"
    # Or if we just check for presence of bad forms
    
    # Check for bad forms
    bad_dr = re.search(r'disaster recovery', text_content, re.IGNORECASE)
    # Ensure what we found matches specific bad casing. 
    # Actually, simpler: Check that ALL instances match 'Disaster Recovery'
    # Count total case-insensitive matches vs correct matches
    dr_matches = re.findall(r'disaster recovery', text_content, re.IGNORECASE)
    dr_correct = re.findall(r'Disaster Recovery', text_content)
    
    if len(dr_matches) > 0 and len(dr_matches) == len(dr_correct):
        score += 20
        feedback.append("Term 'Disaster Recovery' standardized.")
    else:
        feedback.append(f"Found {len(dr_matches)-len(dr_correct)} uncorrected instances of 'disaster recovery'.")

    # Check 3: "BCP" -> "Business Continuity Plan" (20 points)
    # "BCP" should NOT exist as a standalone word
    if re.search(r'\bBCP\b', text_content):
        feedback.append("Found standalone 'BCP' abbreviation (should be expanded).")
    else:
        # Check that we actually have "Business Continuity Plan" now
        if "Business Continuity Plan" in text_content:
            score += 20
            feedback.append("Abbreviation 'BCP' expanded correctly.")
        else:
            feedback.append("Abbreviation 'BCP' removed but not expanded correctly.")

    # Check 4: Double spaces (15 points)
    if "  " in text_content:
        feedback.append("Double spaces still detected.")
    else:
        score += 15
        feedback.append("Double spaces removed.")

    # Check 5: "e-mail" -> "email" (15 points)
    if "e-mail" in text_content.lower():
        feedback.append("Term 'e-mail' still found.")
    elif "email" in text_content:
        score += 15
        feedback.append("Term 'e-mail' standardized to 'email'.")
    else:
        # If neither exists, maybe they deleted it?
        feedback.append("Term 'email' missing.")

    # Check 6: "back-up" -> "backup" (10 points)
    if "back-up" in text_content.lower():
        feedback.append("Term 'back-up' still found.")
    elif "backup" in text_content:
        score += 10
        feedback.append("Term 'back-up' standardized to 'backup'.")
    else:
        feedback.append("Term 'backup' missing.")
        
    # Check 7: Content integrity (10 points)
    # Roughly check word count to ensure they didn't just delete everything
    word_count = len(text_content.split())
    if 100 < word_count < 500: # Original is around 200 words
        score += 10
    else:
        feedback.append("Document content significantly altered (length mismatch).")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }