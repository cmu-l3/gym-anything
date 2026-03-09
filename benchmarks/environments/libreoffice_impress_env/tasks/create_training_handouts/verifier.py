#!/usr/bin/env python3
"""
Verifier for Create Training Handouts task
"""

import sys
import os
import json
import tempfile
import logging
from io import BytesIO

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_handout_pdf(traj, env_info, task_info):
    """
    Verify the generated PDF handout.
    
    Criteria:
    1. PDF file exists and was created during task.
    2. Header text "INTERNAL TRAINING MATERIAL" is present.
    3. Page count is exactly 4 (implies 10 slides / 3 per page).
    4. Content from last slide is present (implies full export).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_header = metadata.get('required_header_text', "INTERNAL TRAINING MATERIAL")
    expected_page_count = metadata.get('expected_page_count', 4)
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/results/safety_handouts.pdf')

    # 1. Load basic result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("output_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Output PDF file not found at expected location."
        }

    if not result_data.get("file_created_during_task", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "❌ Output file exists but was not created/modified during this task session."
        }

    # 2. Analyze PDF Content
    # We copy the PDF to a temp file to analyze it with pdfminer
    temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
    try:
        copy_from_env(expected_path, temp_pdf.name)
        
        # Import PDF processing tools
        try:
            from pdfminer.high_level import extract_text, extract_pages
            
            # Check Page Count
            pages = list(extract_pages(temp_pdf.name))
            actual_page_count = len(pages)
            
            # Check Text Content
            full_text = extract_text(temp_pdf.name)
            
        except ImportError:
            # Fallback if pdfminer not available (though it should be per env spec)
            # Simple binary check for the header string as a last resort
            logger.warning("pdfminer not found, using binary fallback")
            with open(temp_pdf.name, 'rb') as f:
                raw_content = f.read()
                # Basic PDF page counting (naive)
                actual_page_count = raw_content.count(b'/Type /Page') - raw_content.count(b'/Type /Pages')
                # Text check (pdf text might be compressed/encoded, so this is risky but better than nothing)
                full_text = raw_content.decode('latin-1', errors='ignore')

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error processing PDF file: {e}"}
    finally:
        if os.path.exists(temp_pdf.name):
            os.unlink(temp_pdf.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # Criterion 1: File created (already checked above, granting points)
    score += 20
    feedback_parts.append("✅ PDF created")

    # Criterion 2: Page Count (Layout Check)
    # 10 slides / 3 per page = 4 pages. 
    # If 1 per page = 10 pages. If 2 per page = 5 pages. If 6 per page = 2 pages.
    if actual_page_count == expected_page_count:
        score += 30
        feedback_parts.append(f"✅ Correct layout (4 pages found)")
    else:
        feedback_parts.append(f"❌ Incorrect layout: Found {actual_page_count} pages (Expected {expected_page_count} for 3-up handout)")

    # Criterion 3: Header Text
    if required_header in full_text:
        score += 30
        feedback_parts.append(f"✅ Header text found")
    else:
        feedback_parts.append(f"❌ Header text '{required_header}' missing from PDF")

    # Criterion 4: Content Completeness (Last slide content)
    # Check for content from the last slide to ensure full export
    last_slide_keywords = ["Safety Officer", "Emergency Services", "911"]
    found_keywords = [kw for kw in last_slide_keywords if kw in full_text]
    
    if len(found_keywords) > 0:
        score += 20
        feedback_parts.append("✅ Full content exported")
    else:
        feedback_parts.append("❌ Last slide content missing (export might be incomplete)")

    # Final result
    passed = score >= 80  # Requires layout and header to be correct
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }