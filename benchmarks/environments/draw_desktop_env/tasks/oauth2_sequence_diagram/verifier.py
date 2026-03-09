#!/usr/bin/env python3
"""
Verifier for oauth2_sequence_diagram task.

Scoring (100 points):
- File saved & modified: 5 pts
- Participants (4 required): 20 pts
- Message flow (8+ messages): 15 pts
- Keywords (PKCE params, tokens): 20 pts
- Self-message included: 5 pts
- Note/Annotation included: 5 pts
- Multi-page structure (2 pages): 15 pts
- Page 2 logic (Refresh flow): 5 pts
- PNG Export valid: 10 pts

Pass Threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_oauth2_sequence_diagram(traj, env_info, task_info):
    """Verify the OAuth 2.0 PKCE Sequence Diagram task."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    analysis = result.get('analysis', {})
    score = 0
    feedback = []

    # 1. File Existence (5 pts)
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 5
        feedback.append("File saved successfully")
    elif result.get('file_exists'):
        score += 2
        feedback.append("File exists but timestamp is old")
    else:
        feedback.append("FAIL: .drawio file not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. Participants (20 pts)
    # Expect: User, Client, Auth Server, Resource Server
    participants = analysis.get('participants_found', [])
    req_participants = ["user", "client", "authorization server", "resource server"]
    
    # Fuzzy matching for "authorization server" (accept "auth server" etc)
    found_count = 0
    missing = []
    
    for req in req_participants:
        if any(req in p or p in req for p in participants):
            found_count += 1
        else:
            missing.append(req)

    if found_count >= 4:
        score += 20
        feedback.append("All 4 participants found")
    elif found_count >= 2:
        score += 10
        feedback.append(f"Partial participants ({found_count}/4). Missing: {missing}")
    else:
        feedback.append(f"Missing most participants. Found: {participants}")

    # 3. Message Flow (15 pts)
    msg_count = analysis.get('messages_count', 0)
    if msg_count >= 8:
        score += 15
        feedback.append(f"Good message flow ({msg_count} messages)")
    elif msg_count >= 5:
        score += 8
        feedback.append(f"Sparse message flow ({msg_count} messages)")
    else:
        feedback.append(f"Too few messages ({msg_count})")

    # 4. Keywords (20 pts)
    # PKCE specific terms
    keywords = analysis.get('keywords_found', [])
    unique_kws = set(keywords)
    kw_count = len(unique_kws)
    
    if kw_count >= 5:
        score += 20
        feedback.append(f"Excellent protocol details ({kw_count} keywords found)")
    elif kw_count >= 3:
        score += 10
        feedback.append(f"Some protocol details ({kw_count} keywords)")
    else:
        feedback.append(f"Missing technical details (code_verifier, challenge, etc.). Found: {keywords}")

    # 5. Self-Message (5 pts)
    if analysis.get('self_messages_count', 0) > 0:
        score += 5
        feedback.append("Self-message included")
    else:
        feedback.append("Missing self-message (e.g. for generating/verifying code)")

    # 6. Note/Annotation (5 pts)
    if analysis.get('has_note'):
        score += 5
        feedback.append("Note/Annotation present")
    else:
        feedback.append("Missing explanatory note")

    # 7. Pages (15 pts)
    pages = analysis.get('num_pages', 0)
    if pages >= 2:
        score += 15
        feedback.append("Multi-page diagram created")
    else:
        feedback.append("Only 1 page found (requested 2)")

    # 8. Page 2 Content (5 pts)
    page_names = analysis.get('page_names', [])
    refresh_page = any('refresh' in name for name in page_names)
    if pages >= 2 and refresh_page:
        score += 5
        feedback.append("Token Refresh page identified")
    elif pages >= 2:
        # If 2 pages exist but 'refresh' not in title, give partial
        score += 2
        feedback.append("Second page title doesn't mention 'refresh'")

    # 9. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_valid'):
        png_size = result.get('png_size', 0)
        if png_size > 2000:
            score += 10
            feedback.append("PNG export valid")
        else:
            score += 5
            feedback.append("PNG export too small/empty")
    else:
        feedback.append("PNG export missing")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }