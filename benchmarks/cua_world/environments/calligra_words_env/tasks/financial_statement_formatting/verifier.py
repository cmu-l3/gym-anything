#!/usr/bin/env python3
"""Verifier for financial_statement_formatting task."""

import os
import sys
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_odt_styles,
    ODF_NS
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def parse_pt(size_str):
    if not size_str: return 0.0
    try:
        return float(size_str.replace('pt', '').strip())
    except Exception:
        return 0.0


def get_style_properties(styles_dict, style_name):
    props = {}
    chain = []
    current = style_name
    visited = set()
    while current and current not in visited:
        visited.add(current)
        chain.append(current)
        current = styles_dict.get(current, {}).get('parent', '')

    for s in reversed(chain):
        st = styles_dict.get(s, {})
        if 'bold' in st: props['bold'] = st['bold']
        if 'alignment' in st: props['alignment'] = st['alignment']
        if 'font_size' in st: props['font_size'] = st['font_size']
    return props


def verify_financial_statement_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/novatech_financials.odt")
    
    # 1. Check if the agent modified the file (Anti-gaming)
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_json = json.load(f)
    except Exception as e:
        result_json = {"file_modified_during_task": False}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not result_json.get("file_modified_during_task"):
        return {"passed": False, "score": 0, "feedback": "Document was not modified/saved by the agent."}

    # 2. Parse ODT XML
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj
    styles_dict = get_odt_styles(content_tree, styles_tree)

    score = 0
    max_score = 100
    feedback = []
    
    # Get all paragraphs
    paras = content_tree.findall('.//text:p', ODF_NS)
    headings = content_tree.findall('.//text:h', ODF_NS)
    all_text_blocks = paras + headings

    # ==========================================
    # Criterion 1: Title Formatting (15 pts)
    # ==========================================
    title_target = metadata.get("main_title", "NOVATECH SOLUTIONS INC.")
    title_bold = False
    title_center = False
    title_size = False
    
    for blk in all_text_blocks:
        text = "".join(blk.itertext())
        if title_target in text:
            style_name = blk.get(f"{{{ODF_NS['text']}}}style-name", "")
            props = get_style_properties(styles_dict, style_name)
            
            # Check for inline spans applying bold
            inline_bold = False
            for span in blk.findall('.//text:span', ODF_NS):
                span_style = span.get(f"{{{ODF_NS['text']}}}style-name", "")
                span_props = get_style_properties(styles_dict, span_style)
                if span_props.get('bold'):
                    inline_bold = True

            title_bold = props.get('bold') or inline_bold
            title_center = props.get('alignment') == 'center'
            title_size = parse_pt(props.get('font_size', '0')) >= 15.5
            break

    c1_pts = (5 if title_bold else 0) + (5 if title_center else 0) + (5 if title_size else 0)
    score += c1_pts
    feedback.append(f"Title Format: {c1_pts}/15 pts (Bold:{title_bold}, Center:{title_center}, >=16pt:{title_size})")

    # ==========================================
    # Criterion 2: Section Headings (15 pts)
    # ==========================================
    target_headings = metadata.get("headings", [])
    headings_found = 0
    for h_target in target_headings:
        for blk in all_text_blocks:
            if h_target in "".join(blk.itertext()):
                is_h1 = False
                if blk.tag == f"{{{ODF_NS['text']}}}h" and blk.get(f"{{{ODF_NS['text']}}}outline-level") == "1":
                    is_h1 = True
                
                style_name = blk.get(f"{{{ODF_NS['text']}}}style-name", "")
                if "Heading_20_1" in style_name or "Heading 1" in style_name:
                    is_h1 = True
                    
                if is_h1:
                    headings_found += 1
                break
                
    c2_pts = min(15, int((headings_found / max(1, len(target_headings))) * 15))
    score += c2_pts
    feedback.append(f"Heading 1: {headings_found}/{len(target_headings)} found ({c2_pts}/15 pts)")

    # ==========================================
    # Criterion 3: Narrative Justification (10 pts)
    # ==========================================
    narrative_target = "We have audited the accompanying"
    justified = False
    for p in paras:
        if narrative_target in "".join(p.itertext()):
            style_name = p.get(f"{{{ODF_NS['text']}}}style-name", "")
            props = get_style_properties(styles_dict, style_name)
            if props.get('alignment') == 'justify':
                justified = True
            break
            
    c3_pts = 10 if justified else 0
    score += c3_pts
    feedback.append(f"Narrative Justified: {justified} ({c3_pts}/10 pts)")

    # ==========================================
    # Criterion 4: Pagination / Page Breaks (20 pts)
    # ==========================================
    break_styles = set()
    for tree in [content_tree, styles_tree]:
        if tree is None: continue
        for style_elem in tree.findall('.//style:style', ODF_NS):
            para_props = style_elem.find('style:paragraph-properties', ODF_NS)
            if para_props is not None:
                if para_props.get(f"{{{ODF_NS['fo']}}}break-before") == "page" or \
                   para_props.get(f"{{{ODF_NS['fo']}}}break-after") == "page":
                    break_styles.add(style_elem.get(f"{{{ODF_NS['style']}}}name"))

    page_break_count = 0
    for blk in all_text_blocks:
        if blk.get(f"{{{ODF_NS['text']}}}style-name") in break_styles:
            page_break_count += 1
            
    c4_pts = min(20, int((min(page_break_count, 3) / 3.0) * 20))
    score += c4_pts
    feedback.append(f"Page Breaks: {page_break_count} found ({c4_pts}/20 pts)")

    # ==========================================
    # Criterion 5 & 6: Table Alignment (35 pts)
    # ==========================================
    header_aligned = 0
    header_bold = 0
    data_aligned = 0
    
    target_headers = ["2025 ($)", "2024 ($)"]
    target_data = metadata.get("numeric_samples", [])
    
    for p in paras:
        text = "".join(p.itertext()).strip()
        style_name = p.get(f"{{{ODF_NS['text']}}}style-name", "")
        props = get_style_properties(styles_dict, style_name)
        
        inline_bold = False
        for span in p.findall('.//text:span', ODF_NS):
            span_props = get_style_properties(styles_dict, span.get(f"{{{ODF_NS['text']}}}style-name", ""))
            if span_props.get('bold'): inline_bold = True

        is_center = props.get('alignment') == 'center'
        is_right = props.get('alignment') in ['end', 'right']
        is_bold = props.get('bold') or inline_bold

        for th in target_headers:
            if th in text:
                if is_center: header_aligned += 1
                if is_bold: header_bold += 1
                break

        for td in target_data:
            if td == text:
                if is_right: data_aligned += 1
                break

    c5_pts = min(15, (header_aligned + header_bold) // 2)
    score += c5_pts
    feedback.append(f"Table Headers Centered/Bold: {c5_pts}/15 pts")
    
    c6_pts = min(20, int((data_aligned / max(1, len(target_data))) * 20))
    score += c6_pts
    feedback.append(f"Table Numeric Data Right-Aligned: {data_aligned}/{len(target_data)} ({c6_pts}/20 pts)")

    # ==========================================
    # Criterion 7: Totals Emphasis (20 pts)
    # ==========================================
    target_totals = metadata.get("totals", [])
    totals_bold = 0
    
    for p in paras:
        text = "".join(p.itertext()).strip()
        for tt in target_totals:
            if tt == text:
                style_name = p.get(f"{{{ODF_NS['text']}}}style-name", "")
                props = get_style_properties(styles_dict, style_name)
                
                inline_bold = False
                for span in p.findall('.//text:span', ODF_NS):
                    span_props = get_style_properties(styles_dict, span.get(f"{{{ODF_NS['text']}}}style-name", ""))
                    if span_props.get('bold'): inline_bold = True
                
                if props.get('bold') or inline_bold:
                    totals_bold += 1
                break

    c7_pts = min(20, int((totals_bold / max(1, len(target_totals))) * 20))
    score += c7_pts
    feedback.append(f"Totals Bolded: {totals_bold}/{len(target_totals)} ({c7_pts}/20 pts)")

    # Determine overall pass
    passed = score >= 70 and page_break_count > 0 and data_aligned > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }