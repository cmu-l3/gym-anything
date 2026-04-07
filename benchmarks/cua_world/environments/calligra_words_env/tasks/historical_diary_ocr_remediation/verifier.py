#!/usr/bin/env python3
"""Verifier for the historical_diary_ocr_remediation task."""

import logging
import os
import re
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_text_bold_odt,
    check_paragraph_alignment_odt,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_styles,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _resolve_property(styles, style_name, prop_name):
    """Walk the style inheritance chain to find a property."""
    visited = set()
    current = style_name
    while current and current not in visited:
        visited.add(current)
        style_info = styles.get(current, {})
        if prop_name in style_info and style_info[prop_name]:
            return style_info[prop_name]
        current = style_info.get('parent', '')
    return ''

def verify_historical_diary_ocr_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/lewis_clark_ocr_raw.odt")

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        full_text = get_document_text_odt(content_tree)
        full_text_lower = full_text.lower()

        # 1. Content preservation & Watermark (10 pts)
        if "unique_watermark_str_9942" in full_text_lower:
            score += 10
            feedback_parts.append("Watermark found")
        else:
            feedback_parts.append("Watermark missing - text may have been replaced completely")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
            
        # 2. Paragraph Continuity (25 pts)
        paragraphs = get_odt_paragraphs(content_tree)
        non_empty_paras = [p for p in paragraphs if p['text'].strip()]
        
        # Original had ~35 non-empty paragraphs. Correctly combined, there should be < 12.
        if len(non_empty_paras) <= 12:
            score += 25
            feedback_parts.append(f"Paragraphs combined successfully (Count: {len(non_empty_paras)})")
        elif len(non_empty_paras) <= 22:
            score += 10
            feedback_parts.append(f"Paragraphs partially combined (Count: {len(non_empty_paras)})")
        else:
            feedback_parts.append(f"Paragraphs not combined (Count: {len(non_empty_paras)})")

        # 3. OCR Errors Fixed (25 pts)
        ocr_errors = ["moming", "govemment", "agarnst", "l804"]
        errors_found = [err for err in ocr_errors if err in full_text_lower]
        
        ocr_corrections = ["morning", "government", "against", "1804"]
        corrections_found = [corr for corr in ocr_corrections if corr in full_text_lower]
        
        if len(errors_found) == 0 and len(corrections_found) == 4:
            score += 25
            feedback_parts.append("All OCR character errors fixed")
        elif len(errors_found) < 4 or len(corrections_found) > 0:
            score += 10
            feedback_parts.append(f"Some OCR errors fixed ({len(errors_found)} remaining)")
        else:
            feedback_parts.append("OCR errors not fixed")

        # 4. Hyphens Rejoined (15 pts)
        hyphen_regexes = [r"pres-\s*ence", r"inhab-\s*itants", r"exped-\s*ition", r"provi-\s*sions"]
        hyphen_issues = sum(1 for regex in hyphen_regexes if re.search(regex, full_text_lower))
                
        joined_words = ["presence", "inhabitants", "expedition", "provisions"]
        joined_found = sum(1 for w in joined_words if w in full_text_lower)
        
        if hyphen_issues == 0 and joined_found >= 3:
            score += 15
            feedback_parts.append("All hyphenated words rejoined")
        elif hyphen_issues < 4:
            score += 5
            feedback_parts.append(f"Some hyphenated words rejoined ({hyphen_issues} still split)")
        else:
            feedback_parts.append("Hyphenated words not rejoined")

        # 5. Header Formatting (15 pts)
        headers = ["Monday, May 14, 1804", "Wednesday, May 16, 1804", "Monday, May 21, 1804"]
        headers_formatted = 0
        
        for header in headers:
            uncorrected = header.replace("1804", "l804")
            
            is_bold = check_text_bold_odt(content_tree, styles_tree, header) or \
                      check_text_bold_odt(content_tree, styles_tree, uncorrected)
            
            is_centered = False
            align_match, _ = check_paragraph_alignment_odt(content_tree, styles_tree, header, "center")
            if align_match == 0:
                align_match, _ = check_paragraph_alignment_odt(content_tree, styles_tree, uncorrected, "center")
                
            if align_match > 0:
                is_centered = True
                
            if is_bold and is_centered:
                headers_formatted += 1
                
        if headers_formatted == 3:
            score += 15
            feedback_parts.append("All date headers bold and centered")
        elif headers_formatted > 0:
            score += 5
            feedback_parts.append(f"Some headers formatted ({headers_formatted}/3)")
        else:
            feedback_parts.append("Headers not properly formatted")

        # 6. Body Text Formatting (10 pts)
        styles = get_odt_styles(content_tree, styles_tree)
        justified_indented_paras = 0
        body_para_count = 0
        
        for para in non_empty_paras:
            text = para['text'].strip()
            # Skip very short paragraphs (titles, dates, watermarks)
            if len(text) < 40:
                continue
                
            body_para_count += 1
            style_name = para.get('style_name', '')
            
            alignment = _resolve_property(styles, style_name, 'alignment')
            text_indent = _resolve_property(styles, style_name, 'text_indent')
                
            has_indent = False
            if text_indent:
                try:
                    val = float(re.sub(r'[^\d.]', '', text_indent))
                    if val > 0:
                        has_indent = True
                except ValueError:
                    pass
                    
            if alignment == 'justify' and has_indent:
                justified_indented_paras += 1
                
        if body_para_count > 0 and justified_indented_paras >= min(3, body_para_count):
            score += 10
            feedback_parts.append("Body paragraphs justified with first-line indent")
        elif justified_indented_paras > 0:
            score += 5
            feedback_parts.append("Some body paragraphs formatted correctly")
        else:
            feedback_parts.append("Body paragraphs lack justify alignment and/or indent")

        # Overall pass condition
        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification failed with error: {str(e)}"}