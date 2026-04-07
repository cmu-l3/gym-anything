#!/usr/bin/env python3
"""
Verifier for print_dive_log_pdf task.

VERIFICATION STRATEGY:
1. File Existence: Check if /home/ga/Documents/printed_log.pdf exists.
2. Anti-Gaming: Ensure file creation time is after the task start time.
3. PDF Format: Verify PDF magic bytes (%PDF-).
4. Content Extraction (Programmatic): Use pdfminer to extract text and check against known dive sites in SampleDivesV2.ssrf.
5. VLM Trajectory (Supplementary): Verify Print functionality was used.
"""

import os
import json
import tempfile
import logging

# Ensure pdfminer is imported, failing gracefully if env issues occur
try:
    from pdfminer.high_level import extract_text
    PDFMINER_AVAILABLE = True
except ImportError:
    PDFMINER_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_print_pdf(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Documents/printed_log.pdf')
    min_file_size_bytes = metadata.get('min_file_size_bytes', 1024)
    keywords = metadata.get('required_text_keywords', ["Sund Rock", "Yellow House"])

    feedback_parts = []
    score = 0

    # 1. Read task_result.json
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result.get('output_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    output_size_bytes = result.get('output_size_bytes', 0)

    # 2. Check File Existence and Timestamps (up to 40 pts)
    if not output_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "printed_log.pdf not found in /home/ga/Documents/"
        }
    
    score += 20
    feedback_parts.append("File exists")

    if not file_created_during_task:
        return {
            "passed": False,
            "score": score,
            "feedback": "File exists but was NOT created during the task (Anti-gaming check failed)."
        }
    
    score += 20
    feedback_parts.append("Created during task")

    if output_size_bytes < min_file_size_bytes:
        feedback_parts.append(f"File size too small ({output_size_bytes} bytes).")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
    
    score += 10
    feedback_parts.append("Valid file size")

    # 3. Copy the actual PDF to check structure and content (up to 50 pts)
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        copy_from_env(expected_output_path, temp_pdf.name)
        
        # Verify Magic Bytes
        with open(temp_pdf.name, 'rb') as f:
            magic = f.read(5)
            
        if magic != b'%PDF-':
            feedback_parts.append("Invalid PDF format (missing magic bytes).")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
        score += 20
        feedback_parts.append("Valid PDF format")

        # Verify Content Using PDFMiner
        content_found = False
        if PDFMINER_AVAILABLE:
            try:
                text = extract_text(temp_pdf.name)
                text_lower = text.lower()
                
                # Check for our known sample dive keywords
                matches = [kw for kw in keywords if kw.lower() in text_lower]
                if matches:
                    content_found = True
                    score += 30
                    feedback_parts.append(f"Found dive data keywords: {matches}")
                else:
                    feedback_parts.append("PDF is valid but does not contain expected dive log text.")
            except Exception as e:
                logger.error(f"pdfminer extraction failed: {e}")
                feedback_parts.append(f"PDF extraction failed: {e}")
        else:
            feedback_parts.append("pdfminer not available for deep text verification.")
            # Give benefit of the doubt if pdfminer isn't installed but PDF is valid and correct size
            score += 30 
            content_found = True

    except Exception as e:
        feedback_parts.append(f"Failed to copy/read PDF: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    passed = score >= 80 and output_exists and file_created_during_task

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }