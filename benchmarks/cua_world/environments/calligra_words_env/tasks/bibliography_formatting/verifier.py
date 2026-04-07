#!/usr/bin/env python3
"""Verifier for the bibliography_formatting task."""

import json
import logging
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    copy_and_parse_document,
    get_odt_paragraphs,
    get_odt_styles,
    get_document_text_odt,
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_bibliography_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/vaccine_hesitancy_brief.odt")
    expected_authors = metadata.get("expected_authors_order", [])
    journal_keywords = metadata.get("journal_keywords", [])
    body_samples = metadata.get("body_preservation_samples", [])

    # Fetch export result to check if file was even modified
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_data = json.load(f)
    except Exception as e:
        export_data = {"file_modified_during_task": False}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_data.get("file_modified_during_task", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Document was not modified. Doing nothing earns 0 points."
        }

    # Fetch and parse ODT
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document."}

    content_tree, styles_tree = doc_obj
    paragraphs = get_odt_paragraphs(content_tree)
    styles = get_odt_styles(content_tree, styles_tree)
    full_text = get_document_text_odt(content_tree).lower()

    score = 0
    feedback_parts = []
    
    # Check body preservation (5 pts)
    body_preserved = 0
    for sample in body_samples:
        if sample.lower() in full_text:
            body_preserved += 1
            
    if body_preserved >= 2:
        score += 5
        feedback_parts.append("Body preserved")
    else:
        feedback_parts.append(f"Body NOT preserved ({body_preserved}/{len(body_samples)})")

    # Locate "References" and the reference items
    ref_idx = -1
    for idx, p in enumerate(paragraphs):
        if p['text'].strip().lower() == "references":
            ref_idx = idx
            break

    if ref_idx == -1:
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts) + " | 'References' label missing."
        }

    ref_para = paragraphs[ref_idx]
    
    # 1. References heading is H1 (10 pts)
    is_h1 = (ref_para.get('outline_level') == 1) or ('Heading' in ref_para.get('style_name', '') and '1' in ref_para.get('style_name', ''))
    if not is_h1:
        # Fallback element check
        if ref_para['element'].tag.endswith('h'):
            is_h1 = True
            
    if is_h1:
        score += 10
        feedback_parts.append("References is H1")
    else:
        feedback_parts.append("References not formatted as H1")

    # Filter actual citations
    citations = []
    for p in paragraphs[ref_idx+1:]:
        t = p['text'].strip()
        if len(t) > 20:  # Valid citation
            citations.append(p)

    # 2. Alphabetical Order (20 pts)
    # Extract leading words and count how many appear in the exact correct sequence
    authors_found = [c['text'].split(',')[0].strip() for c in citations]
    correct_order_count = 0
    for found, expected in zip(authors_found, expected_authors):
        if found.lower() == expected.lower():
            correct_order_count += 1
            
    if correct_order_count >= 13:
        score += 20
        feedback_parts.append(f"Order OK ({correct_order_count}/{len(expected_authors)})")
    elif correct_order_count >= 8:
        score += 10
        feedback_parts.append(f"Order partially correct ({correct_order_count}/{len(expected_authors)})")
    else:
        feedback_parts.append(f"Order incorrect ({correct_order_count}/{len(expected_authors)})")

    # Style Checks on citations
    hanging_indents = 0
    italic_titles = 0
    courier_remaining = 0
    pt10_remaining = 0
    authors_present = set()

    for p in citations:
        text_lower = p['text'].lower()
        style_name = p.get('style_name', '')
        p_style = styles.get(style_name, {})
        
        # Resolve parent styles
        font_name = p_style.get('font_name', '').lower()
        font_size = p_style.get('font_size', '')
        parent = p_style.get('parent')
        if not font_name and parent:
            font_name = styles.get(parent, {}).get('font_name', '').lower()
        if not font_size and parent:
            font_size = styles.get(parent, {}).get('font_size', '')

        # Track fonts
        if "courier" in font_name:
            courier_remaining += 1
        if "10pt" in font_size:
            pt10_remaining += 1
            
        # Track Authors
        for auth in expected_authors:
            if auth.lower() in text_lower:
                authors_present.add(auth)

        # 3. Hanging Indent
        ml = p_style.get('margin_left', '0')
        ti = p_style.get('text_indent', '0')
        try:
            ml_val = float(re.sub(r'[^\d.-]', '', ml)) if ml else 0
            ti_val = float(re.sub(r'[^\d.-]', '', ti)) if ti else 0
            if ml_val > 0 and ti_val < 0:
                hanging_indents += 1
        except:
            pass

        # 4. Italicized Titles
        # Find spans inside element
        spans = p['element'].findall('.//{urn:oasis:names:tc:opendocument:xmlns:text:1.0}span')
        has_correct_italic = False
        for span in spans:
            span_style_name = span.get('{urn:oasis:names:tc:opendocument:xmlns:text:1.0}style-name')
            span_style = styles.get(span_style_name, {})
            if span_style.get('italic', False):
                span_text = "".join(span.itertext()).lower()
                for kw in journal_keywords:
                    if kw.lower() in span_text:
                        has_correct_italic = True
                        break
        if has_correct_italic:
            italic_titles += 1

    # Hanging indents score (15 pts)
    if hanging_indents >= 12:
        score += 15
        feedback_parts.append(f"Hanging indents OK ({hanging_indents}/15)")
    elif hanging_indents >= 6:
        score += 7
        feedback_parts.append(f"Hanging indents partial ({hanging_indents}/15)")
    else:
        feedback_parts.append(f"Missing hanging indents ({hanging_indents}/15)")

    # Italics score (20 pts)
    if italic_titles >= 12:
        score += 20
        feedback_parts.append(f"Italics OK ({italic_titles}/15)")
    elif italic_titles >= 6:
        score += 10
        feedback_parts.append(f"Italics partial ({italic_titles}/15)")
    else:
        feedback_parts.append(f"Missing italics ({italic_titles}/15)")

    # Font type fix (10 pts)
    if courier_remaining == 0:
        score += 10
        feedback_parts.append("Courier fonts fixed")
    else:
        feedback_parts.append(f"Courier fonts remaining: {courier_remaining}")

    # Font size fix (5 pts)
    if pt10_remaining == 0:
        score += 5
        feedback_parts.append("Font sizes fixed")
    else:
        feedback_parts.append(f"10pt fonts remaining: {pt10_remaining}")

    # Content Preservation (10 pts)
    if len(authors_present) >= 14:
        score += 10
        feedback_parts.append("References preserved")
    else:
        feedback_parts.append(f"References lost! Only {len(authors_present)}/15 found")

    # VLM Verification (5 pts)
    vlm_score = 0
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = (
                "Review these screenshots of an agent using Calligra Words. "
                "The task was to format a References section (alphabetizing, setting hanging indents, adding italics). "
                "Do these images show genuine progression of formatting work in the document, "
                "such as text selections, paragraph setting dialogs, or moving citations? "
                "Reply ONLY in valid JSON: {'genuine_work': true/false}"
            )
            try:
                vlm_result = query_vlm(prompt=prompt, images=frames)
                if vlm_result.get("success") and vlm_result.get("parsed", {}).get("genuine_work", False):
                    vlm_score = 5
                    feedback_parts.append("VLM visual verify OK")
                else:
                    feedback_parts.append("VLM visual verify failed")
            except Exception as e:
                logger.warning(f"VLM error: {e}")
    
    score += vlm_score

    passed = score >= 65 and export_data.get("file_modified_during_task", False)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }