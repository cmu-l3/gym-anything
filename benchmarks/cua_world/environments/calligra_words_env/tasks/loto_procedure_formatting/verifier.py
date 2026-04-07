#!/usr/bin/env python3
"""Verifier for the loto_procedure_formatting task."""

import json
import logging
import os
import re
import sys
import xml.etree.ElementTree as ET

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    check_paragraph_alignment_odt,
    copy_and_parse_document,
    get_odt_tables,
    ODF_NS
)
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_loto_procedure_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/LOTO_Cincinnati_Press.odt")

    # Verify document modifications
    try:
        temp_json = "/tmp/task_result.json"
        local_json = "/tmp/local_result.json"
        copy_from_env(temp_json, local_json)
        with open(local_json, 'r') as f:
            export_data = json.load(f)
        file_modified = export_data.get("file_modified", False)
    except Exception as e:
        logger.warning(f"Could not read task_result.json: {e}")
        file_modified = True  # Fallback to true if missing to avoid failing immediately

    if not file_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Document was not modified or saved. Agent must save changes to complete the task."
        }

    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    try:
        score = 0
        feedback_parts = []

        # ── 1. Heading Formatting (20 points) ──
        expected_headings = metadata.get("expected_headings", [
            "Purpose", "Machine Specifications", "Energy Source Inventory",
            "Shutdown Sequence", "Restoration to Normal Operations"
        ])
        
        h1_matched, h1_total, _ = check_heading_styles_odt(
            content_tree, styles_tree, expected_headings, 1
        )
        
        # Check if the numbers were stripped
        h1_elements = content_tree.findall('.//text:h', ODF_NS)
        numbers_removed = True
        h1_texts = []
        for h in h1_elements:
            if h.get(f"{{{ODF_NS['text']}}}outline-level") == "1":
                text = "".join(h.itertext()).strip()
                h1_texts.append(text)
                if re.match(r'^\d+\.\d+\s', text):
                    numbers_removed = False

        if h1_matched >= 4:
            if numbers_removed and len(h1_texts) > 0:
                score += 20
                feedback_parts.append(f"Section Headings: {h1_matched}/{h1_total} H1 with numbers removed (20/20)")
            else:
                score += 15
                feedback_parts.append(f"Section Headings: {h1_matched}/{h1_total} H1, but numbers not fully removed (15/20)")
        else:
            score += h1_matched * 3
            feedback_parts.append(f"Section Headings: Only {h1_matched}/{h1_total} H1 applied ({h1_matched * 3}/20)")

        # ── 2. Title Block Alignment (10 points) ──
        title_lines = metadata.get("expected_title_lines", [])
        centered_count = 0
        for line in title_lines:
            matched, _ = check_paragraph_alignment_odt(
                content_tree, styles_tree, re.escape(line), "center"
            )
            if matched > 0:
                centered_count += 1
                
        if centered_count == len(title_lines):
            score += 10
            feedback_parts.append("Title Block: Centered correctly (10/10)")
        elif centered_count > 0:
            score += 5
            feedback_parts.append(f"Title Block: Partially centered {centered_count}/{len(title_lines)} (5/10)")
        else:
            feedback_parts.append("Title Block: Not centered (0/10)")

        # ── 3. Energy Source Table (25 points) ──
        tables = get_odt_tables(content_tree)
        table_created = False
        for tbl in tables:
            rows = tbl.get("rows", [])
            # Must have at least 5 rows (1 header + 4 data) and roughly 5 columns
            if len(rows) >= 5 and max([len(r) for r in rows]) >= 4:
                # Ensure it contains our data
                flat_data = " ".join([" ".join(r).lower() for r in rows])
                if "electrical" in flat_data and "hydraulic" in flat_data:
                    table_created = True
                    break

        if table_created:
            score += 25
            feedback_parts.append("Energy Source Table: Created correctly (25/25)")
        else:
            feedback_parts.append("Energy Source Table: Not created or malformed (0/25)")

        # ── 4. Numbered Lists (30 points) ──
        # Find all actual XML list items <text:list-item>
        list_items = content_tree.findall('.//text:list-item', ODF_NS)
        num_list_items = len(list_items)
        
        # Expecting ~14 list items. If they got at least 12, full points.
        if num_list_items >= 12:
            score += 30
            feedback_parts.append(f"Numbered Lists: {num_list_items} items formatted correctly (30/30)")
        elif num_list_items >= 6:
            score += 15
            feedback_parts.append(f"Numbered Lists: Partially formatted ({num_list_items} items) (15/30)")
        else:
            feedback_parts.append(f"Numbered Lists: Not formatted as XML lists (found {num_list_items}) (0/30)")

        # ── 5. Typography (5 points) ──
        content_str = ET.tostring(content_tree, encoding='utf8').lower()
        styles_str = ET.tostring(styles_tree, encoding='utf8').lower() if styles_tree else b""
        
        if b"liberation sans" in content_str or b"liberation sans" in styles_str:
            score += 5
            feedback_parts.append("Typography: Liberation Sans detected (5/5)")
        else:
            feedback_parts.append("Typography: Font not changed to Liberation Sans (0/5)")

        # ── 6. VLM Verification (10 points) ──
        query_vlm = env_info.get("query_vlm")
        vlm_passed = False
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            if frames and final:
                images = frames + [final]
                vlm_prompt = """You are evaluating screenshots of an agent formatting a safety document in Calligra Words.
                
                Evaluate the final state and progression:
                1. TABLE: Is there a table visible with columns like "Energy Type", "Magnitude", "Location"?
                2. LISTS: Are the "Shutdown Sequence" and "Restoration" steps formatted as indented numbered lists?
                
                Answer in JSON format:
                {
                  "table_visible": true/false,
                  "lists_visible": true/false,
                  "confidence": "high/medium/low"
                }
                """
                try:
                    vlm_res = query_vlm(prompt=vlm_prompt, images=images)
                    if vlm_res.get("success"):
                        parsed = vlm_res.get("parsed", {})
                        if parsed.get("table_visible") or parsed.get("lists_visible"):
                            score += 10
                            vlm_passed = True
                            feedback_parts.append("VLM Verification: Visual confirmation of structure (10/10)")
                        else:
                            feedback_parts.append("VLM Verification: Could not visually confirm structure (0/10)")
                except Exception as e:
                    logger.warning(f"VLM verification failed: {e}")
                    # Give benefit of doubt if VLM fails but programmatic check passes heavily
                    if table_created and num_list_items >= 6:
                        score += 10
                        feedback_parts.append("VLM Verification: Skipped due to error, full points awarded based on XML data (10/10)")

        # Evaluate pass condition
        passed = score >= 75 and table_created and num_list_items >= 6
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback_parts)
        }
        
    except Exception as e:
        logger.error(f"Error during verification: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification encountered an error: {e}"
        }