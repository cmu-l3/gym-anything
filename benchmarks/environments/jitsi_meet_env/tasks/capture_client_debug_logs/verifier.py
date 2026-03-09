#!/usr/bin/env python3
"""
Verifier for capture_client_debug_logs task.

Criteria:
1. Log file creation and redirection (Programmatic)
2. Log content validity (Programmatic keyword search)
3. Application termination (Programmatic)
4. Workflow interaction (VLM Trajectory)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Common keywords found in Firefox stdout/stderr when running WebRTC/Jitsi
# Note: "Jitsi" might not appear in stdout if console logging isn't verbose,
# but "Gecko", "GL", "webrtc", "ICE", "SDP" are common in browser logs.
EXPECTED_KEYWORDS = [
    "Firefox", "Gecko", "Child", "Web Content",  # Process indicators
    "GLContext", "Gouraud", "Shaders",           # Graphics/Rendering
    "webrtc", "ice", "candidate", "sdp",         # WebRTC specific
    "Jitsi", "conference", "xmpp", "strophe"     # Jitsi specific (if verbose)
]

def verify_capture_client_debug_logs(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Import shared VLM utils if available (mocked here for standalone)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
    except ImportError:
        def sample_trajectory_frames(t, n): return []
        def query_vlm(**kwargs): return {"success": False}

    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Retrieve Task Results
    # ------------------------------------------------------------------
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_log = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Get JSON result
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
            
        # Get Log Content
        copy_from_env("/tmp/task_log_capture.txt", temp_log.name)
        with open(temp_log.name, 'r', errors='ignore') as f:
            log_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_log.name):
            os.unlink(temp_log.name)

    # ------------------------------------------------------------------
    # 2. Verify Log File Existence and Properties (30 pts)
    # ------------------------------------------------------------------
    log_exists = result.get('log_exists', False)
    log_size = result.get('log_size_bytes', 0)
    created_during = result.get('file_created_during_task', False)
    
    if log_exists:
        score += 10
        feedback_parts.append("Log file exists")
        
        if created_during:
            score += 10
            feedback_parts.append("File created during task")
        else:
            feedback_parts.append("File timestamp verification failed")
            
        if log_size > 500:  # Arbitrary small threshold for "not empty"
            score += 10
            feedback_parts.append(f"Log contains data ({log_size} bytes)")
        elif log_size > 0:
            score += 5
            feedback_parts.append("Log is nearly empty")
        else:
            feedback_parts.append("Log file is empty (redirection failed?)")
    else:
        feedback_parts.append("Log file not found")

    # ------------------------------------------------------------------
    # 3. Verify Log Content (25 pts)
    # ------------------------------------------------------------------
    # We check if the log looks like a browser log
    found_keywords = [k for k in EXPECTED_KEYWORDS if k.lower() in log_content.lower()]
    unique_matches = len(found_keywords)
    
    if unique_matches >= 3:
        score += 25
        feedback_parts.append(f"Log content verified ({unique_matches} signature types found)")
    elif unique_matches >= 1:
        score += 15
        feedback_parts.append("Weak log content evidence")
    else:
        if log_size > 0:
            feedback_parts.append("Log content does not resemble Firefox/Jitsi output")
        
    # ------------------------------------------------------------------
    # 4. Verify Application Termination (10 pts)
    # ------------------------------------------------------------------
    firefox_running = result.get('firefox_running', True)
    if not firefox_running:
        score += 10
        feedback_parts.append("Firefox terminated cleanly")
    else:
        feedback_parts.append("Firefox was left running")

    # ------------------------------------------------------------------
    # 5. VLM Trajectory Verification (35 pts)
    # ------------------------------------------------------------------
    # We look for evidence of:
    # 1. Terminal usage (launching firefox)
    # 2. In-meeting interface (buttons, video tiles)
    
    frames = sample_trajectory_frames(traj, n=6)
    
    if not frames:
        feedback_parts.append("No trajectory frames available for VLM")
    else:
        prompt = """
        Analyze these screenshots of a user performing a task.
        I need to verify two specific phases:
        1. TERMINAL PHASE: Did the user type commands in a terminal window (black/dark background with text)?
        2. MEETING PHASE: Did the user join a video meeting (Jitsi Meet interface with buttons for Mute/Video/Chat)?
        
        Look closely at the meeting phase. Do you see:
        - A central meeting area?
        - Toolbar buttons (Microphone, Camera, Chat/Message icon)?
        - A side panel for Chat (opened at any point)?
        
        Return JSON:
        {
            "terminal_seen": true/false,
            "meeting_interface_seen": true/false,
            "chat_panel_seen": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            
            if parsed.get("terminal_seen"):
                score += 10
                feedback_parts.append("VLM: Terminal usage detected")
            
            if parsed.get("meeting_interface_seen"):
                score += 15
                feedback_parts.append("VLM: Meeting interface detected")
                
            if parsed.get("chat_panel_seen"):
                score += 10
                feedback_parts.append("VLM: Chat interaction detected")
        else:
            # Fallback if VLM fails but logs are good
            if unique_matches >= 3:
                score += 20
                feedback_parts.append("VLM skipped (Log evidence sufficient)")

    # ------------------------------------------------------------------
    # Final Result
    # ------------------------------------------------------------------
    passed = (score >= 70) and log_exists and (log_size > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }