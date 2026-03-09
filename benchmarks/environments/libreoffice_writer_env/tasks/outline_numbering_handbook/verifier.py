#!/usr/bin/env python3
"""
Verifier for outline_numbering_handbook task.
"""

import json
import os
import re
import logging
import tempfile
import sys

# Import shared utilities if available, otherwise define minimal placeholders
try:
    from utils.writer_verification_utils import (
        copy_and_parse_document,
        check_heading_styles,
        vlm_verify_screenshot
    )
except ImportError:
    # Fallback if running outside full environment (e.g. testing)
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_outline_numbering(traj, env_info, task_info):
    """
    Verify that the handbook has correctly applied heading styles and outline numbering.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_headings = metadata.get('heading_structure', {})
    output_path = metadata.get('output_path', "/home/ga/Documents/handbook_numbered.docx")
    txt_export_path = metadata.get('txt_export_path', "/home/ga/Documents/handbook_numbered.txt")

    score = 0
    max_score = 100
    feedback_parts = []
    
    # =========================================================
    # 1. Check Result JSON & File Existence
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file handbook_numbered.docx not found."
        }
    
    score += 5
    feedback_parts.append("File created")

    # =========================================================
    # 2. Check DOCX for Heading Styles (using python-docx)
    # =========================================================
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, 'docx')
    if not success:
        return {"passed": False, "score": 5, "feedback": f"Corrupt DOCX: {error}"}

    # Verify Heading 1
    h1_map = {text: "Heading 1" for text in expected_headings.get("Heading 1", [])}
    h1_match, h1_total, _ = check_heading_styles(doc, h1_map)
    
    # Verify Heading 2
    h2_map = {text: "Heading 2" for text in expected_headings.get("Heading 2", [])}
    h2_match, h2_total, _ = check_heading_styles(doc, h2_map)

    # Verify Heading 3
    h3_map = {text: "Heading 3" for text in expected_headings.get("Heading 3", [])}
    h3_match, h3_total, _ = check_heading_styles(doc, h3_map)

    # Scoring for Styles
    # Allow some margin of error (e.g. typos or missed one)
    if h1_match >= len(h1_map) - 1: score += 15
    else: feedback_parts.append(f"Heading 1: {h1_match}/{len(h1_map)} matched")

    if h2_match >= len(h2_map) - 2: score += 15
    else: feedback_parts.append(f"Heading 2: {h2_match}/{len(h2_map)} matched")

    if h3_match >= len(h3_map) - 2: score += 15
    else: feedback_parts.append(f"Heading 3: {h3_match}/{len(h3_map)} matched")
    
    # =========================================================
    # 3. Check for Outline Numbering
    # =========================================================
    # Strategy A: Check DOCX XML for numPr in heading styles/paragraphs
    # This detects if numbering is *structurally* applied
    has_xml_numbering = False
    try:
        ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
        # Check specific paragraphs that should be headings
        numbered_paras = 0
        target_texts = (
            expected_headings["Heading 1"] + 
            expected_headings["Heading 2"] + 
            expected_headings["Heading 3"]
        )
        
        for para in doc.paragraphs:
            if any(t in para.text for t in target_texts):
                # Check for <w:numPr> or style implying numbering
                if para._element.findall('.//w:numPr', ns):
                    numbered_paras += 1
        
        # If > 50% of headings have explicit numbering XML, that's good evidence
        if numbered_paras >= len(target_texts) * 0.5:
            has_xml_numbering = True
            
    except Exception as e:
        logger.warning(f"XML check failed: {e}")

    # Strategy B: Check exported Text file for visual numbering (e.g. "1. General...")
    # This confirms it actually RENDERS as numbered
    has_text_numbering = False
    if result.get('txt_export_exists'):
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(txt_export_path, temp_txt.name)
            with open(temp_txt.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                
            # Regex to find "1. General", "1.1. Equal", "1.1.1. Reasonable"
            # Matches start of line, number sequence, space, then known title
            # Example: ^1\. General Employment
            
            found_numbers = 0
            
            # Check Level 1 (e.g., "1. General...")
            if re.search(r'^\s*\d+\.\s+General Employment', content, re.MULTILINE): found_numbers += 1
            
            # Check Level 2 (e.g., "1.1. Equal...") - allow 1.1 or 1.1.
            if re.search(r'^\s*\d+\.\d+\.?\s+Equal Opportunity', content, re.MULTILINE): found_numbers += 1
            
            # Check Level 3 (e.g., "1.1.1. Reasonable...")
            if re.search(r'^\s*\d+\.\d+\.\d+\.?\s+Reasonable', content, re.MULTILINE): found_numbers += 1
            
            if found_numbers >= 2:
                has_text_numbering = True
                
        except Exception as e:
            logger.warning(f"Text check failed: {e}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)

    if has_text_numbering or has_xml_numbering:
        score += 25
        feedback_parts.append("Outline numbering verified")
    else:
        feedback_parts.append("Outline numbering NOT detected in output")

    # =========================================================
    # 4. Content Preservation
    # =========================================================
    # Check that body text isn't deleted
    full_text = " ".join([p.text for p in doc.paragraphs])
    key_phrase = "committed to providing a work environment that is free from discrimination"
    if key_phrase in full_text:
        score += 10
        feedback_parts.append("Content preserved")
    else:
        feedback_parts.append("Body content appears damaged/missing")

    # =========================================================
    # 5. VLM Verification (Visual Check)
    # =========================================================
    vlm_result = vlm_verify_screenshot(env_info, traj, """
    Analyze this LibreOffice Writer screenshot.
    Look for document headings.
    1. Are headings clearly numbered (e.g., "1. Title", "1.1 Subtitle")?
    2. Do the numbers look hierarchical (1, 1.1, 1.1.1)?
    
    Answer in JSON:
    {
        "visible_numbering": true/false,
        "hierarchical": true/false,
        "heading_styles_visible": true/false
    }
    """)
    
    vlm_score = 0
    if vlm_result.get('parsed', {}).get('visible_numbering'): vlm_score += 10
    if vlm_result.get('parsed', {}).get('hierarchical'): vlm_score += 5
    score += vlm_score
    if vlm_score > 0: feedback_parts.append("VLM confirmed visual numbering")

    # =========================================================
    # Final Verdict
    # =========================================================
    # Pass if Score >= 60 AND Heading 1s match AND Numbering detected
    # (Must have at least tried the main task)
    passed = (score >= 60) and (h1_match >= 3) and (has_text_numbering or has_xml_numbering)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }