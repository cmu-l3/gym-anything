#!/usr/bin/env python3
"""Verifier for the archival_finding_aid_formatting task."""

import json
import logging
import os
import re
import sys
import tempfile

# Add shared verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    check_text_bold_odt,
    check_text_font_size_odt,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_paragraphs,
    get_odt_tables,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_archival_finding_aid(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/sba_finding_aid.odt")

    # Fetch export info for anti-gaming modification check
    modified_during_task = False
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_export.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            export_data = json.load(f)
            modified_during_task = export_data.get("modified_during_task", False)
    except Exception as e:
        logger.warning(f"Failed to read task_export.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []

        # Anti-gaming 
        if not modified_during_task:
            return {"passed": False, "score": 0, "feedback": "Document was not saved/modified during the task."}

        # ── Criterion 1: Title Formatting (10 pts)
        title_text = metadata.get("title_text", "Susan B. Anthony Papers")
        title_pattern = re.escape(title_text)
        title_centered, _ = check_paragraph_alignment_odt(content_tree, styles_tree, title_pattern, "center")
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 16.0)

        if title_centered > 0 and title_bold and title_sized:
            score += 10
            feedback_parts.append("Title formatting OK")
        else:
            issues = []
            if title_centered == 0: issues.append("not centered")
            if not title_bold: issues.append("not bold")
            if not title_sized: issues.append("< 16pt")
            feedback_parts.append(f"Title issues: {', '.join(issues)}")

        # ── Criterion 2: Main Sections H1 (20 pts)
        h1_sections = metadata.get("h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, h1_sections, 1)
        if h1_matched >= 5:
            score += 20
            feedback_parts.append(f"H1 sections: {h1_matched}/{h1_total} OK")
        else:
            score += int(20 * (h1_matched / max(1, len(h1_sections))))
            feedback_parts.append(f"H1 sections: {h1_matched}/{h1_total}")

        # ── Criterion 3: Series Titles H2 (15 pts)
        h2_sections = metadata.get("h2_sections", [])
        h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, h2_sections, 2)
        if h2_matched >= 3:
            score += 15
            feedback_parts.append(f"H2 sections: {h2_matched}/{h2_total} OK")
        else:
            score += int(15 * (h2_matched / max(1, len(h2_sections))))
            feedback_parts.append(f"H2 sections: {h2_matched}/{h2_total}")

        # ── Criterion 4: Subject List (15 pts)
        paragraphs = get_odt_paragraphs(content_tree)
        subject_terms = metadata.get("subject_terms", [])
        list_items_text = [p['text'].lower() for p in paragraphs if p.get('is_list_item')]
        
        # Check how many subject terms appear in list items
        terms_in_list = 0
        for term in subject_terms:
            if any(term.lower() in li_text for li_text in list_items_text):
                terms_in_list += 1

        if terms_in_list >= 4:
            score += 15
            feedback_parts.append(f"Subject bulleted list OK ({terms_in_list} terms found)")
        elif terms_in_list > 0:
            score += 5
            feedback_parts.append(f"Partial subject list ({terms_in_list} terms found)")
        else:
            feedback_parts.append("Subject terms not converted to a bulleted list")

        # ── Criterion 5: Container Table (20 pts)
        tables = get_odt_tables(content_tree)
        table_found = False

        for tbl in tables:
            rows = tbl.get("rows", [])
            if len(rows) >= 5:
                # Validate if this is the migrated table
                tbl_text = " ".join([" ".join(r).lower() for r in rows])
                if "box" in tbl_text and "folder" in tbl_text and "correspondence" in tbl_text:
                    table_found = True
                    break
        
        if table_found:
            score += 20
            feedback_parts.append("Container table created OK")
        else:
            feedback_parts.append("Container table missing or incomplete")

        # ── Criterion 6: Table Header Bold (5 pts)
        if table_found:
            if check_text_bold_odt(content_tree, styles_tree, "Box") or check_text_bold_odt(content_tree, styles_tree, "Folder"):
                score += 5
                feedback_parts.append("Table header bold OK")
            else:
                feedback_parts.append("Table header not bold")
        else:
            feedback_parts.append("Table header check skipped (no table)")

        # ── Criterion 7: Text Justification (5 pts)
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sample), "justify")
            if matched > 0:
                justified_count += 1
        
        if justified_count >= 2:
            score += 5
            feedback_parts.append("Narrative text justified OK")
        else:
            feedback_parts.append(f"Narrative text not justified ({justified_count}/{len(body_samples)})")

        # ── Criterion 8: Content Preservation (10 pts)
        full_text = get_document_text_odt(content_tree).lower()
        keywords = metadata.get("content_keywords", [])
        kw_found = sum(1 for kw in keywords if kw.lower() in full_text)
        if kw_found >= len(keywords) - 1:
            score += 10
            feedback_parts.append("Content preservation OK")
        else:
            feedback_parts.append(f"Content missing ({kw_found}/{len(keywords)} keywords found)")

        # ── Hybrid VLM Checking (Trajectory Frames)
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames and env_info.get("query_vlm"):
                prompt = """Analyze these screenshots of a user formatting a document in a word processor.
Did the user interact with the UI to format the document (e.g., using 'Insert Table' features, applying bulleted lists, or clicking formatting toolbars)?
Respond with JSON: {"active_formatting": true} or {"active_formatting": false}"""
                vlm_res = env_info["query_vlm"](prompt=prompt, images=frames)
                if vlm_res and vlm_res.get("success"):
                    parsed = vlm_res.get("parsed", {})
                    if parsed.get("active_formatting", False):
                        logger.info("VLM confirmed active interaction.")
                    else:
                        logger.warning("VLM did not confirm active formatting interaction.")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")

        # Final pass constraints
        table_critical = table_found
        list_critical = (terms_in_list >= 4)
        passed = (score >= 75) and table_critical and list_critical

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error in verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}