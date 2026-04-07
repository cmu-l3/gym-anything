#!/usr/bin/env python3
"""
Verifier for export_sudo_usage_evidence task.
"""

import json
import os
import tempfile
import logging
import re

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_sudo_usage_evidence(traj, env_info, task_info):
    """
    Verify that the user exported a PDF containing sudo logs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_keywords = metadata.get('required_content', ["sudo", "COMMAND"])
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON
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
            
    # 2. Check File Existence and Timing (Anti-gaming)
    if not result.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Evidence PDF file not found at expected location."}
        
    if not result.get("file_created_during_task"):
        return {"passed": False, "score": 0, "feedback": "File exists but was not created during the task window (anti-gaming check failed)."}
    
    score += 30
    feedback_parts.append("PDF file created successfully")

    # 3. Retrieve and Analyze the PDF
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    pdf_content_text = ""
    try:
        copy_from_env("/tmp/sudo_evidence.pdf", temp_pdf.name)
        
        # Basic check: Is it a PDF?
        with open(temp_pdf.name, 'rb') as f:
            header = f.read(4)
            if header != b'%PDF':
                return {"passed": False, "score": score, "feedback": "Exported file is not a valid PDF."}
        
        score += 20
        feedback_parts.append("Valid PDF format")
        
        # Content Extraction (Try using pdfminer if available, else naive string search)
        try:
            from pdfminer.high_level import extract_text
            pdf_content_text = extract_text(temp_pdf.name)
        except ImportError:
            logger.warning("pdfminer not available, falling back to binary string search")
            with open(temp_pdf.name, 'rb') as f:
                # Naive extraction of text-like strings from binary
                # This is flaky for compressed PDFs but often works for simple exports
                raw_data = f.read()
                # Remove null bytes and filter for printable chars
                pdf_content_text = raw_data.decode('latin-1', errors='ignore')
        except Exception as e:
            logger.error(f"PDF parsing error: {e}")
            feedback_parts.append("Could not parse PDF content")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Failed to retrieve PDF for analysis: {e}"}
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # 4. Check Content for Keywords
    # We look for 'sudo' and other indicators of log data
    found_keywords = []
    missing_keywords = []
    
    for kw in required_keywords:
        if kw.lower() in pdf_content_text.lower():
            found_keywords.append(kw)
        else:
            missing_keywords.append(kw)
            
    if "sudo" in found_keywords:
        score += 25
        feedback_parts.append("Contains 'sudo' keyword")
    else:
        feedback_parts.append("Missing 'sudo' keyword in PDF")

    if len(found_keywords) >= len(required_keywords):
        score += 25
        feedback_parts.append("Contains all required log details")
    elif len(found_keywords) > 0:
        # Partial credit for content
        score += 10
        feedback_parts.append(f"Found some keywords: {', '.join(found_keywords)}")
    else:
        feedback_parts.append("PDF seems empty of required log data")

    # 5. Final pass determination
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }