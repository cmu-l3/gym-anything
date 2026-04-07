#!/usr/bin/env python3
"""
Verifier for generate_absence_report task.

Criteria:
1. PDF File Creation (Time/Existence)
2. PDF Validity
3. Content Analysis:
   - Must contain absent students (Cameron Frye, Ferris Bueller)
   - Must NOT contain present student (Hermione Granger)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Import PDF extraction tool if available, else simple binary check
try:
    from pdfminer.high_level import extract_text
    PDFMINER_AVAILABLE = True
except ImportError:
    PDFMINER_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_absence_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy missing"}

    metadata = task_info.get('metadata', {})
    expected_absent = metadata.get('absent_students', ["Cameron Frye", "Ferris Bueller"])
    expected_present = metadata.get('present_students', ["Hermione Granger"])

    # 1. Retrieve Result JSON
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
    
    # Check 1: File Existence & Timestamp (20 pts)
    file_path = result.get("file_path", "")
    created_during = result.get("created_during_task", False)
    
    if file_path and created_during:
        score += 20
        feedback.append("New PDF report generated.")
    elif file_path:
        # File exists but timestamp issue (maybe updated old file?)
        score += 10
        feedback.append("PDF report found, but timestamp is ambiguous.")
    else:
        return {"passed": False, "score": 0, "feedback": "No PDF report output found created during the task."}

    # 2. Retrieve the PDF file for content analysis
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        # The export script copies the found file to /tmp/exported_report.pdf
        copy_from_env("/tmp/exported_report.pdf", temp_pdf.name)
        
        # Check 2: PDF Validity (20 pts)
        # Simple check: file signature
        with open(temp_pdf.name, 'rb') as f:
            header = f.read(4)
        if header == b'%PDF':
            score += 20
            feedback.append("File is a valid PDF.")
        else:
            return {"passed": False, "score": score, "feedback": f"{feedback} File is not a valid PDF."}

        # Check 3: Content Extraction (60 pts split)
        pdf_text = ""
        if PDFMINER_AVAILABLE:
            try:
                pdf_text = extract_text(temp_pdf.name)
            except Exception as e:
                logger.error(f"PDF extraction failed: {e}")
                pdf_text = "" # Fallback
        
        # Fallback if miner fails or not installed: binary search (unreliable for compressed streams but better than nothing)
        if not pdf_text:
            with open(temp_pdf.name, 'rb') as f:
                raw_content = f.read().decode('latin-1') # wide decode
                pdf_text = raw_content

        # normalize
        pdf_text_norm = pdf_text.lower()
        
        # Verify Absent Students (20 pts each)
        for student in expected_absent:
            # Check full name or "Last, First"
            parts = student.lower().split()
            first = parts[0]
            last = parts[1]
            
            if student.lower() in pdf_text_norm or (f"{last}, {first}" in pdf_text_norm) or (f"{last},{first}" in pdf_text_norm):
                score += 20
                feedback.append(f"Found absent student: {student}.")
            else:
                feedback.append(f"Missing absent student: {student}.")

        # Verify Present Students are NOT included (20 pts)
        present_found = False
        for student in expected_present:
            parts = student.lower().split()
            first = parts[0]
            last = parts[1]
            if student.lower() in pdf_text_norm or (f"{last}, {first}" in pdf_text_norm):
                present_found = True
                feedback.append(f"Incorrectly included present student: {student}.")
        
        if not present_found:
            score += 20
            feedback.append("Correctly excluded present students.")

    except Exception as e:
        feedback.append(f"Error analyzing PDF content: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # Location check bonus/penalty
    # If the user saved to /home/ga/Documents as requested, they get full points.
    # If it was in Downloads (which export_result detects), we might deduct or just accept.
    # The current scoring ignores location strictness if file was found, assuming description compliance.
    # However, strict compliance:
    if "/Documents/" in file_path:
        pass # Good
    elif "/Downloads/" in file_path:
        feedback.append("(Note: File saved to Downloads instead of Documents).")
    
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }