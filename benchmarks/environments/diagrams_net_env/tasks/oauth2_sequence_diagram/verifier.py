#!/usr/bin/env python3
"""
Verifier for OAuth 2.0 Sequence Diagram Task.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_oauth2_sequence_diagram(traj, env_info, task_info):
    """
    Verifies the OAuth 2.0 sequence diagram task based on:
    1. File structure (parsed XML metrics)
    2. Content requirements (specific lifelines, phases, frames)
    3. Multi-page support
    4. Export generation
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve results
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/final_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load verification data: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = data.get('analysis', {})
    export_exists = data.get('export_exists', False)
    
    score = 0
    feedback_parts = []
    
    # 1. Anti-Gaming / File Activity (5 pts)
    if analysis.get('file_modified', False):
        score += 5
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified")

    # 2. Page 1 Structure: Lifelines (25 pts)
    # Start was 3. Expected >= 5 (Added Resource Server & Token Store)
    p1_lifelines = analysis.get('p1_lifelines', 0)
    if p1_lifelines >= 5:
        score += 15
        feedback_parts.append(f"Lifelines count OK ({p1_lifelines})")
    else:
        feedback_parts.append(f"Missing lifelines ({p1_lifelines}/5)")
        
    if analysis.get('resource_server_found'):
        score += 5
    else:
        feedback_parts.append("Missing 'Resource Server' lifeline")
        
    if analysis.get('token_store_found'):
        score += 5
    else:
        feedback_parts.append("Missing 'Token Store' lifeline")

    # 3. Page 1 Structure: Messages (15 pts)
    # Start was 6. Expected >= 14 (Added ~4 for token exchange, ~4 for resource access)
    p1_messages = analysis.get('p1_messages', 0)
    if p1_messages >= 14:
        score += 15
        feedback_parts.append(f"Message flow detailed ({p1_messages} messages)")
    elif p1_messages >= 10:
        score += 8
        feedback_parts.append(f"Message flow partial ({p1_messages} messages)")
    else:
        feedback_parts.append(f"Insufficient messages ({p1_messages}/14)")

    # 4. Page 1 Structure: Combined Fragment (10 pts)
    if analysis.get('p1_has_alt'):
        score += 10
        feedback_parts.append("Combined Fragment 'alt' found")
    else:
        feedback_parts.append("Missing 'alt' fragment for validation logic")

    # 5. Page 2: Token Refresh Flow (25 pts)
    page_names = [n.lower() for n in analysis.get('page_names', [])]
    p2_exists = len(page_names) >= 2
    
    if p2_exists:
        score += 10
        feedback_parts.append("Second page exists")
        
        # Check naming
        if any('refresh' in n or 'token' in n for n in page_names[1:]):
            score += 5
            feedback_parts.append("Second page named correctly")
            
        # Check content
        p2_messages = analysis.get('p2_messages', 0)
        if p2_messages >= 4:
            score += 10
            feedback_parts.append("Refresh flow modeled")
        else:
            feedback_parts.append("Refresh flow page empty/incomplete")
    else:
        feedback_parts.append("Missing second page for Refresh Flow")

    # 6. Terminology (10 pts)
    terms_found = len(analysis.get('terms_found', []))
    if terms_found >= 4:
        score += 10
        feedback_parts.append("Correct OAuth terminology used")
    elif terms_found >= 2:
        score += 5
        feedback_parts.append("Partial terminology usage")
    else:
        feedback_parts.append("Missing specific OAuth terms")

    # 7. Export (10 pts)
    if export_exists and data.get('export_size', 0) > 1000:
        score += 10
        feedback_parts.append("SVG Export successful")
    else:
        feedback_parts.append("SVG Export missing or empty")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }