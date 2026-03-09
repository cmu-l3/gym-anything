#!/usr/bin/env python3
"""
Verifier for event_badge_mail_merge task.

Verifies:
1. Output file exists and was created during the task.
2. Content contains data from the CSV (names, organizations).
3. Structure mimics labels (Tables).
4. Formatting matches specifications (Bold, Centered, Font Sizes).
5. No raw placeholders (<First Name>) remain.
"""

import sys
import os
import json
import logging
import tempfile
from docx.enum.text import WD_ALIGN_PARAGRAPH

# Add workspace/utils to path to import writer_verification_utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_event_badge_mail_merge(traj, env_info, task_info):
    """
    Verify the mail merge badge generation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    metadata = task_info.get('metadata', {})
    expected_samples = metadata.get('attendee_sample', [])
    formatting_rules = metadata.get('formatting_rules', {})
    
    # Load the export result to find the file path
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    output_exists = export_result.get("output_exists", False)
    output_path = export_result.get("output_path", "")
    created_during = export_result.get("file_created_during_task", False)

    if not output_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file not found. Ensure you performed the merge and saved to the correct path."
        }
    
    if not created_during:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file was not created during the task session."
        }

    # Determine format and parse
    # Even if it's .odt, our utils try to handle it (via odfpy if installed) or converting if needed
    # Ideally, we convert to docx for easier python-docx inspection if odfpy isn't robust enough
    # But let's try standard parse first.
    file_ext = os.path.splitext(output_path)[1].lower().replace('.', '')
    success, doc, error, temp_dir = copy_and_parse_document(
        output_path, copy_from_env, file_format=file_ext
    )

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse document: {error}"}

    score = 0
    feedback = []

    try:
        # === CRITERION 1: Data Integrity (40 pts) ===
        # Check if names from CSV are present
        full_text = get_document_text(doc)
        found_count = 0
        total_samples = len(expected_samples)
        
        for sample in expected_samples:
            if sample in full_text:
                found_count += 1
        
        # We expect at least 20 names in the full list, checking samples gives us a ratio
        # If we found most samples, we assume merge worked.
        if found_count >= len(expected_samples) * 0.8:
            score += 40
            feedback.append(f"Data merge successful ({found_count}/{total_samples} samples found).")
        elif found_count > 0:
            score += 20
            feedback.append(f"Partial data merge ({found_count}/{total_samples} samples found).")
        else:
            feedback.append("No expected attendee names found in document.")

        # === CRITERION 2: No Raw Placeholders (10 pts) ===
        placeholders = ["<First Name>", "<Last Name>", "<Organization>", "{First Name}", "{Last Name}"]
        raw_found = False
        for ph in placeholders:
            if ph in full_text:
                raw_found = True
                break
        
        if not raw_found:
            score += 10
            feedback.append("No raw placeholders found.")
        else:
            feedback.append("Raw placeholders (e.g. <First Name>) still present - merge might not have finished.")

        # === CRITERION 3: Formatting & Structure (40 pts) ===
        # Labels are typically tables. We check the first table.
        formatting_score = 0
        
        # Check if doc has tables (Labels use tables)
        tables = getattr(doc, 'tables', [])
        if tables:
            score += 10 # Structure points
            feedback.append("Document uses table structure (correct for labels).")
            
            # Check first cell
            try:
                first_cell = tables[0].rows[0].cells[0]
                paragraphs = first_cell.paragraphs
                # Filter empty paragraphs
                content_paras = [p for p in paragraphs if p.text.strip()]
                
                if len(content_paras) >= 3:
                    p_first = content_paras[0] # First Name
                    p_last = content_paras[1]  # Last Name
                    p_org = content_paras[2]   # Organization

                    # Check 1st Line (First Name): Bold + Center + Size
                    is_bold = any(run.bold for run in p_first.runs)
                    is_center = (p_first.alignment == WD_ALIGN_PARAGRAPH.CENTER)
                    
                    # Font size estimation (checking largest run)
                    sizes = [run.font.size.pt for run in p_first.runs if run.font.size]
                    avg_size = sum(sizes)/len(sizes) if sizes else 0
                    
                    if is_bold: formatting_score += 5
                    if is_center: formatting_score += 5
                    if avg_size >= 20: formatting_score += 5

                    # Check 2nd Line (Last Name): Bold + Center
                    is_bold_last = any(run.bold for run in p_last.runs)
                    is_center_last = (p_last.alignment == WD_ALIGN_PARAGRAPH.CENTER)
                    if is_bold_last: formatting_score += 5
                    if is_center_last: formatting_score += 5
                    
                    # Check 3rd Line (Org): Not Bold + Center
                    is_bold_org = any(run.bold for run in p_org.runs)
                    is_center_org = (p_org.alignment == WD_ALIGN_PARAGRAPH.CENTER)
                    if not is_bold_org: formatting_score += 5 # Points for correct non-bold
                    if is_center_org: formatting_score += 5

                    feedback.append(f"Formatting check passed (Score: {formatting_score}/35).")
                else:
                    feedback.append("First label does not have 3 distinct lines of text.")
            except Exception as e:
                feedback.append(f"Could not inspect table cell formatting: {e}")
        else:
            feedback.append("No tables found. Labels should use a table layout.")

        score += formatting_score

        # === CRITERION 4: VLM Verification (10 pts) ===
        # Visual check for "grid of badges" look
        vlm_result = vlm_verify_screenshot(env_info, traj, """
            Analyze this LibreOffice Writer screenshot. 
            Does the document look like a sheet of name badges or labels?
            - Are there multiple rectangular areas or a grid?
            - Do the names look like they are formatted (centered, bold)?
            - Are there real names visible (e.g. "Sarah", "Michael")?
            Answer JSON with keys: "is_label_sheet", "names_visible", "formatting_visible".
        """)
        
        if vlm_result.get("passed", False):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("is_label_sheet") and parsed.get("names_visible"):
                score += 10
                feedback.append("Visual verification passed: Looks like a sheet of name badges.")

    except Exception as e:
        logger.error(f"Verification logic error: {e}")
        feedback.append(f"Verification error: {e}")
    finally:
        cleanup_verification_temp(temp_dir)

    passed = (score >= 60)
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }