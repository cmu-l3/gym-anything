#!/usr/bin/env python3
"""
Verifier for PII Masking Regex task.
Verifies ODT content for masked SSNs, sanitized emails, and highlighting.
"""

import json
import os
import re
import shutil
import tempfile
import logging
from zipfile import ZipFile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_odt_content(odt_path):
    """
    Extracts text and styles from an ODT file.
    Returns: (text_content, highlighted_spans_count)
    """
    try:
        with ZipFile(odt_path, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
                
                # Namespaces
                ns = {
                    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
                    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0'
                }
                
                # 1. Extract all text
                text_content = ""
                for elem in root.findall('.//text:p', ns):
                    if elem.text:
                        text_content += elem.text
                    for child in elem:
                        if child.text:
                            text_content += child.text
                        if child.tail:
                            text_content += child.tail
                    text_content += "\n"
                
                # 2. Identify highlight styles
                # Find automatic styles with background color
                highlight_style_names = set()
                auto_styles = root.find('.//office:automatic-styles', ns)
                if auto_styles is not None:
                    for style in auto_styles.findall('style:style', ns):
                        props = style.find('style:text-properties', ns)
                        if props is not None:
                            bg = props.get(f"{{{ns['fo']}}}background-color")
                            if bg and bg != "transparent":
                                highlight_style_names.add(style.get(f"{{{ns['style']}}}name"))
                
                # 3. Count spans using highlight styles
                highlighted_count = 0
                for span in root.findall('.//text:span', ns):
                    style_name = span.get(f"{{{ns['text']}}}style-name")
                    if style_name in highlight_style_names:
                        # Check if span contains relevant text (rough heuristic)
                        span_text = "".join(span.itertext())
                        if "XXX-XX" in span_text or "@redacted" in span_text:
                            highlighted_count += 1
                            
                return text_content, highlighted_count
    except Exception as e:
        logger.error(f"Error parsing ODT: {e}")
        return "", 0

def verify_pii_masking(traj, env_info, task_info):
    """
    Verifies PII masking task.
    Criteria:
    1. Output file exists and modified.
    2. No full SSNs leaked.
    3. SSNs masked correctly (XXX-XX-####) and last 4 digits match ground truth.
    4. Emails sanitized (@redacted.com) and usernames match ground truth.
    5. Highlighting applied.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    score = 0
    feedback = []
    
    # 1. Get task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    if not task_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found."}
        
    score += 10 # File created
    
    # 2. Get Ground Truth
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/roster_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            ground_truth = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read ground truth: {e}"}
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # 3. Get Output Document
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    try:
        copy_from_env("/home/ga/Documents/roster_sanitized.odt", temp_odt.name)
        text_content, highlight_count = parse_odt_content(temp_odt.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output ODT: {e}"}
    finally:
        if os.path.exists(temp_odt.name):
            os.unlink(temp_odt.name)
            
    # CRITERION: Zero Leaks (20 pts)
    # Check for any pattern of ###-##-####
    leaks = re.findall(r'\b\d{3}-\d{2}-\d{4}\b', text_content)
    if len(leaks) == 0:
        score += 20
        feedback.append("No SSN leaks found")
    else:
        feedback.append(f"FAILED: Found {len(leaks)} unmasked SSNs")
        
    # CRITERION: SSN Masking & Preservation (35 pts)
    # Check format XXX-XX-####
    masked_ssns = re.findall(r'XXX-XX-(\d{4})', text_content)
    
    if len(masked_ssns) == 0:
        feedback.append("No masked SSNs found")
    else:
        # Check count
        if len(masked_ssns) >= len(ground_truth):
            score += 20
            feedback.append("SSN masking pattern correct")
        else:
            score += 10
            feedback.append(f"Partial SSN masking ({len(masked_ssns)}/{len(ground_truth)})")
            
        # Check preservation (Match last 4 digits against ground truth)
        # We need to match records. Since order might be preserved or text extraction is linear,
        # we'll collect all last-4s from ground truth and check intersection.
        # Ideally, we should check row-by-row, but text extraction loses table structure.
        # Checking set membership is a reasonable proxy for "regex capture group used correctly".
        
        gt_last4s = [r['last_4'] for r in ground_truth]
        # Count how many of the found masked suffixes exist in the ground truth
        valid_preservation = 0
        for suffix in masked_ssns:
            if suffix in gt_last4s:
                valid_preservation += 1
                
        if valid_preservation >= len(ground_truth) * 0.9:
            score += 15
            feedback.append("SSN digits preserved correctly")
        elif valid_preservation > 0:
            score += 5
            feedback.append("Some SSN digits mismatch ground truth")
        else:
            feedback.append("SSN digits do not match ground truth (did you hardcode 0000?)")

    # CRITERION: Email Sanitization (25 pts)
    email_matches = re.findall(r'([a-zA-Z0-9\._]+)@redacted\.com', text_content)
    
    if len(email_matches) >= len(ground_truth):
        score += 15
        feedback.append("Email domain sanitized")
        
        # Check username preservation
        gt_usernames = [r['username'] for r in ground_truth]
        valid_users = 0
        for user in email_matches:
            if user in gt_usernames:
                valid_users += 1
        
        if valid_users >= len(ground_truth) * 0.9:
            score += 10
            feedback.append("Email usernames preserved")
    else:
        feedback.append(f"Email sanitization incomplete ({len(email_matches)}/{len(ground_truth)})")
        
    # CRITERION: Highlighting (10 pts)
    # Based on our XML parse
    if highlight_count >= 10: # Threshold: at least some highlights found
        score += 10
        feedback.append(f"Highlighting detected ({highlight_count} spans)")
    else:
        # Fallback: Check VLM if programmatic check failed (sometimes styles are complex)
        from gym_anything.vlm import get_final_screenshot, query_vlm
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_res = query_vlm(
                prompt="Does this document show yellow highlighting on the text in the table columns for SSN and Email?",
                image=final_screenshot
            )
            if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False):
                score += 10
                feedback.append("Highlighting verified visually")
            else:
                feedback.append("Highlighting not detected")
        else:
            feedback.append("Highlighting not detected")

    passed = (score >= 75) and (len(leaks) == 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }