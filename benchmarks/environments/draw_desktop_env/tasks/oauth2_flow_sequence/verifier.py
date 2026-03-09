#!/usr/bin/env python3
"""
Verifier for oauth2_flow_sequence task.

Scoring (100 points total):
- File saved after task start: 10 pts
- 20+ shapes drawn: 15 pts                               (partial: 10+ = 6 pts)
- 15+ edges/messages drawn: 15 pts                       (partial: 8+ = 6 pts)
- 5+ distinct OAuth participants identified: 20 pts      (partial: 3+ = 8 pts)
- OAuth-specific keywords present (PKCE, tokens): 15 pts (partial: 4+ = 6 pts)
- Combined fragments (alt/opt/loop) present: 10 pts
- 2+ pages (sequence + threat model): 10 pts
- PNG exported: 5 pts

Pass threshold: 60 points
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

REQUIRED_PARTICIPANTS = [
    "user", "browser", "authorization_server", "token", "resource", "jwks", "session"
]


def verify_oauth2_flow_sequence(traj, env_info, task_info):
    """Verify OAuth 2.0 sequence diagram creation."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    metadata = task_info.get('metadata', {})
    min_shapes = metadata.get('min_shapes', 20)
    min_edges = metadata.get('min_edges', 15)

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    subscores = {}

    # --- Criterion 1: File saved (10 pts) ---
    if not result.get('file_exists'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "oauth2_sequence.drawio not found. No diagram was saved.",
            "subscores": {}
        }

    if result.get('file_modified_after_start'):
        score += 10
        subscores["file_saved"] = True
        feedback.append("Diagram file saved")
    else:
        subscores["file_saved"] = False
        feedback.append("WARN: File exists but not modified after task start")

    if result.get('file_size', 0) < 800:
        return {
            "passed": False,
            "score": score,
            "feedback": f"File too small ({result.get('file_size', 0)} bytes)",
            "subscores": subscores
        }

    # --- Criterion 2: Shape count (15 pts full, 6 partial) ---
    num_shapes = result.get('num_shapes', 0)
    subscores["num_shapes"] = num_shapes
    if num_shapes >= min_shapes:
        score += 15
        feedback.append(f"Shapes: {num_shapes} (comprehensive sequence diagram)")
    elif num_shapes >= 10:
        score += 6
        feedback.append(f"Shapes: {num_shapes} (partial, need ≥{min_shapes})")
    elif num_shapes >= 5:
        score += 2
        feedback.append(f"Shapes: {num_shapes} (too few elements)")
    else:
        feedback.append(f"Shapes: only {num_shapes}")

    # --- Criterion 3: Message/edge count (15 pts full, 6 partial) ---
    num_edges = result.get('num_edges', 0)
    subscores["num_edges"] = num_edges
    if num_edges >= min_edges:
        score += 15
        feedback.append(f"Messages: {num_edges} (≥{min_edges} required)")
    elif num_edges >= 8:
        score += 6
        feedback.append(f"Messages: {num_edges} (partial, need ≥{min_edges})")
    elif num_edges >= 3:
        score += 2
        feedback.append(f"Messages: only {num_edges}")
    else:
        feedback.append(f"Messages: only {num_edges}")

    # --- Criterion 4: Participants identified (20 pts full, 8 partial) ---
    participants = result.get('participants_found', 0)
    subscores["participants"] = participants
    if participants >= 5:
        score += 20
        feedback.append(f"Participants: {participants}/7 identified (strong coverage)")
    elif participants >= 3:
        score += 8
        feedback.append(f"Participants: {participants}/7 (partial — add more lifelines)")
    elif participants >= 1:
        score += 3
        feedback.append(f"Participants: {participants}/7 (too few)")
    else:
        feedback.append("Participants: none identified — add 7 named lifelines")

    # --- Criterion 5: OAuth keywords (15 pts full, 6 partial) ---
    oauth_count = result.get('oauth_keywords_count', 0)
    subscores["oauth_keywords"] = oauth_count
    if oauth_count >= 7:
        score += 15
        feedback.append(f"OAuth keywords: {oauth_count} (excellent PKCE/token coverage)")
    elif oauth_count >= 4:
        score += 6
        feedback.append(f"OAuth keywords: {oauth_count} (partial — label messages with OAuth terms)")
    elif oauth_count >= 1:
        score += 2
        feedback.append(f"OAuth keywords: {oauth_count} (too few)")
    else:
        feedback.append("OAuth keywords: none found — label messages with RFC terms (access_token, code_verifier, etc.)")

    # --- Criterion 6: Combined fragments (10 pts) ---
    if result.get('has_fragments'):
        score += 10
        subscores["fragments"] = True
        feedback.append("Combined fragments: alt/opt/loop present")
    else:
        subscores["fragments"] = False
        feedback.append("Combined fragments: missing (add alt for auth failure, opt for token refresh)")

    # --- Criterion 7: Multiple pages (10 pts) ---
    num_pages = result.get('num_pages', 0)
    has_threat = result.get('has_threat_page', False)
    subscores["multi_page"] = num_pages
    if num_pages >= 2:
        threat_note = " (includes Threat Model page)" if has_threat else " (no Threat Model page detected)"
        score += 10
        feedback.append(f"Pages: {num_pages}{threat_note}")
    else:
        feedback.append(f"Pages: {num_pages} (need ≥2: Sequence diagram + Threat Model)")

    # --- Criterion 8: PNG exported (5 pts) ---
    png_valid = result.get('png_valid', False)
    png_size = result.get('png_size', 0)
    subscores["png_exported"] = result.get('png_exists', False)
    if png_valid and png_size >= 2000:
        score += 5
        feedback.append(f"PNG exported: {png_size} bytes")
    elif result.get('png_exists'):
        score += 2
        feedback.append(f"PNG present but small: {png_size} bytes")
    else:
        feedback.append("PNG not exported (need ~/Desktop/oauth2_sequence.png)")

    passed = score >= 60
    feedback.append(f"{'PASSED' if passed else 'FAILED'} (score={score}/100)")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback),
        "subscores": subscores
    }
