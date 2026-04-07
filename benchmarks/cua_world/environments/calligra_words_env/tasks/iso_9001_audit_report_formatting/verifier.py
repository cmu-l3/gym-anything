#!/usr/bin/env python3
"""Verifier for the iso_9001_audit_report_formatting task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    copy_and_parse_document,
    detect_toc_odt,
    get_document_text_odt,
    get_odt_tables,
    get_odt_styles
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

LOCAL_ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}

def is_red(color_str):
    """Determine if a hex color string represents red."""
    if not color_str:
        return False
    c = color_str.lower().strip()
    if c in ['#ff0000', 'red']:
        return True
    if len(c) == 7 and c.startswith('#'):
        try:
            r, g, b = int(c[1:3], 16), int(c[3:5], 16), int(c[5:7], 16)
            return r > 150 and g < 100 and b < 100
        except ValueError:
            pass
    return False

def get_odt_styles_with_color(content_tree, styles_tree):
    """Extends the standard get_odt_styles to also parse text color."""
    styles = get_odt_styles(content_tree, styles_tree)
    
    ns_style = LOCAL_ODF_NS['style']
    ns_fo = LOCAL_ODF_NS['fo']
    
    def extract_colors(tree):
        if tree is None: return
        for st in tree.findall(f'.//{{{ns_style}}}style'):
            name = st.get(f'{{{ns_style}}}name')
            if name and name in styles:
                text_props = st.find(f'{{{ns_style}}}text-properties')
                if text_props is not None:
                    color = text_props.get(f'{{{ns_fo}}}color')
                    if color:
                        styles[name]['color'] = color
                        
    extract_colors(content_tree)
    extract_colors(styles_tree)
    
    # Propagate color from parents
    for name, props in styles.items():
        curr = name
        while 'color' not in props and curr:
            parent = styles.get(curr, {}).get('parent')
            if parent and parent in styles:
                if 'color' in styles[parent]:
                    props['color'] = styles[parent]['color']
                    break
                curr = parent
            else:
                break
                
    return styles

def get_best_phrase_style(content_tree, styles, target_phrase):
    """Finds the strongest style presence (bold/red/italic) applied to a target phrase."""
    ns_text = LOCAL_ODF_NS['text']
    best_b, best_r, best_i = False, False, False
    
    for node in content_tree.iter():
        tag = node.tag
        if tag in [f'{{{ns_text}}}span', f'{{{ns_text}}}p', f'{{{ns_text}}}h']:
            text_content = "".join(node.itertext())
            if target_phrase in text_content:
                style_name = node.get(f'{{{ns_text}}}style-name', '')
                props = styles.get(style_name, {})
                if props.get('bold'): best_b = True
                if props.get('italic'): best_i = True
                if is_red(props.get('color', '')): best_r = True
    return best_b, best_r, best_i

def verify_iso_9001_audit_report_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/apex_iso_audit_report.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document. The file may be empty or corrupt."}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        styles = get_odt_styles_with_color(content_tree, styles_tree)

        # 1. Content Preservation (5 pts)
        full_text = get_document_text_odt(content_tree)
        if len(full_text) > 1500:
            score += 5
            feedback_parts.append("Content preserved")
        else:
            feedback_parts.append("Warning: Significant content missing")

        # 2. Title Formatting (5 pts)
        title_text = metadata.get("title_text", "ISO 9001:2015 Surveillance Audit Report")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        
        if title_bold and title_sized and title_centered > 0:
            score += 5
            feedback_parts.append("Title formatting OK")
        else:
            feedback_parts.append("Title missing required formatting")

        # 3. Main Sections H1 (15 pts)
        expected_h1 = metadata.get("expected_h1", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
        if h1_matched >= 4:
            score += 15
            feedback_parts.append(f"H1 Sections: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"H1 Sections: {h1_matched}/{h1_total} matched")

        # 4. Subsections H2 (10 pts)
        expected_h2 = metadata.get("expected_h2", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
        if h2_matched >= 4:
            score += 10
            feedback_parts.append(f"H2 Subsections: {h2_matched}/{h2_total} OK")
        else:
            feedback_parts.append(f"H2 Subsections: {h2_matched}/{h2_total} matched")

        # 5. Major Findings Alert (20 pts)
        major_b, major_r, _ = get_best_phrase_style(content_tree, styles, "MAJOR NON-CONFORMANCE")
        if major_b and major_r:
            score += 20
            feedback_parts.append("Major Non-Conformance styled Red and Bold")
        elif major_b or major_r:
            score += 10
            feedback_parts.append("Major Non-Conformance partially styled")
        else:
            feedback_parts.append("Major Non-Conformance missing red/bold")

        # 6. Minor Findings Alert (10 pts)
        minor_b, _, _ = get_best_phrase_style(content_tree, styles, "MINOR NON-CONFORMANCE")
        if minor_b:
            score += 10
            feedback_parts.append("Minor Non-Conformance styled Bold")
        else:
            feedback_parts.append("Minor Non-Conformance missing bold")

        # 7. Clause Italics (10 pts)
        clauses = metadata.get("clauses_to_italicize", [])
        italic_count = 0
        for clause in clauses:
            _, _, i = get_best_phrase_style(content_tree, styles, clause)
            if i: italic_count += 1
        
        if italic_count >= 3:
            score += 10
            feedback_parts.append(f"Clause Italics: {italic_count}/{len(clauses)} OK")
        else:
            feedback_parts.append(f"Clause Italics: only {italic_count}/{len(clauses)}")

        # 8. CAPA Table (20 pts)
        tables = get_odt_tables(content_tree)
        capa_table_valid = False
        for tbl in tables:
            rows = tbl.get('rows', [])
            if len(rows) >= 4:
                text_dump = " ".join([" ".join(c) for r in rows for c in r])
                if "CAPA-001" in text_dump and "MAJOR" in text_dump:
                    capa_table_valid = True
                    break
        
        if capa_table_valid:
            score += 20
            feedback_parts.append("CAPA Table successfully converted")
        else:
            feedback_parts.append("CAPA Table missing or malformed")

        # 9. TOC Generated (5 pts)
        if detect_toc_odt(content_tree):
            score += 5
            feedback_parts.append("Table of Contents found")
        else:
            feedback_parts.append("Table of Contents missing")

        passed = score >= 75 and capa_table_valid and major_r

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification encountered an error: {str(e)}"}