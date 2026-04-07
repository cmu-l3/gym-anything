#!/usr/bin/env python3
"""Verifier for the training_workbook_participant_prep task."""

import json
import logging
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calligra_verification_utils import (
    check_heading_styles_odt,
    copy_and_parse_document,
    get_document_text_odt,
    get_odt_tables
)

# Import VLM trajectory utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_training_workbook(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    document_path = metadata.get("document_path", "/home/ga/Documents/leadership_training_master.odt")

    # 1. Check if file was modified during task (anti-gaming)
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
            "feedback": "Document was not modified/saved during the task. (Did you forget to save?)"
        }

    # 2. Parse the modified ODT
    temp_dir, doc_obj, doc_type = copy_and_parse_document(copy_from_env, document_path)
    if temp_dir is None or doc_type != "odt":
        return {"passed": False, "score": 0, "feedback": "Failed to copy or parse ODT document"}

    content_tree, styles_tree = doc_obj

    score = 0
    feedback_parts = []
    
    full_text = get_document_text_odt(content_tree)
    full_text_lower = full_text.lower()

    # ---------------------------------------------------------
    # Criterion 1: Facilitator Notes Removed (20 points)
    # ---------------------------------------------------------
    facilitator_markers = [m.lower() for m in metadata.get("facilitator_markers", [])]
    notes_absent = all(marker not in full_text_lower for marker in facilitator_markers)
    if notes_absent:
        score += 20
        feedback_parts.append("Facilitator notes successfully removed")
    else:
        feedback_parts.append("Failed: Some facilitator notes remain in the document")

    # ---------------------------------------------------------
    # Criterion 2: H1 Sections Applied (15 points)
    # ---------------------------------------------------------
    expected_h1 = metadata.get("expected_h1_sections", [])
    h1_matched, h1_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h1, 1)
    if h1_matched >= len(expected_h1) - 1:  # Allow 1 missing for partial/full credit
        score += 15
        feedback_parts.append(f"H1 applied correctly ({h1_matched}/{h1_total})")
    elif h1_matched >= 2:
        score += 7
        feedback_parts.append(f"H1 partially applied ({h1_matched}/{h1_total})")
    else:
        feedback_parts.append(f"H1 mostly missing ({h1_matched}/{h1_total})")

    # ---------------------------------------------------------
    # Criterion 3: H2 Subsections Applied (15 points)
    # ---------------------------------------------------------
    expected_h2 = metadata.get("expected_h2_subsections", [])
    h2_matched, h2_total, _ = check_heading_styles_odt(content_tree, styles_tree, expected_h2, 2)
    if h2_matched >= len(expected_h2) - 1:
        score += 15
        feedback_parts.append(f"H2 applied correctly ({h2_matched}/{h2_total})")
    elif h2_matched >= 2:
        score += 7
        feedback_parts.append(f"H2 partially applied ({h2_matched}/{h2_total})")
    else:
        feedback_parts.append(f"H2 mostly missing ({h2_matched}/{h2_total})")

    # ---------------------------------------------------------
    # Criterion 4: Tables Created (20 points)
    # ---------------------------------------------------------
    tables = get_odt_tables(content_tree)
    action_plan_tables_found = 0
    for tbl in tables:
        # Flatten all text in the table to check if it's an action plan table
        table_text = " ".join([" ".join(cell) for row in tbl.get("rows", []) for cell in row]).lower()
        if "goal" in table_text and "action step" in table_text:
            action_plan_tables_found += 1
            
    if action_plan_tables_found >= 3:
        score += 20
        feedback_parts.append(f"Action Plan tables created ({action_plan_tables_found}/4)")
    elif action_plan_tables_found > 0:
        score += 10
        feedback_parts.append(f"Some tables created ({action_plan_tables_found}/4)")
    else:
        feedback_parts.append("No Action Plan tables were created")

    # ---------------------------------------------------------
    # Criterion 5: Content Preservation (15 points)
    # ---------------------------------------------------------
    legitimate_phrases = metadata.get("legitimate_phrases_must_be_present", [])
    phrases_present = sum(1 for phrase in legitimate_phrases if phrase.lower() in full_text_lower)
    if phrases_present >= len(legitimate_phrases) - 1:
        score += 15
        feedback_parts.append(f"Content preserved ({phrases_present}/{len(legitimate_phrases)})")
    else:
        feedback_parts.append(f"Content heavily truncated or missing ({phrases_present}/{len(legitimate_phrases)})")

    # ---------------------------------------------------------
    # Criterion 6: VLM Verification for Page Breaks & Layout (15 points)
    # ---------------------------------------------------------
    vlm_score = 0
    if query_vlm and 'gym_anything.vlm' in sys.modules:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            prompt = """You are evaluating a word processing task in Calligra Words.
The user was asked to insert 'Page Breaks' before main Modules and format tables.

Analyze these trajectory frames and the final screenshot. 
1. PAGE_BREAKS: Can you see evidence of document pagination, empty space at the bottom of pages, or modules starting distinctly at the top of a new page?
2. WORKFLOW: Did the user interact with the Insert > Page Break menu, or table insertion tools?

Respond with a JSON object containing:
{
  "page_breaks_visible": true/false,
  "tables_visible": true/false,
  "confidence": "high/medium/low",
  "reasoning": "Brief explanation"
}"""
            
            images_to_send = frames + [final_frame] if final_frame else frames
            if images_to_send:
                vlm_resp = query_vlm(prompt=prompt, images=images_to_send)
                if vlm_resp and vlm_resp.get("success"):
                    parsed = vlm_resp.get("parsed", {})
                    if parsed.get("page_breaks_visible", False):
                        vlm_score += 15
                        feedback_parts.append("VLM: Page breaks visually confirmed")
                    else:
                        feedback_parts.append("VLM: Page breaks not clearly visible")
                else:
                    feedback_parts.append("VLM query failed or unparseable")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped (error)")
    else:
        # Fallback if VLM isn't available: give partial credit to not fail purely on VLM absence
        vlm_score += 10
        feedback_parts.append("VLM verification skipped (module not loaded)")

    score += vlm_score

    # ---------------------------------------------------------
    # Final Scoring
    # ---------------------------------------------------------
    key_criteria_met = (notes_absent) and (h1_matched >= 2) and (action_plan_tables_found >= 2)
    passed = (score >= 70) and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }