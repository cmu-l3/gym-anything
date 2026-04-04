#!/usr/bin/env python3
"""
Verifier for safety_meeting_minutes_styles task.
Checks:
1. Heading styles applied correctly.
2. Custom 'Action Item' style created with Border, Shading, and Indents.
3. Custom style applied to 'ACTION:' paragraphs.
4. Table of Contents exists.
"""

import json
import os
import sys
import logging
import tempfile
import shutil

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from writer_verification_utils import (
    copy_and_parse_document,
    check_heading_styles,
    detect_toc_present,
    vlm_verify_screenshot
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_safety_minutes(traj, env_info, task_info):
    """Verify the formatting of safety meeting minutes."""
    
    # 1. Setup and Load
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_headings = metadata.get('heading_structure', {})
    required_style_name = metadata.get('required_style_name', "Action Item")
    
    # Load output document
    output_path = metadata.get('output_file', "/home/ga/Documents/site_42_formatted.docx")
    success, doc, error, temp_dir = copy_and_parse_document(output_path, copy_from_env, file_format='docx')
    
    if not success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to open output file: {error}. Did you save as .docx?"
        }

    score = 0
    feedback = []
    
    try:
        # 2. Verify Heading Styles (20 pts)
        # We need to map the text segments to their expected styles
        # The check_heading_styles util does partial matching
        h_matched, h_total, h_feedback = check_heading_styles(doc, expected_headings)
        
        # We expect at least 5 out of 6 headings to be correct for full points
        if h_matched >= 5:
            score += 20
            feedback.append(f"Headings correct ({h_matched}/{h_total})")
        elif h_matched >= 3:
            score += 10
            feedback.append(f"Some headings correct ({h_matched}/{h_total})")
        else:
            feedback.append(f"Headings mostly wrong ({h_matched}/{h_total})")
            
        # 3. Verify Table of Contents (10 pts)
        if detect_toc_present(doc):
            score += 10
            feedback.append("Table of Contents found")
        else:
            feedback.append("Table of Contents missing")

        # 4. Verify Custom Style Existence and Properties (40 pts)
        # Find the style in doc.styles
        found_style = None
        style_name_lower = required_style_name.lower()
        
        # Search by name (case-insensitive)
        for s in doc.styles:
            if s.name and style_name_lower in s.name.lower():
                found_style = s
                break
        
        style_ok = False
        if found_style:
            feedback.append(f"Custom style '{found_style.name}' found")
            style_score = 10
            
            # Check Indentation (10 pts)
            # 0.5 inches = 457200 EMU
            # Allow tolerance of +/- 0.1 inch (91440 EMU)
            target_ind = 457200
            tolerance = 91440
            
            pf = found_style.paragraph_format
            left = pf.left_indent
            right = pf.right_indent
            
            # Convert to int if exists, else 0
            left_val = left.emu if left else 0
            right_val = right.emu if right else 0
            
            if (abs(left_val - target_ind) < tolerance) and (abs(right_val - target_ind) < tolerance):
                style_score += 10
                feedback.append("Style indentation correct (0.5\")")
            else:
                feedback.append(f"Style indentation incorrect (Left: {left_val}, Right: {right_val})")
            
            # Check Borders/Shading via XML (20 pts)
            # python-docx doesn't expose borders/shading nicely, must check XML
            xml = found_style.element.xml
            has_border = 'w:pBdr' in xml or 'w:bottom' in xml # simplistic check for any border def
            has_shading = 'w:shd' in xml and 'w:fill' in xml
            
            if has_border:
                style_score += 10
                feedback.append("Style borders detected")
            else:
                feedback.append("Style borders missing")
                
            if has_shading:
                style_score += 10
                feedback.append("Style shading/background detected")
            else:
                feedback.append("Style shading missing")
                
            score += style_score
            style_ok = True
        else:
            feedback.append(f"Custom style '{required_style_name}' NOT found in document styles")

        # 5. Verify Style Usage (30 pts)
        # Check that paragraphs starting with "ACTION:" use the custom style
        action_paras = []
        for para in doc.paragraphs:
            if para.text.strip().startswith("ACTION:"):
                action_paras.append(para)
        
        if not action_paras:
            feedback.append("CRITICAL: 'ACTION:' paragraphs not found in text!")
        else:
            applied_count = 0
            for p in action_paras:
                # Check if style name matches our found custom style
                if p.style and found_style and p.style.name == found_style.name:
                    applied_count += 1
                elif p.style and style_name_lower in p.style.name.lower():
                    # Fallback loose match
                    applied_count += 1
            
            if applied_count == len(action_paras):
                score += 30
                feedback.append(f"Style applied to all {len(action_paras)} Action Items")
            elif applied_count > 0:
                score += 15
                feedback.append(f"Style applied to {applied_count}/{len(action_paras)} Action Items")
            else:
                feedback.append("Custom style NOT applied to Action Items")

        # 6. VLM Validation (Tie-breaker / Safety)
        # If score is borderline or high, use VLM to confirm visual appearance of yellow boxes
        if score > 60:
            vlm_res = vlm_verify_screenshot(env_info, traj, 
                "Does the document show paragraphs enclosed in yellow boxes or having a yellow background? "
                "Are there Action Items clearly highlighted?")
            if vlm_res.get('safe_to_trust', False) and vlm_res.get('bool_result', False):
                feedback.append("Visual verification confirmed yellow highlighting.")
            elif vlm_res.get('safe_to_trust', False) and not vlm_res.get('bool_result', False):
                feedback.append("Visual verification FAILED to see yellow highlighting.")
                score = max(score - 20, 0) # Penalize if invisible

    except Exception as e:
        logger.error(f"Verification error: {e}")
        score = 0
        feedback.append(f"Verification failed with error: {str(e)}")
    finally:
        cleanup_verification_temp(temp_dir)

    passed = (score >= 70)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }