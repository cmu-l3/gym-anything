#!/usr/bin/env python3
"""
Verifier for rich_text_digest_authoring task.

Requirements:
1. Draft exists with correct recipient and subject.
2. Content is HTML.
3. Contains "Top Discussions" in Bold.
4. Contains "Compiled by AI Assistant" in Italics.
5. Contains a bulleted list (<ul>/<li>) with at least 3 items.
6. The list items match REAL subjects from the inbox (Anti-gaming).
"""

import json
import os
import tempfile
import logging
import re
from difflib import SequenceMatcher

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def similarity(a, b):
    return SequenceMatcher(None, a, b).ratio()

def verify_rich_text_digest_authoring(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_recipient = metadata.get('expected_recipient', 'digest-subscribers@community.org')
    expected_subject = metadata.get('expected_subject', 'Weekly Discussion Digest')
    header_text = metadata.get('header_text', 'Top Discussions')
    footer_text = metadata.get('footer_text', 'Compiled by AI Assistant')
    min_list_items = metadata.get('min_list_items', 3)

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Draft Existence and Headers (20 pts)
    if not result.get('draft_found'):
        return {"passed": False, "score": 0, "feedback": "No draft email found"}
    
    # Recipient
    if expected_recipient.lower() in result.get('recipient', '').lower():
        score += 10
        feedback_parts.append("Recipient correct")
    else:
        feedback_parts.append(f"Wrong recipient: {result.get('recipient')}")

    # Subject
    if expected_subject.lower() in result.get('subject', '').lower():
        score += 10
        feedback_parts.append("Subject correct")
    else:
        feedback_parts.append(f"Wrong subject: {result.get('subject')}")

    # Check 2: HTML Content & Formatting (40 pts)
    html_body = result.get('html_body', '')
    if not html_body:
        feedback_parts.append("Draft is plain text (HTML required)")
    else:
        score += 10 # Base points for having HTML
        
        # Bold Header
        # Regex handles <b>Text</b>, <strong>Text</strong>, <span style="font-weight: bold">Text</span>
        bold_pattern = re.compile(r'<(b|strong)\b[^>]*>.*?Top Discussions.*?</\1>|font-weight:\s*bold[^>]*>.*?Top Discussions', re.IGNORECASE | re.DOTALL)
        if bold_pattern.search(html_body):
            score += 10
            feedback_parts.append("Bold header found")
        elif header_text in html_body:
            score += 5 # Text present but not bold
            feedback_parts.append("Header text present (missing bold)")
        else:
            feedback_parts.append("Header text missing")

        # Italic Footer
        italic_pattern = re.compile(r'<(i|em)\b[^>]*>.*?Compiled by AI Assistant.*?</\1>|font-style:\s*italic[^>]*>.*?Compiled by AI Assistant', re.IGNORECASE | re.DOTALL)
        if italic_pattern.search(html_body):
            score += 10
            feedback_parts.append("Italic footer found")
        elif footer_text in html_body:
            score += 5 # Text present but not italic
            feedback_parts.append("Footer text present (missing italics)")
        else:
            feedback_parts.append("Footer text missing")

        # List Structure
        list_pattern = re.compile(r'<ul\b[^>]*>.*?</ul>', re.IGNORECASE | re.DOTALL)
        if list_pattern.search(html_body):
            score += 10
            feedback_parts.append("Bulleted list structure found")
        else:
            feedback_parts.append("Bulleted list missing")

    # Check 3: Real Data Usage (Anti-Gaming) (40 pts)
    # Extract list items
    list_items = re.findall(r'<li\b[^>]*>(.*?)</li>', html_body, re.IGNORECASE | re.DOTALL)
    
    # Clean up tags from items
    clean_items = []
    for item in list_items:
        clean_text = re.sub(r'<[^>]+>', '', item).strip()
        if clean_text:
            clean_items.append(clean_text)
            
    if len(clean_items) < min_list_items:
        feedback_parts.append(f"Found {len(clean_items)} list items (needed {min_list_items})")
    else:
        # Verify against inbox subjects
        inbox_subjects = result.get('inbox_subjects', [])
        valid_matches = 0
        
        for item in clean_items:
            # Check if this item fuzzily matches any real subject
            is_match = False
            for real_subj in inbox_subjects:
                # Remove common prefixes for comparison (Re:, Fwd:, [List])
                clean_real = re.sub(r'^(Re:|Fwd:|\[.*?\])\s*', '', real_subj, flags=re.IGNORECASE).strip()
                clean_item_comp = re.sub(r'^(Re:|Fwd:|\[.*?\])\s*', '', item, flags=re.IGNORECASE).strip()
                
                # Check containment or high similarity
                if clean_item_comp.lower() in clean_real.lower() or \
                   clean_real.lower() in clean_item_comp.lower() or \
                   similarity(clean_item_comp.lower(), clean_real.lower()) > 0.8:
                    is_match = True
                    break
            
            if is_match:
                valid_matches += 1
        
        if valid_matches >= 3:
            score += 40
            feedback_parts.append(f"Verfied {valid_matches} items match real inbox emails")
        elif valid_matches >= 1:
            score += 20
            feedback_parts.append(f"Only {valid_matches} items match real emails (others may be hallucinated)")
        else:
            feedback_parts.append("List items do not appear to come from the inbox")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }