#!/usr/bin/env python3
"""
Verifier for export_srs_book_pdf task.

Verifies:
1. PDF file exists at expected path.
2. File was created during the task window.
3. Content analysis confirms 'Book' layout characteristics (Table of Contents).
4. Content analysis confirms specific Title ('System Requirements v1.0').
"""

import json
import os
import tempfile
import logging
import sys

# Try to import pdfminer for text extraction
try:
    from pdfminer.high_level import extract_text
    PDFMINER_AVAILABLE = True
except ImportError:
    PDFMINER_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_srs_book_pdf(traj, env_info, task_info):
    """Verify the SRS document was exported as a Book PDF with correct title."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/SRS_Release_1.0.pdf')
    expected_title = metadata.get('expected_title', 'System Requirements v1.0')
    expected_toc = metadata.get('expected_toc_marker', 'Table of Contents')
    min_size = metadata.get('min_file_size_bytes', 1024)

    # Load result metadata from container
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Initial Checks (File Existence & Timing)
    score = 0
    feedback_parts = []
    
    if not task_result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "PDF file not found at expected path."
        }
    
    score += 20
    feedback_parts.append("PDF file created")

    if not task_result.get('file_created_during_task', False):
        feedback_parts.append("File timestamp is too old (not created during task)")
    else:
        score += 10
        feedback_parts.append("File created during task")

    file_size = task_result.get('output_size_bytes', 0)
    if file_size < min_size:
        feedback_parts.append(f"File too small ({file_size} bytes)")
    else:
        score += 10
        feedback_parts.append("File size valid")

    # Content Verification (Requires copying PDF)
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    pdf_text = ""
    try:
        copy_from_env(expected_path, temp_pdf.name)
        
        if PDFMINER_AVAILABLE:
            # Extract text from the first few pages (Title and TOC usually at start)
            try:
                # maxpages=5 should cover title and TOC
                pdf_text = extract_text(temp_pdf.name, maxpages=5)
            except Exception as e:
                feedback_parts.append(f"PDF text extraction failed: {e}")
        else:
            feedback_parts.append("PDF analysis library missing (verifier error)")
            
    except Exception as e:
        feedback_parts.append(f"Failed to retrieve PDF: {e}")
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # Analyze Text Content
    if pdf_text:
        # Check for Title (25 points)
        # Normalize spaces to handle formatting differences
        normalized_text = " ".join(pdf_text.split())
        
        if expected_title.lower() in normalized_text.lower():
            score += 30
            feedback_parts.append(f"Title '{expected_title}' found")
        else:
            feedback_parts.append(f"Title '{expected_title}' NOT found in document header/cover")

        # Check for Table of Contents (25 points)
        # "Table of Contents" or "Contents" usually appears in Book layout, but not Table layout
        if expected_toc.lower() in normalized_text.lower() or "contents" in normalized_text.lower()[:500]:
            score += 30
            feedback_parts.append("Table of Contents found (Book layout confirmed)")
        else:
            feedback_parts.append("Table of Contents NOT found (Check layout setting)")

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }