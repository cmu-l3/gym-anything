#!/usr/bin/env python3
"""Verifier for the academic_journal_typesetting task."""

import json
import logging
import os
import re
import sys
import tempfile

# Add Calligra utility scripts to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_odt_paragraphs,
    get_odt_styles,
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_italic_odt,
    check_text_font_size_odt
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_length(length_str):
    """Safely parse ODT length strings (e.g., '1.25cm', '-0.5in') to floats."""
    if not length_str:
        return 0.0
    m = re.search(r"(-?[\d\.]+)", str(length_str))
    if m:
        return float(m.group(1))
    return 0.0

def get_style_properties(styles_dict, style_name):
    """Walk the style inheritance chain to accumulate properties."""
    props = {
        'margin_left': '0', 'margin_right': '0', 'text_indent': '0', 
        'italic': False, 'bold': False, 'alignment': ''
    }
    curr = style_name
    visited = set()
    chain = []
    
    while curr and curr not in visited:
        visited.add(curr)
        chain.insert(0, curr)
        curr = styles_dict.get(curr, {}).get('parent', '')

    for s in chain:
        st = styles_dict.get(s, {})
        if st.get('margin_left'): props['margin_left'] = st['margin_left']
        if st.get('margin_right'): props['margin_right'] = st['margin_right']
        if st.get('text_indent'): props['text_indent'] = st['text_indent']
        if st.get('italic') is not None: props['italic'] = st.get('italic')
        if st.get('bold') is not None: props['bold'] = st.get('bold')
        if st.get('alignment'): props['alignment'] = st['alignment']
        
    return props

def verify_academic_journal_typesetting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/crispr_brassica_manuscript.odt")

    # Read exported metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    file_modified = False
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
            file_modified = result_data.get("file_modified", False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not file_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Document was not modified or saved during the task. Anti-gaming check failed."
        }

    # Copy and parse the ODT
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)

    score = 0
    feedback_parts = []

    try:
        # ── 1. Title & Author Formatting (10 points) ──
        title_text = metadata.get("title_text", "")
        authors_text = metadata.get("authors_text", "")
        
        title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(title_text))
        title_sized = check_text_font_size_odt(content_tree, styles_tree, re.escape(title_text), 16.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(title_text), "center")
        authors_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(authors_text), "center")
        
        if title_bold and title_sized and title_centered > 0 and authors_centered > 0:
            score += 10
            feedback_parts.append("Title and Authors formatted correctly (+10)")
        else:
            feedback_parts.append("Title/Authors formatting incomplete")

        # ── 2. Abstract Block Indent (20 points) ──
        abstract_snippet = metadata.get("abstract_snippet", "")
        abstract_para = next((p for p in paragraphs if abstract_snippet in p['text']), None)
        
        if abstract_para:
            props = get_style_properties(styles, abstract_para['style_name'])
            ml = parse_length(props['margin_left'])
            mr = parse_length(props['margin_right'])
            
            if ml > 0.0 and mr > 0.0:
                score += 20
                feedback_parts.append("Abstract Block Indent verified (+20)")
            else:
                feedback_parts.append(f"Abstract margins incorrect (Left: {ml}, Right: {mr})")
        else:
            feedback_parts.append("Abstract paragraph not found")

        # ── 3. Abstract Italicization (10 points) ──
        # Can be applied via paragraph style OR direct span formatting
        abstract_italic = False
        if abstract_para:
            props = get_style_properties(styles, abstract_para['style_name'])
            if props['italic']:
                abstract_italic = True
            else:
                abstract_italic = check_text_italic_odt(content_tree, styles_tree, re.escape(abstract_snippet))
                
        if abstract_italic:
            score += 10
            feedback_parts.append("Abstract Italicized (+10)")
        else:
            feedback_parts.append("Abstract not italicized")

        # ── 4. Heading 1 Application (15 points) ──
        expected_h1 = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
        if h1_matched >= 6:
            score += 15
            feedback_parts.append(f"Heading 1: {h1_matched}/{h1_total} OK (+15)")
        else:
            feedback_parts.append(f"Heading 1: only {h1_matched}/{h1_total} matched")

        # ── 5. Heading 2 Application (10 points) ──
        expected_h2 = metadata.get("expected_h2_subsections", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
        if h2_matched >= 2:
            score += 10
            feedback_parts.append(f"Heading 2: {h2_matched}/{h2_total} OK (+10)")
        else:
            feedback_parts.append(f"Heading 2: only {h2_matched}/{h2_total} matched")

        # ── 6. Body Text Justification (10 points) ──
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sample), "justify")
            if matched > 0:
                justified_count += 1
                
        if justified_count >= 2:
            score += 10
            feedback_parts.append(f"Body text justified: {justified_count}/{len(body_samples)} OK (+10)")
        else:
            feedback_parts.append(f"Body text justified: {justified_count}/{len(body_samples)}")

        # ── 7. References Hanging Indent (25 points) ──
        # To pass, Left Margin must be > 0 and Text Indent (first-line) must be < 0
        ref_snippets = metadata.get("reference_snippets", [])
        hanging_count = 0
        
        for snippet in ref_snippets:
            ref_para = next((p for p in paragraphs if snippet in p['text']), None)
            if ref_para:
                props = get_style_properties(styles, ref_para['style_name'])
                ml = parse_length(props['margin_left'])
                ti = parse_length(props['text_indent'])
                
                if ml > 0.0 and ti < 0.0:
                    hanging_count += 1
                    
        if hanging_count >= 2:
            score += 25
            feedback_parts.append(f"References Hanging Indent: {hanging_count}/{len(ref_snippets)} OK (+25)")
        else:
            feedback_parts.append(f"References Hanging Indent: only {hanging_count}/{len(ref_snippets)} valid")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification error: {e}"}

    # Pass threshold is 75 points. Must hit the advanced requirements.
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }