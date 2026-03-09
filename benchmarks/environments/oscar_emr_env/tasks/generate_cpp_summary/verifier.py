#!/usr/bin/env python3
"""
Verifier for generate_cpp_summary task.

Verifies:
1. PDF file was created in Downloads folder
2. PDF was created during the task window
3. PDF content includes Patient Name, Asthma, and Penicillin
"""

import os
import json
import logging
import tempfile
import time

# Check if pdfminer is available (it should be in the standard python environment provided)
try:
    from pdfminer.high_level import extract_text
    PDFMINER_AVAILABLE = True
except ImportError:
    PDFMINER_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_generate_cpp_summary(traj, env_info, task_info):
    """
    Verify the generated CPP PDF.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    patient_name = metadata.get('patient_name', 'Oliver Export')
    expected_problem = metadata.get('expected_problem', 'Asthma')
    expected_allergy = metadata.get('expected_allergy', 'Penicillin')

    # ================================================================
    # 1. Retrieve Result JSON
    # ================================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    pdf_found = result.get('pdf_found', False)
    file_created_during_task = result.get('file_created_during_task', False)
    
    score = 0
    feedback_parts = []
    
    if not pdf_found:
        return {
            "passed": False,
            "score": 0, 
            "feedback": "No PDF file found in Downloads folder.",
            "details": {"file_found": False}
        }

    score += 10
    feedback_parts.append("PDF file found")

    if file_created_during_task:
        score += 20
        feedback_parts.append("PDF created during task")
    else:
        feedback_parts.append("PDF timestamp indicates old file (anti-gaming)")

    # ================================================================
    # 2. Retrieve and Analyze PDF Content
    # ================================================================
    if not PDFMINER_AVAILABLE:
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Verifier environment missing pdfminer library."
        }

    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        # Copy the PDF identified by export_result.sh
        copy_from_env("/tmp/cpp_output.pdf", temp_pdf.name)
        
        # Extract text
        try:
            text = extract_text(temp_pdf.name)
            logger.info(f"Extracted text length: {len(text)}")
        except Exception as e:
            text = ""
            feedback_parts.append(f"Failed to extract text from PDF: {e}")
            
        # Analyze Text
        text_lower = text.lower()
        
        # Check Patient Name
        if patient_name.lower() in text_lower:
            score += 20
            feedback_parts.append(f"Patient name '{patient_name}' found")
        else:
            feedback_parts.append(f"Patient name '{patient_name}' missing")
            
        # Check Problem
        if expected_problem.lower() in text_lower or "493" in text:
            score += 25
            feedback_parts.append(f"Problem '{expected_problem}' found")
        else:
            feedback_parts.append(f"Problem '{expected_problem}' missing")
            
        # Check Allergy
        if expected_allergy.lower() in text_lower:
            score += 25
            feedback_parts.append(f"Allergy '{expected_allergy}' found")
        else:
            feedback_parts.append(f"Allergy '{expected_allergy}' missing")
            
    except Exception as e:
        feedback_parts.append(f"Error analyzing PDF: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)
            
    # Calculate final status
    # Pass threshold: 75 (Need file + name + at least one medical item)
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "pdf_found": pdf_found,
            "created_during_task": file_created_during_task,
            "final_score": score
        }
    }