#!/usr/bin/env python3
"""Verifier for the organic_audit_report_formatting task."""

import json
import logging
import os
import re
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    copy_and_parse_document,
    detect_toc_odt,
    get_odt_tables,
    ODF_NS
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_organic_audit_report(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/sunny_creek_audit_report.odt")

    # Read the pre-exported result file to verify anti-gaming (file modification)
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not read export result JSON: {e}")
        export_result = {"file_modified": True} # Fallback
    finally:
        if os.path.exists(temp_res.name):
            os.unlink(temp_res.name)

    if not export_result.get("file_modified", False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Document was not modified. Task was not completed."
        }

    # Fetch and parse the document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []

    try:
        # ── 1. Title formatting (bold, >=16pt, centered) [15 pts] ──
        title_text = metadata.get("title_text", "Sunny Creek Organics - Annual On-Site Inspection Report")
        title_pattern = re.escape(title_text)
        
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        
        title_score = 0
        if title_bold: title_score += 5
        if title_sized: title_score += 5
        if title_centered > 0: title_score += 5
        score += title_score
        
        if title_score == 15:
            feedback_parts.append("Title formatted perfectly")
        else:
            feedback_parts.append(f"Title partial ({title_score}/15): bold={title_bold}, sized={title_sized}, centered={title_centered>0}")

        # ── 2. Heading 1 (6 sections) [15 pts] ──
        h1_sections = metadata.get("expected_h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, h1_sections, 1)
        if h1_matched >= 5:
            score += 15
            feedback_parts.append(f"H1 Sections OK ({h1_matched}/{h1_total})")
        else:
            score += h1_matched * 2
            feedback_parts.append(f"H1 Sections missed: only {h1_matched}/{h1_total}")

        # ── 3. Heading 2 (4 sections) [10 pts] ──
        h2_sections = metadata.get("expected_h2_subsections", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, h2_sections, 2)
        if h2_matched >= 3:
            score += 10
            feedback_parts.append(f"H2 Sections OK ({h2_matched}/{h2_total})")
        else:
            score += h2_matched * 2
            feedback_parts.append(f"H2 Sections missed: only {h2_matched}/{h2_total}")

        # ── 4. Table created [15 pts] ──
        tables = get_odt_tables(content_tree)
        table_keywords = metadata.get("table_keywords", [])
        table_found = False
        
        for tbl in tables:
            rows = tbl.get("rows", [])
            # Check for grid size and contents
            if len(rows) >= 4:
                table_text = " ".join([" ".join(row) for row in rows]).lower()
                hits = sum(1 for kw in table_keywords if kw.lower() in table_text)
                if hits >= 3:
                    table_found = True
                    break
        
        if table_found:
            score += 15
            feedback_parts.append("Crop table successfully created")
        else:
            feedback_parts.append("Crop table missing or incorrect")

        # ── 5. Bulleted List created [10 pts] ──
        list_keywords = metadata.get("list_keywords", [])
        lists = content_tree.findall('.//text:list', ODF_NS)
        list_items_found = 0
        
        for lst in lists:
            items = lst.findall('.//text:list-item', ODF_NS)
            for item in items:
                # Recursively extract text
                item_text = "".join(item.itertext()).lower()
                for kw in list_keywords:
                    if kw.lower() in item_text:
                        list_items_found += 1
                        
        if list_items_found >= 3:
            score += 10
            feedback_parts.append("Input materials bulleted list found")
        else:
            feedback_parts.append("Bulleted list for inputs missing")

        # ── 6. Citations Bolded [15 pts] ──
        citations = metadata.get("citations_to_bold", [])
        bold_citations_count = 0
        for cit in citations:
            if check_text_bold_odt(content_tree, styles_tree, re.escape(cit)):
                bold_citations_count += 1
                
        if bold_citations_count >= 3:
            score += 15
            feedback_parts.append(f"Citations bolded OK ({bold_citations_count}/4)")
        else:
            score += bold_citations_count * 3
            feedback_parts.append(f"Citations missing bold ({bold_citations_count}/4)")

        # ── 7. Body text justified [10 pts] ──
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sample), "justify")
            if matched > 0:
                justified_count += 1

        if justified_count >= 2:
            score += 10
            feedback_parts.append("Body paragraphs justified")
        else:
            feedback_parts.append("Body paragraphs not properly justified")

        # ── 8. Table of Contents [10 pts] ──
        if detect_toc_odt(content_tree):
            score += 10
            feedback_parts.append("TOC present")
        else:
            feedback_parts.append("TOC missing")

        passed = score >= 75 and table_found and h1_matched >= 5

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
            "feedback": f"Verification error: {e}"
        }