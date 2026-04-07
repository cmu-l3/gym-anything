#!/usr/bin/env python3
"""Verifier for the it_incident_rca_formatting task."""

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
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
    get_odt_tables
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_it_incident_rca_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/INC-2026-042_PostMortem.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj
    
    score = 0
    feedback_parts = []
    
    # 1. Title formatting (10 pts)
    title_text = "INC-2026-042 Post-Mortem Report"
    title_bold = check_text_bold_odt(content_tree, styles_tree, re.escape(title_text))
    title_sized = check_text_font_size_odt(content_tree, styles_tree, re.escape(title_text), 16.0)
    title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(title_text), "center")
    
    if title_bold and title_sized and title_centered > 0:
        score += 10
        feedback_parts.append("Title formatting OK")
    else:
        feedback_parts.append("Title formatting incomplete")
        
    # 2. Heading 1 Sections (15 pts)
    expected_h1 = metadata.get("expected_h1_sections", [
        "Executive Summary",
        "Impact",
        "Timeline",
        "Log Excerpts",
        "Root Cause Analysis (Five Whys)",
        "Action Items"
    ])
    h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
    if h1_matched >= 5:
        score += 15
        feedback_parts.append(f"H1 sections: {h1_matched}/{h1_total} OK")
    else:
        feedback_parts.append(f"H1 sections: {h1_matched}/{h1_total} (need 5)")
        
    # 3. Tables (30 pts: 15 Timeline, 15 Action Items)
    tables = get_odt_tables(content_tree)
    has_timeline = False
    has_actions = False
    
    for tbl in tables:
        tbl_text = " ".join([" ".join(row) for row in tbl.get("rows", [])]).lower()
        if "timestamp" in tbl_text and "09:12" in tbl_text:
            has_timeline = True
        if "owner" in tbl_text and "j. smith" in tbl_text:
            has_actions = True
            
    if has_timeline:
        score += 15
        feedback_parts.append("Timeline table OK")
    else:
        feedback_parts.append("Timeline table missing")
        
    if has_actions:
        score += 15
        feedback_parts.append("Action Items table OK")
    else:
        feedback_parts.append("Action Items table missing")
        
    # 4. Monospace logs (15 pts)
    log_text = "FATAL: remaining connection slots"
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)
    
    def _resolve_font_name(styles_dict, st_name):
        visited = set()
        curr = st_name
        while curr and curr not in visited:
            visited.add(curr)
            info = styles_dict.get(curr, {})
            if info.get('font_name'):
                return info.get('font_name')
            curr = info.get('parent', '')
        return ""
        
    monospace_ok = False
    for para in paragraphs:
        if log_text.lower() in para['text'].lower():
            st_name = para.get('style_name', '')
            fname = _resolve_font_name(styles, st_name)
            if fname and ("mono" in fname.lower() or "courier" in fname.lower() or "consolas" in fname.lower()):
                monospace_ok = True
                break
                
            # Check inline spans if whole paragraph is not styled
            for child in para.get('element', []):
                if child.tag.endswith("span"):
                    span_style = ""
                    for key, val in child.attrib.items():
                        if key.endswith('style-name'):
                            span_style = val
                            break
                    if span_style:
                        span_fname = _resolve_font_name(styles, span_style)
                        if span_fname and ("mono" in span_fname.lower() or "courier" in span_fname.lower() or "consolas" in span_fname.lower()):
                            monospace_ok = True
                            break

    if monospace_ok:
        score += 15
        feedback_parts.append("Monospace logs OK")
    else:
        feedback_parts.append("Monospace logs missing")
        
    # 5. Numbered List (15 pts)
    list_items = [p for p in paragraphs if p.get('is_list_item')]
    list_ok = False
    if len(list_items) >= 4:
        list_text = " ".join(p['text'] for p in list_items).lower()
        if "split-brain" in list_text and "timeout" in list_text:
            list_ok = True

    if list_ok:
        score += 15
        feedback_parts.append("Numbered list OK")
    else:
        feedback_parts.append("Numbered list missing")
        
    # 6. Body Alignment (5 pts)
    samples = [
        "On October 14, 2026, the primary production",
        "The checkout service was completely unavailable"
    ]
    justified = 0
    for s in samples:
        matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(s), "justify")
        if matched > 0:
            justified += 1
            
    if justified >= 1:
        score += 5
        feedback_parts.append("Body justified OK")
    else:
        feedback_parts.append("Body justified missing")
        
    # 7. Content preservation (5 pts)
    full_text = get_document_text_odt(content_tree).lower()
    keywords = [
        "inc-2026-042",
        "split-brain",
        "12,400",
        "j. smith"
    ]
    k_found = sum(1 for k in keywords if k in full_text)
    if k_found >= 3:
        score += 5
        feedback_parts.append("Content preserved OK")
    else:
        feedback_parts.append("Content missing")

    # Anti-gaming: At least one main structural criteria (table/list/monospace) must be met
    key_criteria_met = has_timeline or has_actions or monospace_ok or list_ok
    passed = score >= 75 and key_criteria_met

    cleanup_verification_temp(temp_dir)
    return {
        "passed": bool(passed),
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }