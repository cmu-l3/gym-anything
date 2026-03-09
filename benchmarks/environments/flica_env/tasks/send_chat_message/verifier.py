#!/usr/bin/env python3
"""
Verifier for send_chat_message task.

Checks:
1. Programmatic: Parses Android UI hierarchy (XML) to confirm message text exists and is sent (not in EditText).
2. VLM: Uses trajectory to verify workflow (Home -> Chat -> Type -> Send).
3. Anti-gaming: Checks task duration and app state.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_send_chat_message(traj, env_info, task_info):
    """
    Verify that the agent sent the correct chat message.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_message = metadata.get('target_message', "Arriving gate B7 at 4:30 PM - meet at baggage claim 3")
    
    score = 0
    feedback_parts = []
    
    # ------------------------------------------------------------------
    # 1. Fetch Data from Environment
    # ------------------------------------------------------------------
    temp_dir = tempfile.mkdtemp()
    try:
        # Copy JSON result
        json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/sdcard/task_result.json", json_path)
            with open(json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.error(f"Failed to load task result: {e}")
            result_data = {}

        # Copy UI Dump XML
        xml_path = os.path.join(temp_dir, "final_ui_state.xml")
        xml_content = ""
        try:
            copy_from_env("/sdcard/final_ui_state.xml", xml_path)
            with open(xml_path, 'r', encoding='utf-8', errors='ignore') as f:
                xml_content = f.read()
        except Exception as e:
            logger.warning(f"Failed to load UI XML: {e}")
    finally:
        # Cleanup happens at end or separate process, but here we just leave temp dir 
        # for debugging if needed, or rely on OS cleanup. 
        # For strictness:
        pass

    # ------------------------------------------------------------------
    # 2. Anti-Gaming & Basic Checks
    # ------------------------------------------------------------------
    duration = result_data.get("duration_seconds", 0)
    app_running = result_data.get("app_running", False)

    if duration < 5:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Task completed suspiciously fast ({duration}s). Possible gaming."
        }
    
    if not app_running:
        feedback_parts.append("Warning: App was not in foreground at end of task.")
    else:
        score += 5 # App is running

    # ------------------------------------------------------------------
    # 3. UI XML Verification (Programmatic)
    # ------------------------------------------------------------------
    text_found = False
    is_sent = False
    left_home = True

    if xml_content:
        # Check if we are still on home screen
        if "Add New Friend" in xml_content and "Friends" in xml_content:
            left_home = False
            feedback_parts.append("Failed: Still on Friends home screen.")
        else:
            score += 10 # Left home screen
            
        # Parse XML to find message
        try:
            root = ET.fromstring(xml_content)
            
            # Helper to find text
            for node in root.iter():
                text = node.attrib.get('text', '')
                content_desc = node.attrib.get('content-desc', '')
                resource_id = node.attrib.get('resource-id', '')
                class_name = node.attrib.get('class', '')
                
                # Check for target text
                if target_message in text or target_message in content_desc:
                    text_found = True
                    
                    # Check if it's an input field (EditText)
                    if 'EditText' in class_name:
                        is_sent = False
                        feedback_parts.append("Message found but appears to be in input field (Draft).")
                    else:
                        # Likely a TextView, meaning it's sent/displayed
                        is_sent = True
        except ET.ParseError:
            # Fallback to string matching if XML is malformed
            if target_message in xml_content:
                text_found = True
                # Cannot determine if sent or draft reliably without XML structure
                is_sent = False 
                feedback_parts.append("Message found in UI dump (structure unclear).")

    if text_found:
        score += 20
        if is_sent:
            score += 25 # Bonus for confirming it's not in EditText
            feedback_parts.append("Message successfully verified in chat history.")
    else:
        # Check partials
        if "Arriving gate B7" in xml_content:
            score += 10
            feedback_parts.append("Partial message text found.")
        else:
            feedback_parts.append("Message text NOT found in UI.")

    # ------------------------------------------------------------------
    # 4. VLM Verification (Trajectory & Final State)
    # ------------------------------------------------------------------
    # We use VLM to verify the workflow and visual confirmation of "Sent" status
    # This is crucial because XML might be tricky with custom views (Recycler adapters)
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    
    prompt = f"""
    You are verifying an agent's performance in an Android app "Flight Crew View".
    Goal: Navigate to chat and send message: "{target_message}".
    
    Review the image sequence. 
    1. Did the agent navigate away from the initial "Friends" list?
    2. Did the agent reach a chat interface (look for message bubbles/input field)?
    3. Is the specific message "{target_message}" visible in the conversation?
    4. Does the message appear to be SENT (in a bubble) rather than just typed in the input box?
    
    Return JSON:
    {{
      "navigated_to_chat": true/false,
      "message_visible": true/false,
      "message_sent": true/false,
      "confidence": 0-10
    }}
    """
    
    vlm_result = query_vlm(images=frames + [final_frame], prompt=prompt)
    
    vlm_score = 0
    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("navigated_to_chat"):
            vlm_score += 15
        if parsed.get("message_visible"):
            vlm_score += 10
        if parsed.get("message_sent"):
            vlm_score += 15
        
        feedback_parts.append(f"VLM Analysis: Chat={parsed.get('navigated_to_chat')}, Sent={parsed.get('message_sent')}")
    else:
        feedback_parts.append("VLM verification failed to run.")
    
    score += vlm_score

    # ------------------------------------------------------------------
    # 5. Final Scoring
    # ------------------------------------------------------------------
    # Max Score Breakdown:
    # - App Running: 5
    # - Left Home (XML): 10
    # - Text Found (XML): 20
    # - Text Sent (XML): 25
    # - VLM Nav: 15
    # - VLM Visible: 10
    # - VLM Sent: 15
    # Total: 100
    
    passed = score >= 60 and (text_found or (vlm_result.get("parsed", {}).get("message_visible")))

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }