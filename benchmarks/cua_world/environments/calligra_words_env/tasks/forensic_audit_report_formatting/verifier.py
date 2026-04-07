#!/usr/bin/env python3
"""Verifier for the forensic_audit_report_formatting task."""

import logging
import os
import re
import sys
import json
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    cleanup_verification_temp,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_tables,
    get_odt_paragraphs,
    get_odt_styles,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_forensic_audit_report_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/project_chariot_investigation.odt")

    # Read the JSON result for timestamps
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        result_data = {"mtime": 0, "size": 0, "start_time": 0}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Parse ODT file
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []
        
        # ── 1. Check file modification (anti-gaming) ──
        mtime = result_data.get("mtime", 0)
        start_time = result_data.get("start_time", 0)
        file_modified = mtime > start_time and mtime > 0
        
        if file_modified:
            score += 5
            feedback_parts.append("File modified")
        else:
            feedback_parts.append("File not modified")

        # ── 2. Check content preservation (anti-gaming) ──
        full_text = get_document_text_odt(content_tree)
        orig_len = metadata.get("original_char_count", 2500)
        if len(full_text) >= orig_len * 0.85:
            score += 10
            feedback_parts.append("Content preserved")
            content_preserved = True
        else:
            feedback_parts.append(f"Content severely truncated ({len(full_text)} chars)")
            content_preserved = False

        # ── 3. Title formatted ──
        title_text = metadata.get("title_text", "Project Chariot: Forensic Audit Report")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)

        if title_bold and title_sized:
            score += 10
            feedback_parts.append("Title: bold and >=16pt")
        else:
            feedback_parts.append("Title not properly formatted")

        # ── 4. H1 Headings ──
        expected_h1 = metadata.get("expected_h1", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
        if h1_matched >= 4:
            score += 15
            feedback_parts.append(f"H1 headings: {h1_matched}/{h1_total}")
        elif h1_matched > 0:
            score += 5
            feedback_parts.append(f"H1 headings: partial {h1_matched}/{h1_total}")
        else:
            feedback_parts.append("H1 headings: 0")

        # ── 5. H2 Headings ──
        expected_h2 = metadata.get("expected_h2", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
        if h2_matched >= 2:
            score += 10
            feedback_parts.append(f"H2 headings: {h2_matched}/{h2_total}")
        elif h2_matched == 1:
            score += 5
            feedback_parts.append(f"H2 headings: partial {h2_matched}/{h2_total}")
        else:
            feedback_parts.append("H2 headings: 0")

        # ── 6. Transaction Table ──
        tables = get_odt_tables(content_tree)
        table_found = False
        table_pts = 0
        if len(tables) > 0:
            for tbl in tables:
                rows = tbl.get("rows", [])
                if len(rows) >= 4:
                    cols = len(rows[0]) if rows else 0
                    if cols >= 4:
                        table_found = True
                        table_pts = 20
                        break
        score += table_pts
        if table_found:
            feedback_parts.append("Transaction Table created")
        else:
            feedback_parts.append("Transaction Table not found or incomplete")

        # ── 7. Recommendations List ──
        paragraphs = get_odt_paragraphs(content_tree)
        list_items = [p for p in paragraphs if p.get('is_list_item')]
        list_matched = sum(1 for p in list_items if "mandatory dual-approval" in p['text'] or "Deploy automated threshold" in p['text'] or "comprehensive retroactive review" in p['text'] or "documented Statements of Work" in p['text'] or "independent vendor management office" in p['text'])
        
        if list_matched >= 3:
            score += 10
            feedback_parts.append("Recommendations List created")
        else:
            feedback_parts.append(f"Recommendations List incomplete ({list_matched}/5)")

        # ── 8. Entity Emphasis (Bold) ──
        entities = metadata.get("entities_to_bold", [])
        entity_bolds = 0
        for entity in entities:
            # We use a simple regex matching the entity to avoid missing it if punctuation surrounds it
            if check_text_bold_odt(content_tree, styles_tree, re.escape(entity)):
                entity_bolds += 1
        
        if entity_bolds == 2:
            score += 10
            feedback_parts.append("Entity Emphasis applied (2/2)")
        elif entity_bolds == 1:
            score += 5
            feedback_parts.append("Entity Emphasis applied (1/2)")
        else:
            feedback_parts.append("Entity Emphasis not applied")

        # ── 9. Justified Summary ──
        summary_text = "Between January 2024 and September 2025, the internal audit team"
        justified, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(summary_text[:30]), "justify")
        if justified > 0:
            score += 10
            feedback_parts.append("Executive Summary justified")
        else:
            feedback_parts.append("Executive Summary not justified")

        # Threshold to pass is 75 points + MUST include Transaction Table & Content Preservation
        passed = score >= 75 and table_found and content_preserved

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}
    finally:
        cleanup_verification_temp(temp_dir)