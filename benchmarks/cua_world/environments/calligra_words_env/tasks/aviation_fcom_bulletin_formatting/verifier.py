#!/usr/bin/env python3
"""
Verifier for the aviation_fcom_bulletin_formatting task.
Validates exact structural properties in ODF XML based on the FCOM style guide.
"""

import logging
import os
import sys
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables,
    check_heading_styles_odt,
    get_document_text_odt
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_length_cm(val):
    """Parses an ODF length string (e.g., '1in', '2.54cm') and returns its value in cm."""
    if not val:
        return 0.0
    val = str(val).lower().strip()
    try:
        if 'in' in val: return float(val.replace('in', '')) * 2.54
        if 'cm' in val: return float(val.replace('cm', ''))
        if 'mm' in val: return float(val.replace('mm', '')) / 10.0
        if 'pt' in val: return float(val.replace('pt', '')) * 0.03527
        return float(val)
    except Exception:
        return 0.0

def resolve_style_property(styles, style_name, prop_name, default=None):
    """Walks the ODF style parent chain to resolve a property."""
    current = style_name
    visited = set()
    while current and current not in visited:
        visited.add(current)
        style = styles.get(current, {})
        if prop_name in style and style[prop_name] not in ('', None):
            return style[prop_name]
        current = style.get('parent', '')
    return default

def verify_fcom_bulletin_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/b737_winter_ops_bulletin.odt")

    # Anti-gaming check (file modified)
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            res_data = json.load(f)
            file_modified = res_data.get("file_modified_during_task", False)
    except Exception:
        pass
    finally:
        if os.path.exists(temp_res.name): os.unlink(temp_res.name)

    if not file_modified:
        return {"passed": False, "score": 0, "feedback": "Document was not saved/modified during the task."}

    # Fetch and parse the ODT Document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)
    
    score = 0
    feedback_parts = []
    
    # ----------------------------------------------------------------
    # 1. Header Formatting (Right-aligned, Bold) - 15 points
    # ----------------------------------------------------------------
    header_lines = metadata.get("header_lines", [])
    headers_ok = 0
    for hl in header_lines:
        for para in paragraphs:
            if hl in para['text']:
                s_name = para.get('style_name', '')
                bold = resolve_style_property(styles, s_name, 'bold', False)
                align = resolve_style_property(styles, s_name, 'alignment', '')
                if bold and align in ['right', 'end']:
                    headers_ok += 1
                break
    
    if headers_ok == 4:
        score += 15
        feedback_parts.append("Headers: Formatted OK")
    else:
        feedback_parts.append(f"Headers: {headers_ok}/4 formatted correctly")

    # ----------------------------------------------------------------
    # 2. Section Headings (Heading 1) - 15 points
    # ----------------------------------------------------------------
    section_headings = metadata.get("section_headings", [])
    h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, section_headings, 1)
    if h1_matched == h1_total:
        score += 15
        feedback_parts.append("Section Headings: Formatted OK")
    else:
        feedback_parts.append(f"Section Headings: {h1_matched}/{h1_total} as H1")

    # ----------------------------------------------------------------
    # 3. WARNING Formatting (Centered, Bold, Margins >= 2.0cm) - 20 points
    # ----------------------------------------------------------------
    warnings = metadata.get("warnings", [])
    warnings_ok = 0
    for wt in warnings:
        for para in paragraphs:
            if wt in para['text']:
                s_name = para.get('style_name', '')
                bold = resolve_style_property(styles, s_name, 'bold', False)
                align = resolve_style_property(styles, s_name, 'alignment', '')
                ml_cm = parse_length_cm(resolve_style_property(styles, s_name, 'margin_left', '0'))
                mr_cm = parse_length_cm(resolve_style_property(styles, s_name, 'margin_right', '0'))
                
                # Check centered, bold, bilateral indent (~1 in / 2.54 cm -> tolerate >= 2.0 cm)
                if bold and align == 'center' and ml_cm >= 2.0 and mr_cm >= 2.0:
                    warnings_ok += 1
                break
    
    if warnings_ok == len(warnings):
        score += 20
        feedback_parts.append("Warnings: Formatted OK")
    else:
        feedback_parts.append(f"Warnings: {warnings_ok}/{len(warnings)} formatted correctly")

    # ----------------------------------------------------------------
    # 4. CAUTION Formatting (Italicized, Left Indent >= 1.0cm) - 20 points
    # ----------------------------------------------------------------
    cautions = metadata.get("cautions", [])
    cautions_ok = 0
    for ct in cautions:
        for para in paragraphs:
            if ct in para['text']:
                s_name = para.get('style_name', '')
                italic = resolve_style_property(styles, s_name, 'italic', False)
                align = resolve_style_property(styles, s_name, 'alignment', '')
                ml_cm = parse_length_cm(resolve_style_property(styles, s_name, 'margin_left', '0'))
                mr_cm = parse_length_cm(resolve_style_property(styles, s_name, 'margin_right', '0'))
                
                # Check italic, not centered/right, left indent (~0.5 in / 1.27 cm -> tolerate >= 1.0 cm), no right indent
                if italic and align not in ['center', 'right', 'end'] and ml_cm >= 1.0 and mr_cm < 1.0:
                    cautions_ok += 1
                break

    if cautions_ok == len(cautions):
        score += 20
        feedback_parts.append("Cautions: Formatted OK")
    else:
        feedback_parts.append(f"Cautions: {cautions_ok}/{len(cautions)} formatted correctly")

    # ----------------------------------------------------------------
    # 5. Table Conversion - 20 points
    # ----------------------------------------------------------------
    tables = get_odt_tables(content_tree)
    table_found = False
    for t in tables:
        t_text = str(t).lower()
        if "type ii" in t_text or "holdover" in t_text:
            table_found = True
            break
    
    if table_found:
        score += 20
        feedback_parts.append("Table: Created OK")
    else:
        feedback_parts.append("Table: Not found")

    # ----------------------------------------------------------------
    # 6. List Conversion - 10 points
    # ----------------------------------------------------------------
    list_items = metadata.get("list_items", [])
    lists_ok = 0
    for lt in list_items:
        for para in paragraphs:
            if lt in para['text'] and para.get('is_list_item'):
                lists_ok += 1
                break
    
    if lists_ok >= len(list_items) - 1: # Allow 1 minor miss
        score += 10
        feedback_parts.append("List: Created OK")
    else:
        feedback_parts.append(f"List: {lists_ok}/{len(list_items)} items formatted as list")

    # ----------------------------------------------------------------
    # Final Evaluation
    # ----------------------------------------------------------------
    # Critical criteria: Must score at least 75, AND at least one Warning must be correct 
    # to demonstrate they understood multi-property/bilateral margin instructions.
    
    passed = score >= 75 and warnings_ok > 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }