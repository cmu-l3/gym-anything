#!/usr/bin/env python3
"""Verifier for emergency_action_plan_format task."""

import sys
import os
import json
import logging

# Ensure we can import wps_verification_utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from wps_verification_utils import (
        copy_and_parse_document,
        cleanup_verification_temp,
        get_document_text,
        count_tables,
        get_table_content,
        count_headings_by_level,
        check_text_formatting
    )
except ImportError:
    logging.warning("wps_verification_utils not found. Formatting checks may be limited.")

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_emergency_action_plan_format(traj, env_info, task_info):
    """
    Verify that the raw EAP document was correctly formatted.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load export results to check basic file status
    temp_result = "/tmp/emergency_action_plan_result_host.json"
    try:
        copy_from_env("/tmp/emergency_action_plan_result.json", temp_result)
        with open(temp_result, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result):
            os.unlink(temp_result)

    doc_exists = result_data.get("document_exists", False)
    doc_mtime = result_data.get("document_mtime", 0)
    task_start = result_data.get("task_start", 0)

    # Check anti-gaming (file must be saved during task)
    if doc_mtime < task_start:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output document was not saved/modified during the task execution."
        }

    container_path = "/tmp/emergency_action_plan_formatted.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {
            "passed": False,
            "score": 4, # Small point for at least triggering an export/save
            "feedback": f"Could not parse the formatted document: {error}"
        }

    try:
        feedback_parts = []
        score = 0
        
        full_text = get_document_text(doc).lower()
        
        # Criterion 10: Content preservation (8 points)
        expected_words = ["purpose", "meridian", "evacuate", "lockdown", "john smith", "alice brown", "extinguishers"]
        preserved = sum(1 for w in expected_words if w.lower() in full_text)
        if preserved >= 6:
            score += 8
            feedback_parts.append(f"Content preserved ({preserved}/{len(expected_words)})")
        else:
            feedback_parts.append(f"Content degraded ({preserved}/{len(expected_words)} key phrases found)")

        # File saved successfully (4 points) - If we're here, it parsed.
        score += 4

        # Criterion 1: Title formatting (6 points)
        has_title = False
        for para in doc.paragraphs[:5]:
            text_l = para.text.lower()
            if "emergency action plan" in text_l and "meridian" in text_l:
                if para.style and ("title" in para.style.name.lower() or "heading" in para.style.name.lower()):
                    has_title = True
                # Check inline styling
                elif any(r.font and r.font.size and r.font.size.pt >= 16 for r in para.runs):
                    has_title = True
        
        if has_title:
            score += 6
            feedback_parts.append("Title formatted properly")
        else:
            feedback_parts.append("Title lacks prominent formatting")

        # Criterion 2: Heading 1 sections (14 points)
        # Criterion 3: Heading 2 subsections (10 points)
        heading_counts = count_headings_by_level(doc)
        h1_count = heading_counts.get('Heading 1', 0)
        h2_count = heading_counts.get('Heading 2', 0)

        if h1_count >= 6:
            score += 14
            feedback_parts.append(f"Heading 1s applied ({h1_count})")
        elif h1_count >= 3:
            score += 7
            feedback_parts.append(f"Heading 1s partially applied ({h1_count})")
        else:
            feedback_parts.append(f"Insufficient Heading 1s ({h1_count})")

        if h2_count >= 4:
            score += 10
            feedback_parts.append(f"Heading 2s applied ({h2_count})")
        elif h2_count >= 2:
            score += 5
            feedback_parts.append(f"Heading 2s partially applied ({h2_count})")
        else:
            feedback_parts.append(f"Insufficient Heading 2s ({h2_count})")

        # Table extractions
        num_tables = count_tables(doc)
        feedback_parts.append(f"Tables found: {num_tables}")

        contact_table_score = 0
        warden_table_score = 0
        assembly_table_score = 0
        equipment_table_score = 0

        for t_idx in range(num_tables):
            content = get_table_content(doc, t_idx)
            text_content = str(content).lower()
            row_count = len(content)

            # Contact table (12 points)
            if "john smith" in text_content and "jane doe" in text_content:
                if row_count >= 6:
                    contact_table_score = 12
                elif row_count >= 3:
                    contact_table_score = 6

            # Floor Warden table (10 points)
            if "alice brown" in text_content and "floor 1" in text_content:
                if row_count >= 4:
                    warden_table_score = 10
                elif row_count >= 2:
                    warden_table_score = 5

            # Assembly Points table (10 points)
            if "north exit" in text_content and "south lawn" in text_content:
                if row_count >= 3:
                    assembly_table_score = 10
                elif row_count >= 2:
                    assembly_table_score = 5

            # Equipment table (8 points)
            if "fire extinguishers" in text_content and "hallways" in text_content:
                if row_count >= 4:
                    equipment_table_score = 8
                elif row_count >= 2:
                    equipment_table_score = 4

        score += contact_table_score + warden_table_score + assembly_table_score + equipment_table_score
        
        if contact_table_score > 0: feedback_parts.append("Contact table created")
        if warden_table_score > 0: feedback_parts.append("Warden table created")
        if assembly_table_score > 0: feedback_parts.append("Assembly table created")
        if equipment_table_score > 0: feedback_parts.append("Equipment table created")

        # Bold safety keywords (10 points)
        safety_keywords = ["evacuate", "shelter in place", "lockdown", "call 911", "do not"]
        bolded_keywords = 0
        for kw in safety_keywords:
            if check_text_formatting(doc, kw, bold=True):
                bolded_keywords += 1
        
        if bolded_keywords >= 4:
            score += 10
            feedback_parts.append(f"Safety keywords bolded ({bolded_keywords}/5)")
        elif bolded_keywords >= 2:
            score += 5
            feedback_parts.append(f"Some safety keywords bolded ({bolded_keywords}/5)")
        else:
            feedback_parts.append(f"Insufficient keywords bolded ({bolded_keywords}/5)")

        # Body font consistency (5 points)
        # Check standard paragraphs (non-headings/titles)
        font_sizes = []
        for para in doc.paragraphs:
            if para.style and "heading" not in para.style.name.lower() and "title" not in para.style.name.lower():
                if para.text.strip():
                    sizes = [r.font.size.pt for r in para.runs if r.font and r.font.size]
                    if sizes:
                        font_sizes.extend(sizes)
        
        consistent_fonts = 0
        if font_sizes:
            # Check if majority of text is 11pt or 12pt
            valid_sizes = sum(1 for s in font_sizes if 10.5 <= s <= 12.5)
            ratio = valid_sizes / len(font_sizes)
            if ratio >= 0.6:
                score += 5
                feedback_parts.append("Body font size is consistent (11-12pt)")
            else:
                feedback_parts.append("Body font size inconsistent or incorrect")
        else:
            # If default font size isn't explicitly set in runs, assume default is ok
            score += 5
            feedback_parts.append("Default font size maintained")

        # VLM Visual Verification (3 points)
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_img = get_final_screenshot(traj)
            
            vlm_prompt = """
            You are evaluating a document formatting task in WPS Writer.
            Look at the final screenshot. Does the document look professionally formatted with visible headings and/or tables?
            Respond in JSON format:
            {
                "looks_professional": true/false,
                "headings_visible": true/false,
                "tables_visible": true/false
            }
            """
            
            vlm_result = query_vlm(prompt=vlm_prompt, image=final_img)
            if vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                if parsed.get("looks_professional") or parsed.get("tables_visible"):
                    score += 3
                    feedback_parts.append("VLM visual check passed")
                else:
                    feedback_parts.append("VLM did not detect professional formatting")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

        # Final evaluation
        # Pass threshold: 60 points + at least 2 tables created + at least 3 Heading 1s
        tables_created = sum(1 for s in [contact_table_score, warden_table_score, assembly_table_score, equipment_table_score] if s > 0)
        
        passed = (score >= 60) and (tables_created >= 2) and (h1_count >= 3)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {str(e)}"
        }
    finally:
        cleanup_verification_temp(temp_dir)