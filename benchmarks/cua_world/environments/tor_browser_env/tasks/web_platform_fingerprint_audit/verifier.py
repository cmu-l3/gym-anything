#!/usr/bin/env python3
"""Verifier for web_platform_fingerprint_audit task.

Checks that the agent visited the diagnostic sites through Tor Browser
and compiled a structured text report containing their findings.
"""

import json
import logging
import os
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TASK_NAME = "web_platform_fingerprint_audit"

def extract_section(text: str, header: str, next_headers: list) -> str:
    """Extracts text for a specific section up to the next recognized header."""
    start_idx = text.find(header)
    if start_idx == -1:
        return ""
    start_idx += len(header)
    
    end_idx = len(text)
    for nh in next_headers:
        idx = text.find(nh, start_idx)
        if idx != -1 and idx < end_idx:
            end_idx = idx
            
    return text[start_idx:end_idx].strip()

def verify_web_platform_fingerprint_audit(traj, env_info, task_info):
    """
    Verification strategy:
    1. Read task_result.json for history and file metadata.
    2. Read tor-compatibility-report.txt content directly.
    3. Score the content structure and relevance.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    score = 0
    feedback_parts = []
    
    # 1. Read JSON result
    tmp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_json.close()
    try:
        copy_from_env(f"/tmp/{TASK_NAME}_result.json", tmp_json.name)
        with open(tmp_json.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Result JSON not found."}
    finally:
        if os.path.exists(tmp_json.name):
            os.unlink(tmp_json.name)

    # Criterion: File exists (Gate)
    if not result.get('file_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Target file /home/ga/Documents/tor-compatibility-report.txt does not exist."
        }
    
    score += 10
    feedback_parts.append("Report file exists (10/10)")

    # Criterion: File created after task start
    if result.get('file_mtime', 0) >= result.get('task_start_ts', float('inf')):
        score += 5
        feedback_parts.append("File created during task (5/5)")
    else:
        feedback_parts.append("File appears older than task start (0/5)")

    # Criterion: File size > 500 bytes
    if result.get('file_size', 0) > 500:
        score += 5
        feedback_parts.append("File size > 500 bytes (5/5)")
    else:
        feedback_parts.append("File size too small (0/5)")

    # 2. Read Report Content
    tmp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    tmp_txt.close()
    content = ""
    try:
        copy_from_env("/home/ga/Documents/tor-compatibility-report.txt", tmp_txt.name)
        with open(tmp_txt.name, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()
    except Exception as e:
        logger.warning(f"Failed to read report text: {e}")
    finally:
        if os.path.exists(tmp_txt.name):
            os.unlink(tmp_txt.name)

    # 3. Analyze Content Sections
    h1 = "--- 1. TOR CONNECTION STATUS ---"
    h2 = "--- 2. WEBRTC LEAK TEST ---"
    h3 = "--- 3. CANVAS FINGERPRINT TEST ---"
    h4 = "--- 4. EFF COVER YOUR TRACKS ---"
    h5 = "--- 5. SUMMARY ---"
    headers = [h1, h2, h3, h4, h5]
    
    sec1 = extract_section(content, h1, headers).lower()
    sec2 = extract_section(content, h2, headers).lower()
    sec3 = extract_section(content, h3, headers).lower()
    sec4 = extract_section(content, h4, headers).lower()
    sec5 = extract_section(content, h5, headers).lower()

    # Section 1 checks
    if h1 in content and "tor" in sec1 and any(kw in sec1 for kw in ["confirmed", "connected", "exit", "ip", "address"]):
        score += 10
        feedback_parts.append("Section 1 valid (10/10)")
    else:
        feedback_parts.append("Section 1 missing or lacks keywords (0/10)")

    # Section 2 checks
    if h2 in content and "webrtc" in sec2 and any(kw in sec2 for kw in ["leak", "disabled", "blocked", "no leak", "false", "none", "n/a"]):
        score += 10
        feedback_parts.append("Section 2 valid (10/10)")
    else:
        feedback_parts.append("Section 2 missing or lacks keywords (0/10)")

    # Section 3 checks
    if h3 in content and "canvas" in sec3 and any(kw in sec3 for kw in ["fingerprint", "protected", "unique", "randomized", "blocked", "100%", "random"]):
        score += 10
        feedback_parts.append("Section 3 valid (10/10)")
    else:
        feedback_parts.append("Section 3 missing or lacks keywords (0/10)")

    # Section 4 checks
    if h4 in content and any(kw in sec4 for kw in ["fingerprint", "tracking", "unique", "bits", "entropy", "protection", "strong", "randomized"]):
        score += 10
        feedback_parts.append("Section 4 valid (10/10)")
    else:
        feedback_parts.append("Section 4 missing or lacks keywords (0/10)")

    # Section 5 checks
    if h5 in content and len(sec5) >= 50:
        score += 10
        feedback_parts.append("Section 5 Summary valid (10/10)")
    else:
        feedback_parts.append("Section 5 Summary missing or too short (0/10)")

    # 4. Check Browser History (20 points total)
    if result.get('history_check_tor', False):
        score += 5
        feedback_parts.append("check.torproject.org visited (5/5)")
    else:
        feedback_parts.append("check.torproject.org NOT visited (0/5)")

    if result.get('history_webrtc', False):
        score += 5
        feedback_parts.append("browserleaks.com/webrtc visited (5/5)")
    else:
        feedback_parts.append("browserleaks.com/webrtc NOT visited (0/5)")

    if result.get('history_canvas', False):
        score += 5
        feedback_parts.append("browserleaks.com/canvas visited (5/5)")
    else:
        feedback_parts.append("browserleaks.com/canvas NOT visited (0/5)")

    if result.get('history_eff', False):
        score += 5
        feedback_parts.append("coveryourtracks.eff.org visited (5/5)")
    else:
        feedback_parts.append("coveryourtracks.eff.org NOT visited (0/5)")

    # 5. Distinct content check (Anti-copy-paste gaming)
    # Ensure sections aren't just the exact same text repeated
    sections = [s for s in [sec1, sec2, sec3, sec4] if len(s) > 10]
    if len(sections) == 4 and len(set(sections)) == 4:
        score += 5
        feedback_parts.append("Sections have distinct content (5/5)")
    else:
        feedback_parts.append("Sections lack distinct content (0/5)")

    # 6. WebRTC logic consistency check
    # Tor Browser disables WebRTC, so it shouldn't be leaking
    if len(sec2) > 0 and not ("leaking" in sec2 and "is" in sec2 and "not" not in sec2):
        score += 5
        feedback_parts.append("WebRTC logic consistent (5/5)")
    elif len(sec2) > 0:
        feedback_parts.append("WebRTC result indicates leak, which contradicts Tor behavior (0/5)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }