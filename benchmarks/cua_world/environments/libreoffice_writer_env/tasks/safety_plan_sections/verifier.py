#!/usr/bin/env python3
"""
Verifier for Construction Safety Plan Section Formatting task.

Criteria:
1. File exists and valid DOCX (10 pts)
2. Heading 1 styles applied to 6 main sections (15 pts)
3. Heading 2 styles applied to 8 subsections (15 pts)
4. Document has at least 3 sections (15 pts)
5. At least one section is Landscape (15 pts)
6. Page numbers present in footer (10 pts)
7. Body text formatted to 11pt Arial/Liberation Sans (15 pts)
8. Content preservation (5 pts)

Pass Threshold: 65/100
"""

import json
import os
import sys
import tempfile
import logging
import re

# Add utils path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_safety_plan(traj, env_info, task_info):
    """Verify safety plan formatting task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/safety_plan_formatted.docx')
    heading1_titles = metadata.get('heading1_titles', [])
    heading2_titles = metadata.get('heading2_titles', [])
    approved_fonts = [f.lower() for f in metadata.get('approved_fonts', ["arial", "liberation sans"])]

    # Load result metadata
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check anti-gaming timestamp
    if not task_result.get('file_created_during_task', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file was not created/modified during the task session."
        }

    # Load the document
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse output document: {error}"
        }

    try:
        score = 0
        feedback_parts = []
        
        # Criterion 1: File validity (10 pts)
        score += 10
        feedback_parts.append("File exists and is valid DOCX")

        # Criterion 2: Heading 1 Styles (15 pts)
        h1_map = {t: 'Heading 1' for t in heading1_titles}
        h1_matched, h1_total, h1_fb = check_heading_styles(doc, h1_map)
        
        if h1_matched >= 5: # Allow 1 miss
            score += 15
            feedback_parts.append(f"Heading 1 styles: {h1_matched}/{h1_total} correct")
        else:
            feedback_parts.append(f"Heading 1 styles incomplete: only {h1_matched}/{h1_total}")

        # Criterion 3: Heading 2 Styles (15 pts)
        h2_map = {t: 'Heading 2' for t in heading2_titles}
        h2_matched, h2_total, h2_fb = check_heading_styles(doc, h2_map)

        if h2_matched >= 6: # Allow 2 misses
            score += 15
            feedback_parts.append(f"Heading 2 styles: {h2_matched}/{h2_total} correct")
        else:
            feedback_parts.append(f"Heading 2 styles incomplete: only {h2_matched}/{h2_total}")

        # Criterion 4: Section Breaks (15 pts)
        num_sections = len(doc.sections)
        if num_sections >= 3:
            score += 15
            feedback_parts.append(f"Section breaks found ({num_sections} sections)")
        else:
            feedback_parts.append(f"Insufficient sections: {num_sections} (expected >= 3)")

        # Criterion 5: Landscape Orientation (15 pts)
        has_landscape = False
        from docx.enum.section import WD_ORIENT
        for idx, section in enumerate(doc.sections):
            # Check explicit orientation enum OR page dimensions
            width = section.page_width
            height = section.page_height
            is_wide = (width is not None and height is not None and width > height)
            if section.orientation == WD_ORIENT.LANDSCAPE or is_wide:
                has_landscape = True
                break
        
        if has_landscape:
            score += 15
            feedback_parts.append("Landscape section found")
        else:
            feedback_parts.append("No landscape section found")

        # Criterion 6: Page Numbers (10 pts)
        # Check XML of footers for 'PAGE' field or simple numbers
        has_page_num = False
        for section in doc.sections:
            footers = [section.footer, section.first_page_footer, section.even_page_footer]
            for footer in footers:
                if footer and (
                    'w:fldSimple' in footer._element.xml and 'PAGE' in footer._element.xml or
                    'w:instrText' in footer._element.xml and 'PAGE' in footer._element.xml
                ):
                    has_page_num = True
                    break
            if has_page_num: break
        
        if has_page_num:
            score += 10
            feedback_parts.append("Page numbers detected in footer")
        else:
            # Fallback: check text content of footers for digits
            digit_found = False
            for section in doc.sections:
                if section.footer:
                    text = "".join([p.text for p in section.footer.paragraphs])
                    if any(c.isdigit() for c in text):
                        digit_found = True
                        break
            if digit_found:
                score += 5 # Partial credit for just typing number
                feedback_parts.append("Static page number found (partial credit)")
            else:
                feedback_parts.append("No page numbers found")

        # Criterion 7: Body Text Formatting (15 pts)
        # Check random sample of body paragraphs
        body_runs = 0
        correct_runs = 0
        for para in doc.paragraphs:
            if para.style and 'Heading' not in para.style.name and 'Title' not in para.style.name:
                for run in para.runs:
                    if run.text.strip():
                        body_runs += 1
                        font_name = (run.font.name or "").lower()
                        # If run doesn't have font, check style
                        if not font_name and para.style and para.style.font:
                            font_name = (para.style.font.name or "").lower()
                        
                        font_size = run.font.size
                        if not font_size and para.style and para.style.font:
                            font_size = para.style.font.size
                        
                        pt_size = font_size.pt if font_size else 0
                        
                        name_ok = any(f in font_name for f in approved_fonts)
                        size_ok = (pt_size >= 10.5) # allow slight float precision errors
                        
                        if name_ok and size_ok:
                            correct_runs += 1
        
        if body_runs > 0 and (correct_runs / body_runs) > 0.5:
            score += 15
            feedback_parts.append("Body text formatting correct")
        elif body_runs > 0 and (correct_runs / body_runs) > 0.2:
            score += 7
            feedback_parts.append("Body text formatting partially correct")
        else:
            feedback_parts.append("Body text formatting incorrect")

        # Criterion 8: Content Preservation (5 pts)
        text = get_document_text(doc).lower()
        if "site-specific safety plan" in text and "marcus rivera" in text:
            score += 5
            feedback_parts.append("Content preserved")
        else:
            feedback_parts.append("Key content missing")

        return {
            "passed": score >= 65,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification logic failed: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        cleanup_verification_temp(temp_dir)