#!/usr/bin/env python3
"""Verifier for keynote_speech_formatting task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_odt_paragraphs,
    get_odt_styles,
    check_text_bold_odt,
    check_text_italic_odt
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

ODF_NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
}

def convert_to_inches(val_str):
    if not val_str: return 0.0
    val_str = val_str.lower().strip()
    try:
        if val_str.endswith('in'):
            return float(val_str[:-2])
        elif val_str.endswith('cm'):
            return float(val_str[:-2]) / 2.54
        elif val_str.endswith('mm'):
            return float(val_str[:-2]) / 25.4
        elif val_str.endswith('pt'):
            return float(val_str[:-2]) / 72.0
        return float(val_str)
    except Exception:
        return 0.0

def convert_to_points(val_str):
    if not val_str: return 0.0
    val_str = val_str.lower().strip()
    try:
        if val_str.endswith('pt'):
            return float(val_str[:-2])
        elif val_str.endswith('in'):
            return float(val_str[:-2]) * 72.0
        elif val_str.endswith('cm'):
            return float(val_str[:-2]) / 2.54 * 72.0
        elif val_str.endswith('mm'):
            return float(val_str[:-2]) / 25.4 * 72.0
        elif val_str.endswith('%'):
            return float(val_str[:-1]) / 100.0 * 12.0
        return float(val_str)
    except Exception:
        return 0.0

def get_page_margins(styles_tree):
    margins = {'left': None, 'right': None}
    if styles_tree is not None:
        for pl in styles_tree.findall('.//style:page-layout-properties', ODF_NS):
            left = pl.get(f"{{{ODF_NS['fo']}}}margin-left")
            right = pl.get(f"{{{ODF_NS['fo']}}}margin-right")
            if left: margins['left'] = convert_to_inches(left)
            if right: margins['right'] = convert_to_inches(right)
    return margins

def has_page_break_before(para_elem, content_tree, styles_tree):
    style_name = para_elem.get(f"{{{ODF_NS['text']}}}style-name", "")
    if not style_name:
        return False
        
    for tree in [content_tree, styles_tree]:
        if tree is None: continue
        style_elems = tree.findall(f".//style:style[@style:name='{style_name}']", ODF_NS)
        for se in style_elems:
            pp = se.find(f"style:paragraph-properties", ODF_NS)
            if pp is not None:
                bb = pp.get(f"{{{ODF_NS['fo']}}}break-before")
                if bb == "page":
                    return True
            parent = se.get(f"{{{ODF_NS['style']}}}parent-style-name")
            if parent:
                parent_se = tree.findall(f".//style:style[@style:name='{parent}']", ODF_NS)
                for pse in parent_se:
                    ppp = pse.find(f"style:paragraph-properties", ODF_NS)
                    if ppp is not None:
                        pbb = ppp.get(f"{{{ODF_NS['fo']}}}break-before")
                        if pbb == "page":
                            return True
    return False

def check_footer_text(styles_tree, expected_text):
    if styles_tree is None:
        return False
    footers = styles_tree.findall(".//style:footer", ODF_NS)
    for f in footers:
        text = "".join(f.itertext())
        if expected_text.lower() in text.lower():
            return True
    return False

def check_paragraph_typography(para, styles):
    style_name = para.get('style_name', '')
    curr = styles.get(style_name, {})
    font_size = curr.get('font_size', '')
    line_height = curr.get('line_height', '')
    parent = curr.get('parent', '')
    
    for _ in range(3):
        if (font_size and line_height) or not parent:
            break
        p_style = styles.get(parent, {})
        if not font_size:
            font_size = p_style.get('font_size', '')
        if not line_height:
            line_height = p_style.get('line_height', '')
        parent = p_style.get('parent', '')
        
    return font_size, line_height

def is_double_spaced(line_height):
    if not line_height: return False
    line_height = line_height.lower().strip()
    if line_height in ["200%", "2", "2.0"]: return True
    try:
        if line_height.endswith('in'):
            val = float(line_height[:-2])
            if val >= 0.35: return True
        elif line_height.endswith('cm'):
            val = float(line_height[:-2])
            if val >= 0.8: return True
    except:
        pass
    return False

def verify_keynote_speech_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/keynote_draft.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # 1. Page Margins (20 points)
        margins = get_page_margins(styles_tree)
        left = margins.get('left')
        right = margins.get('right')
        margin_score = 0
        
        if left is not None and abs(left - 2.0) <= 0.15:
            margin_score += 10
        if right is not None and abs(right - 2.0) <= 0.15:
            margin_score += 10
            
        score += margin_score
        if margin_score == 20:
            feedback_parts.append("Page margins: Left/Right 2.0in OK")
        else:
            feedback_parts.append(f"Page margins: Left={left}in, Right={right}in (Expected 2.0in)")

        # Typography checks over body text
        paragraphs = get_odt_paragraphs(content_tree)
        styles = get_odt_styles(content_tree, styles_tree)
        
        body_paras = [p for p in paragraphs if len(p['text']) > 20 and not p['text'].startswith("[")]
        
        fs_count = 0
        ls_count = 0
        
        for p in body_paras:
            fs, ls = check_paragraph_typography(p, styles)
            if convert_to_points(fs) >= 17.0:
                fs_count += 1
            if is_double_spaced(ls):
                ls_count += 1
                
        # 2. Font Size (15 points)
        fs_ratio = fs_count / max(1, len(body_paras))
        if len(body_paras) > 0 and fs_ratio >= 0.5:
            score += 15
            feedback_parts.append(f"Font size: >=18pt ({fs_ratio*100:.0f}%) OK")
        else:
            feedback_parts.append(f"Font size: <18pt ({fs_ratio*100:.0f}%)")
                
        # 3. Line Spacing (15 points)
        ls_ratio = ls_count / max(1, len(body_paras))
        if len(body_paras) > 0 and ls_ratio >= 0.5:
            score += 15
            feedback_parts.append(f"Line spacing: Double ({ls_ratio*100:.0f}%) OK")
        else:
            feedback_parts.append(f"Line spacing: Not double ({ls_ratio*100:.0f}%)")
                
        # 4. Stage Cues Styled (25 points)
        cues = metadata.get("stage_cues", [])
        cues_styled = 0
        for cue in cues:
            cue_pattern = re.escape(cue)
            bold = check_text_bold_odt(content_tree, styles_tree, cue_pattern)
            italic = check_text_italic_odt(content_tree, styles_tree, cue_pattern)
            if bold and italic:
                cues_styled += 1
                
        if len(cues) > 0:
            cue_ratio = cues_styled / len(cues)
            if cue_ratio >= 0.8:
                score += 25
                feedback_parts.append(f"Stage cues: {cues_styled}/{len(cues)} Bold+Italic OK")
            elif cue_ratio > 0:
                score += int(25 * cue_ratio)
                feedback_parts.append(f"Stage cues: {cues_styled}/{len(cues)} Bold+Italic (Partial)")
            else:
                feedback_parts.append(f"Stage cues: {cues_styled}/{len(cues)} styled")
                
        # 5. Section Page Breaks (15 points)
        section_markers = metadata.get("section_markers", [])
        breaks_found = 0
        for p in paragraphs:
            for marker in section_markers:
                if p['text'].strip().startswith(marker):
                    if has_page_break_before(p['element'], content_tree, styles_tree):
                        breaks_found += 1
                    break
                    
        if len(section_markers) > 0:
            if breaks_found == len(section_markers):
                score += 15
                feedback_parts.append(f"Page breaks: {breaks_found}/{len(section_markers)} OK")
            else:
                score += int(15 * (breaks_found / len(section_markers)))
                feedback_parts.append(f"Page breaks: {breaks_found}/{len(section_markers)}")
                
        # 6. Footer Text (10 points)
        footer_expected = metadata.get("footer_text", "EMBARGOED DRAFT")
        has_footer = check_footer_text(styles_tree, footer_expected)
        if has_footer:
            score += 10
            feedback_parts.append(f"Footer: '{footer_expected}' found OK")
        else:
            feedback_parts.append(f"Footer: '{footer_expected}' NOT found")

        # Key criteria check
        categories_passed = sum([
            margin_score > 0,
            (fs_ratio >= 0.5) if len(body_paras) > 0 else False,
            (ls_ratio >= 0.5) if len(body_paras) > 0 else False,
            cues_styled >= 3,
            breaks_found >= 1,
            has_footer
        ])
        
        passed = score >= 70 and categories_passed >= 3

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed with error: {str(e)}"
        }