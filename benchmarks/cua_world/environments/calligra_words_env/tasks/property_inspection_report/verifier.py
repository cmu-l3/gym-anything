#!/usr/bin/env python3
"""Verifier for the property_inspection_report task."""

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
)

# Optional import for VLM trajectory verification
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_property_inspection_report(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/inspection_report.odt")

    # Anti-gaming: Check export script results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            export_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read export result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    if not export_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Document not saved or does not exist."}
    
    if not export_result.get("file_modified_during_task", False):
        return {"passed": False, "score": 0, "feedback": "Document was not modified during the task duration."}

    # Fetch and parse the ODT document
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        criteria_passed = 0
        score = 0
        feedback_parts = []

        # ----------------------------------------------------------------------
        # Criterion 1: Title formatting (bold, >=14pt) [10 points]
        # ----------------------------------------------------------------------
        title_text = metadata.get("title_text", "Residential Property Inspection Report")
        title_pattern = re.escape(title_text)
        title_bold = check_text_bold_odt(content_tree, styles_tree, title_pattern)
        title_sized = check_text_font_size_odt(content_tree, styles_tree, title_pattern, 14.0)

        if title_bold and title_sized:
            score += 10
            feedback_parts.append("Title: bold and >=14pt OK")
        else:
            feedback_parts.append(f"Title formatting incomplete (Bold: {title_bold}, >=14pt: {title_sized})")

        # ----------------------------------------------------------------------
        # Criterion 2: Property info block labels (bold) [10 points]
        # ----------------------------------------------------------------------
        property_labels = metadata.get("property_labels", [])
        labels_bold_count = 0
        for label in property_labels:
            if check_text_bold_odt(content_tree, styles_tree, re.escape(label)):
                labels_bold_count += 1
        
        if len(property_labels) > 0 and labels_bold_count >= 4:
            score += 10
            feedback_parts.append(f"Property info labels: {labels_bold_count}/{len(property_labels)} bold OK")
        else:
            feedback_parts.append(f"Property info labels: only {labels_bold_count}/{len(property_labels)} bold (need 4)")

        # ----------------------------------------------------------------------
        # Criterion 3: H1 section headings (>=7/10) [15 points]
        # ----------------------------------------------------------------------
        h1_sections = metadata.get("h1_sections", [])
        h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, h1_sections, 1)
        if h1_matched >= 7:
            score += 15
            feedback_parts.append(f"Heading 1 sections: {h1_matched}/{h1_total} OK")
        else:
            feedback_parts.append(f"Heading 1 sections: only {h1_matched}/{h1_total} (need 7)")

        # ----------------------------------------------------------------------
        # Criterion 4: H2 subsection headings (>=6) [10 points]
        # We look for "Observations" and "Recommendations". There are 9 of each in the doc.
        # We just need to check if H2 style is applied to instances of these words.
        # ----------------------------------------------------------------------
        h2_subsections = metadata.get("h2_subsections", ["Observations", "Recommendations"])
        
        # Count total instances of these words in H2 elements manually to get total matched instances
        ns_text = "urn:oasis:names:tc:opendocument:xmlns:text:1.0"
        h2_instances_found = 0
        for elem in content_tree.findall(f".//{{{ns_text}}}h"):
            if elem.get(f"{{{ns_text}}}outline-level") == "2":
                text_content = "".join(elem.itertext()).strip()
                if any(sub in text_content for sub in h2_subsections):
                    h2_instances_found += 1
        
        if h2_instances_found >= 6:
            score += 10
            feedback_parts.append(f"Heading 2 subsections: {h2_instances_found} instances OK")
        else:
            feedback_parts.append(f"Heading 2 subsections: only {h2_instances_found} instances (need 6)")

        # ----------------------------------------------------------------------
        # Criterion 5 & 6: Summary and Per-section Rating Tables [25 points total]
        # Summary table (>=8 rows) [10 pts], Section tables (>=5 additional) [15 pts]
        # ----------------------------------------------------------------------
        tables = get_odt_tables(content_tree)
        summary_tables = 0
        section_tables = 0
        
        for tbl in tables:
            num_rows = len(tbl.get("rows", []))
            if num_rows >= 8:
                summary_tables += 1
            elif num_rows >= 2:
                section_tables += 1
                
        if summary_tables >= 1:
            score += 10
            feedback_parts.append("Summary table (>=8 rows) OK")
        else:
            feedback_parts.append("Summary table not found")
            
        if section_tables >= 5 or (len(tables) >= 6 and summary_tables == 0):
            score += 15
            feedback_parts.append(f"Section tables: {section_tables} OK")
        else:
            feedback_parts.append(f"Section tables: only {section_tables} found (need 5)")

        # ----------------------------------------------------------------------
        # Criterion 7: Body text justified (>=3/5) [10 points]
        # ----------------------------------------------------------------------
        body_samples = metadata.get("body_alignment_samples", [])
        justified_count = 0
        for sample in body_samples:
            matched, _ = check_paragraph_alignment_odt(content_tree, styles_tree, re.escape(sample), "justify")
            if matched > 0:
                justified_count += 1

        if body_samples and justified_count >= 3:
            score += 10
            feedback_parts.append(f"Body justified: {justified_count}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body justified: only {justified_count}/{len(body_samples)} (need 3)")

        # ----------------------------------------------------------------------
        # Criterion 8: Body font size >=11pt (>=3/5) [5 points]
        # ----------------------------------------------------------------------
        font_size_ok = 0
        for sample in body_samples:
            if check_text_font_size_odt(content_tree, styles_tree, re.escape(sample), 11.0):
                font_size_ok += 1

        if body_samples and font_size_ok >= 3:
            score += 5
            feedback_parts.append(f"Body font >=11pt: {font_size_ok}/{len(body_samples)} OK")
        else:
            feedback_parts.append(f"Body font >=11pt: only {font_size_ok}/{len(body_samples)} (need 3)")

        # ----------------------------------------------------------------------
        # Criterion 9: Content preservation (>=7/9 keywords) [10 points]
        # ----------------------------------------------------------------------
        content_keywords = metadata.get("content_keywords", [])
        full_text = get_document_text_odt(content_tree).lower()
        keyword_hits = sum(1 for kw in content_keywords if kw.lower() in full_text)

        # Basic word count anti-gaming check
        word_count = len(full_text.split())
        if word_count < 1500:
            score = 0
            feedback_parts.append(f"FAILED: Document heavily truncated ({word_count} words). Content deleted.")
        elif keyword_hits >= 7:
            score += 10
            feedback_parts.append(f"Content preserved: {keyword_hits}/{len(content_keywords)} keywords OK")
        else:
            feedback_parts.append(f"Content preserved: only {keyword_hits}/{len(content_keywords)} keywords (need 7)")

        # ----------------------------------------------------------------------
        # Criterion 10: VLM visual verification [5 points]
        # ----------------------------------------------------------------------
        query_vlm = env_info.get("query_vlm")
        vlm_passed = False
        
        if VLM_AVAILABLE and query_vlm:
            try:
                frames = sample_trajectory_frames(traj, n=3)
                final = get_final_screenshot(traj)
                images = frames + [final] if final else frames
                
                if images:
                    prompt = """You are evaluating a desktop agent that was instructed to format a residential property inspection report in a word processor.
                    
                    Review these trajectory frames from the agent's workflow.
                    Does the document look professionally formatted? Specifically, look for:
                    1. Distinct bold headings or title.
                    2. Data organized into proper grid tables (not just plain text separated by | characters).
                    3. Text paragraphs properly aligned.
                    
                    Respond in JSON format:
                    {
                        "looks_formatted": true/false,
                        "tables_visible": true/false,
                        "reasoning": "brief explanation"
                    }
                    """
                    
                    vlm_res = query_vlm(prompt=prompt, images=images)
                    if vlm_res.get("success"):
                        parsed = vlm_res.get("parsed", {})
                        if parsed.get("looks_formatted", False) and parsed.get("tables_visible", False):
                            score += 5
                            vlm_passed = True
                            feedback_parts.append("VLM visual verification passed")
                        else:
                            feedback_parts.append("VLM visual verification failed (lack of formatting/tables)")
                    else:
                        feedback_parts.append("VLM query failed during verification")
            except Exception as e:
                logger.warning(f"VLM verification error: {e}")
                feedback_parts.append("VLM visual verification skipped (error)")
        else:
            # Grant points if VLM is unavailable but primary checks pass
            if score >= 60:
                score += 5
                feedback_parts.append("VLM check skipped (awarded automatically based on structural score)")

        # Final Evaluation
        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        cleanup_verification_temp(temp_dir)