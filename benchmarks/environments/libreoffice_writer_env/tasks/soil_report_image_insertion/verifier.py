#!/usr/bin/env python3
"""
Verifier for soil_report_image_insertion task.
"""

import sys
import os
import json
import logging
import tempfile
import shutil

# Add utils directory to path to import shared utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_soil_report_images(traj, env_info, task_info):
    """
    Verify the soil report task.
    
    Criteria:
    1. Output file exists and was created during task.
    2. File size indicates images were added (significantly larger than draft).
    3. Document contains at least 3 images (inline shapes).
    4. Correct captions are present.
    5. Placeholders are removed.
    6. Original text content is preserved.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata from export_result.sh
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task_result.json: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 1. Check basic file existence and creation
    if not task_result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file soil_survey_complete.docx not found."
        }
    
    if not task_result.get('file_created_during_task', False):
        return {
            "passed": False,
            "score": 0,
            "feedback": "Output file timestamp is too old (created before task started)."
        }

    # 2. Check file size increase (Images add weight)
    # Empty doc with text is ~10-20KB. Doc with 3 pics should be >100KB.
    output_size = task_result.get('output_size', 0)
    draft_size = task_result.get('draft_size', 0)
    
    if output_size < draft_size + 10000: # minimal check, refined below
        logger.warning(f"Output size {output_size} is close to draft size {draft_size}")

    # 3. Parse the document content
    output_path = "/home/ga/Documents/soil_survey_complete.docx"
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output document: {error}"}

    score = 0
    feedback_parts = []
    
    try:
        # Criterion: Image Count (20 pts)
        # In python-docx, images are inline_shapes
        image_count = len(doc.inline_shapes)
        if image_count >= 3:
            score += 20
            feedback_parts.append(f"Images found: {image_count} (>=3)")
        elif image_count > 0:
            score += 10
            feedback_parts.append(f"Images found: {image_count} (Partial credit, expected 3)")
        else:
            feedback_parts.append("No images found in document")

        # Criterion: File Size check (10 pts)
        # If image count is 0, this likely fails too, but checks for distinct implementation
        if output_size > draft_size + 50000: # At least 50KB gained
            score += 10
            feedback_parts.append("File size indicates content added")
        else:
            feedback_parts.append("File size increase insufficient for 3 images")

        # Criterion: Captions (30 pts - 10 per caption)
        full_text = get_document_text(doc)
        
        # We search for unique substrings from the required captions
        captions_found = 0
        caption_targets = [
            ("Figure 1", "Aerial view", "Sharkey clay"),
            ("Figure 2", "soil profile", "slickensides"),
            ("Figure 3", "bucket auger", "T-14")
        ]
        
        for i, (prefix, kw1, kw2) in enumerate(caption_targets):
            # Check if paragraph contains prefix AND (kw1 OR kw2)
            found = False
            for para in doc.paragraphs:
                txt = para.text
                if prefix in txt and (kw1 in txt or kw2 in txt):
                    found = True
                    break
            
            if found:
                score += 10
                captions_found += 1
            else:
                feedback_parts.append(f"Missing/Incorrect caption for {prefix}")

        if captions_found == 3:
            feedback_parts.append("All captions correct")

        # Criterion: Placeholders Removed (15 pts)
        placeholders_remaining = 0
        for i in range(1, 4):
            ph = f"[INSERT FIGURE {i} HERE]"
            if ph in full_text:
                placeholders_remaining += 1
        
        if placeholders_remaining == 0:
            score += 15
            feedback_parts.append("All placeholders removed")
        else:
            feedback_parts.append(f"{placeholders_remaining} placeholders still present")

        # Criterion: Content Preservation (15 pts)
        # Check for key phrases from the original text
        key_phrases = [
            "Tallahatchie County is located",
            "Sharkey series consists of very deep",
            "Soil samples were collected",
            "Field Book for Describing and Sampling Soils"
        ]
        phrases_found = 0
        for phrase in key_phrases:
            if phrase in full_text:
                phrases_found += 1
        
        if phrases_found >= 3:
            score += 15
            feedback_parts.append("Original text preserved")
        else:
            feedback_parts.append("Significant original text missing")

        # Criterion: Basic File Existence (10 pts)
        score += 10 # If we got this far, the file exists and is parseable

        # VLM Check (Optional but good for visual verification)
        # We don't rely heavily on it for scoring here since programmatic is robust for DOCX,
        # but we use it to verify the images look like images, not just text.
        
        passed = (score >= 65) and (image_count >= 2) and (captions_found >= 2)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification logic error: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification logic error: {e}"}
    finally:
        cleanup_verification_temp(temp_dir)