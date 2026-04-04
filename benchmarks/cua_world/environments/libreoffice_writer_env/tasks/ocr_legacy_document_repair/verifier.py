#!/usr/bin/env python3
"""
Verifier for OCR Legacy Document Repair task.
Checks if the "messy" document was successfully cleaned, rejoined, and styled.
"""

import sys
import os
import logging
import json
import tempfile

# Add utils directory to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    cleanup_verification_temp,
    get_document_text,
    check_heading_styles,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_ocr_repair(traj, env_info, task_info):
    """
    Verify OCR repair task.
    Criteria:
    1. Output file exists and was modified during task.
    2. Paragraph count is within reasonable range (indicates lines were joined).
    3. Specific broken words (hyphenated in source) are now whole.
    4. Headings have correct styles applied.
    5. VLM visual check for document structure.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_path', '/home/ga/Documents/udhr_restored.docx')
    target_min_paras = metadata.get('target_paragraph_count_min', 10)
    target_max_paras = metadata.get('target_paragraph_count_max', 25)
    broken_words = metadata.get('broken_words_to_fix', [])
    expected_headings = metadata.get('headings', {})

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Load result JSON from export script
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception:
        pass  # Fail gracefully if json missing
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Check file existence (10 pts)
    if not task_result.get('output_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file '/home/ga/Documents/udhr_restored.docx' not found."
        }
    
    score += 10
    feedback_parts.append("File created")

    # Check timestamp (anti-gaming) (5 pts)
    if task_result.get('file_created_during_task', False):
        score += 5
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during task")

    # 2. Parse Document
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    if not success:
        return {"passed": False, "score": score, "feedback": f"Failed to parse document: {error}"}

    try:
        # 3. Check Paragraph Count (Line Joining) (30 pts)
        # Original has ~100+ paragraphs (lines). Restored should have ~17.
        # We allow a range because empty spacers might be kept or removed.
        para_count = len(doc.paragraphs)
        if target_min_paras <= para_count <= target_max_paras:
            score += 30
            feedback_parts.append(f"Line breaks fixed (paragraph count: {para_count})")
        else:
            feedback_parts.append(f"Paragraph count issue: {para_count} (expected {target_min_paras}-{target_max_paras}). Did you join the broken lines?")

        # 4. Check Hyphenation Repair (20 pts)
        full_text = get_document_text(doc).lower()
        fixed_count = 0
        for word in broken_words:
            if word.lower() in full_text:
                fixed_count += 1
            # Also check if the BROKEN version still exists (e.g. "interna- tional")
            # This is harder to check perfectly due to spacing, but checking existence of whole word is good.
        
        # We expect most to be fixed.
        if len(broken_words) > 0:
            fix_ratio = fixed_count / len(broken_words)
            if fix_ratio >= 0.8:
                score += 20
                feedback_parts.append(f"Hyphenation repaired ({fixed_count}/{len(broken_words)} words verified)")
            elif fix_ratio >= 0.5:
                score += 10
                feedback_parts.append(f"Partial hyphenation repair ({fixed_count}/{len(broken_words)})")
            else:
                feedback_parts.append("Hyphenated words not rejoined")

        # 5. Check Heading Styles (20 pts)
        # expected_headings = {"Text": "StyleName"}
        matched, total, h_feedback = check_heading_styles(doc, expected_headings)
        if total > 0:
            style_score = int(20 * (matched / total))
            score += style_score
            feedback_parts.append(f"Styles applied: {matched}/{total}")
            if matched < total:
                feedback_parts.append(f"Missing styles: {', '.join(h_feedback[:2])}...")

        # 6. Check for Double Spaces (Artifacts) (5 pts)
        # Joining lines often leaves double spaces if not careful
        double_spaces = full_text.count("  ")
        if double_spaces < 5: # Allow a few, strict zero is hard
            score += 5
            feedback_parts.append("No significant double spacing artifacts")
        else:
            feedback_parts.append(f"Found {double_spaces} double spaces (cleanup incomplete)")

        # 7. VLM Visual Verification (10 pts)
        # Check if it looks like a normal doc
        vlm_res = vlm_verify_screenshot(env_info, traj, """
        Analyze this document screenshot. 
        1. Does the text extend across the full width of the page (normal paragraphs)?
        2. Or is it a narrow column of text on the left (like a raw scan)?
        3. Do you see Heading styles (larger/bold text) for 'Preamble' or 'Article'?
        Answer JSON: {"is_full_width": bool, "has_headings": bool}
        """)
        
        if vlm_res['success']:
            parsed = vlm_res.get('parsed', {})
            if parsed.get('is_full_width', False):
                score += 5
            if parsed.get('has_headings', False):
                score += 5
        
        # Final calculation
        passed = (score >= 70) and (target_min_paras <= para_count <= target_max_paras)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        cleanup_verification_temp(temp_dir)