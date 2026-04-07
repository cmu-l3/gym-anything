#!/usr/bin/env python3
"""Verifier for the municipal_rfp_formatting task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_text_bold_odt,
    check_text_italic_odt,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}

def check_page_break_before(content_tree, target_text):
    """
    Checks if a page break exists immediately before or on the paragraph containing target_text.
    """
    page_break_styles = set()
    for style in content_tree.findall('.//style:style', ODF_NS):
        props = style.find('.//style:paragraph-properties', ODF_NS)
        if props is not None and props.get(f"{{{ODF_NS['fo']}}}break-before") == "page":
            page_break_styles.add(style.get(f"{{{ODF_NS['style']}}}name"))

    has_break = False
    for p in content_tree.findall('.//text:p', ODF_NS) + content_tree.findall('.//text:h', ODF_NS):
        style_name = p.get(f"{{{ODF_NS['text']}}}style-name")
        if style_name in page_break_styles:
            has_break = True

        text = "".join(p.itertext()).strip()
        if text:  # If paragraph is not completely empty
            if target_text in text and has_break:
                return True
            has_break = (style_name in page_break_styles)
    
    return False

def verify_municipal_rfp_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/smart_parking_rfp.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document."}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # ── 1. Heading 1 styles (15 pts) ──
        expected_headings = metadata.get("expected_headings", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_headings, 1)
        if h1_matched == h1_total:
            score += 15
            feedback_parts.append("Headings: All 6 main sections formatted as H1")
        elif h1_matched > 0:
            score += int(15 * (h1_matched / h1_total))
            feedback_parts.append(f"Headings: {h1_matched}/{h1_total} formatted as H1")
        else:
            feedback_parts.append("Headings: No H1 headings found")

        # ── 2. Table of Contents (10 pts) ──
        has_toc = detect_toc_odt(content_tree)
        if has_toc:
            score += 10
            feedback_parts.append("TOC: Present")
        else:
            feedback_parts.append("TOC: Missing")

        # ── 3 & 4. Tables Parsing ──
        tables = get_odt_tables(content_tree)
        schedule_table_found = False
        matrix_table_found = False
        matrix_perfect = False
        
        for table in tables:
            rows = table.get("rows", [])
            if not rows: continue
            
            # Check for Schedule Table (2 cols, contains "Event" and "Date")
            if not schedule_table_found and len(rows[0]) >= 2:
                header_text = " ".join(rows[0]).lower()
                if "event" in header_text and "date" in header_text:
                    schedule_table_found = True
                    score += 15
                    feedback_parts.append("Schedule Table: Created successfully")
                    continue
                    
            # Check for Vendor Response Matrix (3 cols)
            if not matrix_table_found and len(rows[0]) >= 3:
                header_text = " ".join(rows[0]).lower()
                if "requirement" in header_text and "comply" in header_text and "explanation" in header_text:
                    matrix_table_found = True
                    
                    # Verify content distribution in Matrix
                    requirements = metadata.get("technical_requirements", [])
                    reqs_found = 0
                    empty_cols_respected = True
                    
                    for req in requirements:
                        req_snippet = req[:30].lower() # match first 30 chars
                        for row in rows:
                            if len(row) >= 3 and req_snippet in row[0].lower():
                                reqs_found += 1
                                # Check if columns 2 and 3 are empty
                                if row[1].strip() != "" or row[2].strip() != "":
                                    empty_cols_respected = False
                                break
                                
                    if reqs_found >= 4 and empty_cols_respected:
                        matrix_perfect = True
                        score += 25
                        feedback_parts.append("Vendor Matrix: Created successfully with empty response columns")
                    elif reqs_found >= 4:
                        score += 15
                        feedback_parts.append("Vendor Matrix: Created, but response columns were not left empty")
                    else:
                        score += 5
                        feedback_parts.append("Vendor Matrix: Created, but missing requirement rows")
                        
        if not schedule_table_found:
            feedback_parts.append("Schedule Table: Missing")
        if not matrix_table_found:
            feedback_parts.append("Vendor Matrix: Missing")

        # ── 5. Deadline Highlighting (15 pts) ──
        deadline = metadata.get("deadline_text", "October 15, 2026")
        surrounding = metadata.get("surrounding_text", "submitted no later than")
        
        deadline_bold = check_text_bold_odt(content_tree, styles_tree, deadline)
        deadline_italic = check_text_italic_odt(content_tree, styles_tree, deadline)
        surrounding_bold = check_text_bold_odt(content_tree, styles_tree, surrounding)
        surrounding_italic = check_text_italic_odt(content_tree, styles_tree, surrounding)
        
        if deadline_bold and deadline_italic and not surrounding_bold and not surrounding_italic:
            score += 15
            feedback_parts.append("Deadline Format: Date correctly bolded and italicized independently")
        elif deadline_bold and deadline_italic:
            score += 5
            feedback_parts.append("Deadline Format: Date is bold/italic, but surrounding text is too (imprecise selection)")
        elif deadline_bold or deadline_italic:
            score += 5
            feedback_parts.append("Deadline Format: Date is partially formatted (missing either bold or italic)")
        else:
            feedback_parts.append("Deadline Format: Missing bold/italic")

        # ── 6. Page Break (10 pts) ──
        if check_page_break_before(content_tree, "6.0 Submission Instructions"):
            score += 10
            feedback_parts.append("Page Break: Successfully inserted before Section 6.0")
        else:
            feedback_parts.append("Page Break: Missing before Section 6.0")

        # ── 7. Signature Block (10 pts) ──
        full_text = get_document_text_odt(content_tree)
        patterns = [
            r"Company Name[:\s]*_{4,}",
            r"Signature[:\s]*_{4,}",
            r"Printed Name[:\s]*_{4,}",
            r"Date[:\s]*_{4,}"
        ]
        
        sig_matches = 0
        for pat in patterns:
            if re.search(pat, full_text, re.IGNORECASE):
                sig_matches += 1
                
        if sig_matches == 4:
            score += 10
            feedback_parts.append("Signature Block: All 4 fillable lines created")
        elif sig_matches > 0:
            score += int(10 * (sig_matches / 4))
            feedback_parts.append(f"Signature Block: {sig_matches}/4 lines created")
        else:
            feedback_parts.append("Signature Block: Missing or improperly formatted underscores")

        # ── Final Pass Logic ──
        # Must score >= 75 AND have a perfect vendor response matrix to pass
        passed = (score >= 75) and matrix_perfect

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }