#!/usr/bin/env python3
"""
Verifier for oral_history_transcript_formatting.

Verifies:
1. Metadata converted to table
2. Page Break inserted
3. Archival Header added
4. 1.5 Line Spacing applied
5. Selective Italics (Q: vs A:)
"""

import json
import logging
import os
import re
import sys
import tempfile

# Add utils directory to path to access shared Calligra verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_odt_tables,
    get_odt_paragraphs,
    check_text_italic_odt
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def check_for_page_break(content_tree, styles_tree):
    """Scan ODF XML for page break attributes."""
    for tree in [content_tree, styles_tree]:
        if tree is None:
            continue
        for elem in tree.iter():
            for k, v in elem.attrib.items():
                if 'break-before' in k and v == 'page':
                    return True
                if 'break-after' in k and v == 'page':
                    return True
    return False

def check_for_line_spacing(content_tree, styles_tree):
    """Count paragraph styles with 150% or 1.5 line height formatting."""
    count = 0
    for tree in [content_tree, styles_tree]:
        if tree is None:
            continue
        for elem in tree.iter():
            for k, v in elem.attrib.items():
                if 'line-height' in k and ('150' in v or '1.5' in v):
                    count += 1
    return count

def check_for_header_text(content_tree, styles_tree, expected_text):
    """Check master-page headers for the expected text."""
    for tree in [content_tree, styles_tree]:
        if tree is None:
            continue
        for header in tree.findall('.//{urn:oasis:names:tc:opendocument:xmlns:style:1.0}header'):
            text = "".join(header.itertext())
            if expected_text in text:
                return True
    return False

def verify_oral_history_transcript_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/mt_st_helens_transcript.odt")
    expected_header = metadata.get("expected_header", "Archive Ref: MSH-1980-04")

    # Ensure task actually executed (file modified check)
    try:
        temp_meta = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_meta.name)
        with open(temp_meta.name, 'r') as f:
            meta_res = json.load(f)
        os.unlink(temp_meta.name)
        
        if not meta_res.get("file_modified_during_task", False):
            return {"passed": False, "score": 0, "feedback": "Document was not modified. Did the agent save?"}
    except Exception as e:
        logger.warning(f"Could not read task meta result: {e}")

    # Copy and parse the ODT file
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []

    # 1. Check Metadata Table (20 pts)
    tables = get_odt_tables(content_tree)
    has_valid_table = False
    for t in tables:
        if len(t.get('rows', [])) >= 4:  # At least 4-5 rows of metadata
            has_valid_table = True
            break
            
    if has_valid_table:
        score += 20
        feedback_parts.append("Metadata table created (20/20)")
    else:
        feedback_parts.append("Metadata table not found (0/20)")

    # 2. Check Archival Header (20 pts)
    has_header = check_for_header_text(content_tree, styles_tree, expected_header)
    if has_header:
        score += 20
        feedback_parts.append("Archival header text found (20/20)")
    else:
        feedback_parts.append("Archival header text not found (0/20)")

    # 3. Check Page Break (10 pts)
    has_page_break = check_for_page_break(content_tree, styles_tree)
    if has_page_break:
        score += 10
        feedback_parts.append("Page break found (10/10)")
    else:
        feedback_parts.append("Page break not found (0/10)")

    # 4. Check Line Spacing (20 pts)
    # Require at least 5 instances of line spacing to ensure it was applied broadly
    spacing_count = check_for_line_spacing(content_tree, styles_tree)
    if spacing_count >= 5:
        score += 20
        feedback_parts.append("1.5 line spacing found on body (20/20)")
    else:
        feedback_parts.append(f"Insufficient 1.5 line spacing (found {spacing_count}) (0/20)")

    # 5. Check Selective Italics (30 pts)
    paragraphs = get_odt_paragraphs(content_tree)
    q_total, q_italic = 0, 0
    a_total, a_italic = 0, 0

    for para in paragraphs:
        text = para['text'].strip()
        if text.startswith('Q:'):
            q_total += 1
            # Check if this specific text snippet was italicized
            if check_text_italic_odt(content_tree, styles_tree, re.escape(text[:40])):
                q_italic += 1
        elif text.startswith('A:'):
            a_total += 1
            if check_text_italic_odt(content_tree, styles_tree, re.escape(text[:40])):
                a_italic += 1

    # Evaluate selective formatting
    if q_total > 0 and a_total > 0:
        if q_italic >= (q_total * 0.8) and a_italic <= (a_total * 0.2):
            score += 30
            feedback_parts.append(f"Selective italics applied correctly (Q: {q_italic}/{q_total}, A: {a_italic}/{a_total}) (30/30)")
        else:
            feedback_parts.append(f"Selective italics failed (Q: {q_italic}/{q_total} italic, A: {a_italic}/{a_total} italic) (0/30)")
    else:
        feedback_parts.append("Q&A paragraphs not detected (0/30)")

    # Determine Pass/Fail
    # To pass, must achieve >= 70 points AND must have successfully applied the header and selective italics
    key_criteria_met = has_header and (q_italic > 0 and a_italic == 0)
    passed = score >= 70 and key_criteria_met

    feedback_str = " | ".join(feedback_parts)
    if not key_criteria_met and score >= 70:
        feedback_str += " | FAILED: Did not meet key criteria (Header and Selective Italics required)."

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback_str
    }