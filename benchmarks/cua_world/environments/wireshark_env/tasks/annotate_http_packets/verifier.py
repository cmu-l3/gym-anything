#!/usr/bin/env python3
"""
Verifier for annotate_http_packets task.

Checks:
1. Output file exists and is valid pcapng (pcap drops comments).
2. File contains 43 packets (no data loss).
3. Correct comment added to HTTP GET request.
4. Correct comment added to HTTP 200 OK response.
5. VLM verification of UI interaction.
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# VLM utilities from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_annotate_http_packets(traj, env_info, task_info):
    """
    Verify packet annotation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_count = metadata.get('expected_packet_count', 43)
    
    # Load result from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # CRITERION 1: File Existence & Format (20 pts)
    # ================================================================
    file_exists = result.get('file_exists', False)
    file_type = result.get('file_type', 'unknown')
    task_start = result.get('task_start', 0)
    file_timestamp = result.get('file_timestamp', 0)

    if not file_exists:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Output file http_annotated.pcapng not found"
        }

    # Anti-gaming: Check timestamp
    if file_timestamp < task_start:
        feedback_parts.append("File timestamp predates task start (using old file?)")
        # Proceed but with penalty
    else:
        score += 10
        feedback_parts.append("File created during task")

    # Check format (must be pcapng to support comments)
    if file_type == 'pcapng':
        score += 10
        feedback_parts.append("Correct file format (pcapng)")
    elif file_type == 'pcap':
        feedback_parts.append("Wrong file format: Saved as pcap (comments are lost in pcap format)")
    else:
        feedback_parts.append(f"Unknown file format: {file_type}")

    # ================================================================
    # CRITERION 2: Data Integrity (10 pts)
    # ================================================================
    packet_count = result.get('packet_count', 0)
    if packet_count == expected_count:
        score += 10
        feedback_parts.append(f"Packet count correct ({packet_count})")
    else:
        feedback_parts.append(f"Packet count mismatch ({packet_count} vs {expected_count})")

    # ================================================================
    # CRITERION 3: Comment Verification (50 pts)
    # ================================================================
    comments = result.get('extracted_comments', [])
    
    # Check for GET comment
    get_comment_found = False
    get_comment_correct = False
    
    for c in comments:
        # Check if this looks like the GET packet (method is GET or comment matches intent)
        is_get_packet = c.get('method') == 'GET'
        comment_text = c.get('comment', '').lower()
        
        if is_get_packet or "get request" in comment_text:
            get_comment_found = True
            if "initial http get request" in comment_text:
                get_comment_correct = True
                break
    
    if get_comment_correct:
        score += 25
        feedback_parts.append("HTTP GET packet correctly annotated")
    elif get_comment_found:
        score += 10
        feedback_parts.append("HTTP GET packet annotated but text mismatch")
    else:
        feedback_parts.append("HTTP GET packet annotation missing")

    # Check for 200 OK comment
    ok_comment_found = False
    ok_comment_correct = False
    
    for c in comments:
        is_ok_packet = c.get('status_code') == '200'
        comment_text = c.get('comment', '').lower()
        
        if is_ok_packet or "200 ok" in comment_text:
            ok_comment_found = True
            if "server responded with 200 ok" in comment_text:
                ok_comment_correct = True
                break
                
    if ok_comment_correct:
        score += 25
        feedback_parts.append("HTTP 200 OK packet correctly annotated")
    elif ok_comment_found:
        score += 10
        feedback_parts.append("HTTP 200 OK packet annotated but text mismatch")
    else:
        feedback_parts.append("HTTP 200 OK packet annotation missing")

    # ================================================================
    # CRITERION 4: VLM Process Verification (20 pts)
    # ================================================================
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        # Sample frames to find the "Packet Comment" dialog
        frames = sample_trajectory_frames(traj, n=8)
        final_img = get_final_screenshot(traj)
        
        prompt = """
        Review this sequence of screenshots from a Wireshark task.
        The user was asked to add comments to packets.
        
        Look for:
        1. The "Packet Comment" dialog box (usually has a text area and OK/Cancel buttons).
        2. The "Save Capture File As" dialog (saving the file).
        3. Any visible comments in the Packet List pane (sometimes shown in a column or info).
        
        JSON response:
        {
            "comment_dialog_seen": boolean,
            "save_as_dialog_seen": boolean,
            "wireshark_visible": boolean
        }
        """
        
        try:
            vlm_result = query_vlm(prompt=prompt, images=frames + [final_img])
            parsed = vlm_result.get('parsed', {})
            
            if parsed.get('wireshark_visible'):
                vlm_score += 5
            if parsed.get('comment_dialog_seen'):
                vlm_score += 10
                feedback_parts.append("VLM confirmed comment dialog usage")
            if parsed.get('save_as_dialog_seen'):
                vlm_score += 5
        except Exception as e:
            logger.warning(f"VLM check failed: {e}")
            # Fallback points if VLM fails but file is good
            if score >= 60: 
                vlm_score = 20
    
    score += vlm_score

    # Final pass determination
    passed = score >= 70 and get_comment_correct and ok_comment_correct
    
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }