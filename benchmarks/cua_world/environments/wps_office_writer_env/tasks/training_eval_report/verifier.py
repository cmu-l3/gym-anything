#!/usr/bin/env python3
"""Verifier for training_eval_report task."""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from wps_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_headings_by_level,
    count_tables,
    get_table_content,
    check_table_header_formatting,
)

# Optional: Import VLM utilities if framework provides them
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_training_eval_report(traj, env_info, task_info):
    """
    Verify the formatting and structure of the Training Evaluation Report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve expected metadata
    metadata = task_info.get('metadata', {})
    expected_tables = metadata.get('expected_tables', 6)
    expected_h1_min = metadata.get('expected_h1_min', 8)
    expected_h2_min = metadata.get('expected_h2_min', 4)
    key_values = metadata.get('key_values', ["247", "1,200,000", "540", "4.3", "Meridian"])

    # First, read the JSON result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result_data = {}
    try:
        copy_from_env("/tmp/training_eval_report_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    document_exists = result_data.get('document_exists', False)
    if not document_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output document not found. The agent did not save the file to the correct location."
        }

    # Fetch and parse the document
    container_path = "/tmp/training_eval_report.docx"
    success, doc, error, temp_dir = copy_and_parse_document(
        container_path, copy_from_env, file_format='docx'
    )

    if not success:
        return {
            "passed": False,
            "score": 5,
            "feedback": f"Document found but failed to parse: {error}"
        }

    score = 5 # Base score for saving the file
    max_score = 100
    feedback_parts = []

    try:
        full_text = get_document_text(doc).lower()
        
        # 1. Content completeness (5 points)
        preserved_values = sum(1 for val in key_values if val.lower() in full_text)
        if preserved_values >= len(key_values) - 1:
            score += 5
            feedback_parts.append("Content preserved")
        else:
            feedback_parts.append(f"Missing key content ({preserved_values}/{len(key_values)} found)")

        # 2. Title page formatting (10 points)
        # Check first 15 paragraphs for title, date, org, and large font
        title_found = False
        large_font_found = False
        for para in doc.paragraphs[:15]:
            text_l = para.text.lower()
            if "cybersecurity awareness" in text_l and "evaluation report" in text_l:
                title_found = True
                # Check for large font or Heading usage
                if para.style and 'Heading' in para.style.name:
                    large_font_found = True
                for run in para.runs:
                    if run.font and run.font.size and run.font.size.pt >= 18:
                        large_font_found = True
                    if run.bold:
                        pass # Bold is good, but we specifically want large font
            
        if title_found and large_font_found:
            score += 10
            feedback_parts.append("Title page formatted with large text")
        elif title_found:
            score += 5
            feedback_parts.append("Title text found but not properly formatted")
        else:
            feedback_parts.append("Title page text missing or misplaced")

        # 3. Heading 1 styles (15 points)
        heading_counts = count_headings_by_level(doc)
        h1_count = heading_counts.get('Heading 1', 0)
        
        if h1_count >= expected_h1_min:
            score += 15
            feedback_parts.append(f"Heading 1s applied ({h1_count})")
        elif h1_count > 0:
            score += 7
            feedback_parts.append(f"Partial Heading 1s ({h1_count}/{expected_h1_min})")
        else:
            feedback_parts.append("No Heading 1s found")

        # 4. Heading 2 styles (10 points)
        h2_count = heading_counts.get('Heading 2', 0)
        if h2_count >= expected_h2_min:
            score += 10
            feedback_parts.append(f"Heading 2s applied ({h2_count})")
        elif h2_count > 0:
            score += 5
            feedback_parts.append(f"Partial Heading 2s ({h2_count}/{expected_h2_min})")
        else:
            feedback_parts.append("No Heading 2s found")

        # 5. Tables creation (30 points total: 5 pts per table up to 6 tables)
        num_tables = count_tables(doc)
        tables_score = min(num_tables * 5, 30)
        score += tables_score
        feedback_parts.append(f"Created {num_tables}/{expected_tables} tables")

        # 6. Table Headers Formatted (5 points)
        # Check if at least 3 tables have bold headers
        bold_headers_count = 0
        for i in range(num_tables):
            if check_table_header_formatting(doc, i, require_bold=True):
                bold_headers_count += 1
                
        if bold_headers_count >= 3:
            score += 5
            feedback_parts.append("Table headers bolded")
        elif bold_headers_count > 0:
            score += 2
            feedback_parts.append("Some table headers bolded")

        # 7. Bulleted/Numbered List in Exec Summary (5 points)
        # Look for list-style paragraphs or text starting with bullet points in the first half of doc
        list_found = False
        exec_summary_area = False
        for para in doc.paragraphs[:50]:
            text_l = para.text.strip().lower()
            if "executive summary" in text_l:
                exec_summary_area = True
                continue
            if "program overview" in text_l:
                exec_summary_area = False
                
            if exec_summary_area and len(text_l) > 10:
                if (para.style and 'List' in para.style.name) or text_l.startswith(('•', '-', '1.', '(1)')):
                    list_found = True
                    break
                    
        if list_found:
            score += 5
            feedback_parts.append("Findings formatted as list")
        else:
            feedback_parts.append("Findings not formatted as a list")

        # 8. VLM Verification (15 points)
        if VLM_AVAILABLE:
            try:
                final_img = get_final_screenshot(traj)
                prompt = """Analyze this screenshot of WPS Writer displaying a Training Evaluation Report.
1. Does the document look professionally formatted with clear headings?
2. Can you see any formatted tables with borders?
3. Is it clearly organized (not just a wall of plain text)?
Return JSON: {"looks_professional": true/false, "tables_visible": true/false}
"""
                vlm_res = query_vlm(images=[final_img], prompt=prompt)
                parsed = vlm_res.get('parsed', {})
                if parsed.get('looks_professional', False) and parsed.get('tables_visible', False):
                    score += 15
                    feedback_parts.append("VLM visual verification passed")
                elif parsed.get('looks_professional', False) or parsed.get('tables_visible', False):
                    score += 7
                    feedback_parts.append("VLM visual verification partially passed")
                else:
                    feedback_parts.append("VLM visual verification failed (looks unformatted)")
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")
                # Award points automatically if programmatic score is very high and VLM failed
                if score >= 70:
                    score += 15
                    feedback_parts.append("VLM skipped but program score high")
        else:
            # Grant points if VLM is unavailable but other high indicators are met
            if score >= 70:
                score += 15
                feedback_parts.append("VLM unavailable, auto-awarded based on structure")

    except Exception as e:
        logger.error(f"Error during verification: {e}")
        feedback_parts.append(f"Error during parsing: {str(e)}")

    finally:
        if 'temp_dir' in locals() and temp_dir:
            import shutil
            shutil.rmtree(temp_dir, ignore_errors=True)

    passed = score >= 60 and num_tables >= 5

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }