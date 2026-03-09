#!/usr/bin/env python3
"""
Verifier for send_chat_message task.

Criteria:
1.  Agent must join the meeting (leave pre-join screen).
2.  Agent must open the chat panel.
3.  Agent must send the specific workout message.
4.  Agent must set the display name "Coach Mara".

Verification Strategy:
- Primary: VLM analysis of trajectory frames (to see workflow) and final screenshot.
- Secondary: Text search in scraped DOM content (if available).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_send_chat_message(traj, env_info, task_info):
    """
    Verify that the agent joined the meeting and sent the correct chat message.
    """
    # 1. Setup & Data Retrieval
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_key_terms = metadata.get('key_terms', ["3 rounds", "20 squats", "15 push-ups"])
    
    score = 0
    feedback_parts = []
    
    # Load result JSON
    task_result = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.warning(f"Could not load task result: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Load console dump text (secondary signal)
    console_text = ""
    temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/console_dump.txt", temp_txt.name)
        with open(temp_txt.name, 'r', errors='ignore') as f:
            console_text = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_txt.name):
            os.unlink(temp_txt.name)

    # 2. Programmatic Text Check (Bonus points)
    # If we managed to scrape the DOM, check for key terms
    text_matches = 0
    for term in expected_key_terms:
        if term.lower() in console_text.lower():
            text_matches += 1
    
    if text_matches >= 3:
        score += 20
        feedback_parts.append(f"Found {text_matches} key terms in page text.")
    
    # 3. VLM Verification (Primary)
    # We check the final state and the workflow
    final_screenshot = get_final_screenshot(traj)
    frames = sample_trajectory_frames(traj, n=4)
    all_images = frames + [final_screenshot] if final_screenshot else frames

    if not all_images:
        return {"passed": False, "score": 0, "feedback": "No screenshots available for verification"}

    prompt = """
    You are verifying an agent's performance in a video conferencing app (Jitsi Meet).
    
    Task Goal: 
    1. Join meeting room "MorningFitness" as "Coach Mara".
    2. Open Chat Panel.
    3. Send message: "Today's Workout: 3 rounds - 20 squats, 15 push-ups, 10 burpees. Rest 60s between rounds."
    
    Review the sequence of screenshots and the FINAL screenshot.
    
    Check for:
    1. MEETING_JOINED: Is the agent in a meeting (video grid/toolbar visible)? NOT on the "Join Meeting" name entry screen.
    2. CHAT_OPEN: Is the side panel for Chat open (usually on the right)?
    3. MESSAGE_SENT: Is the specific workout message visible in the chat history? (Look for '3 rounds', 'squats', 'burpees').
    4. SENDER_NAME: Is the message attributed to "Coach Mara" or is "Coach Mara" visible as the user?
    
    Respond in JSON:
    {
        "meeting_joined": boolean,
        "chat_panel_open": boolean,
        "message_content_visible": boolean,
        "sender_name_correct": boolean,
        "confidence": "high/medium/low",
        "reasoning": "string"
    }
    """

    vlm_result = query_vlm(prompt=prompt, images=all_images)
    
    if not vlm_result.get("success"):
        # Fallback if VLM fails but text matched
        if text_matches >= 3:
            return {"passed": True, "score": 70, "feedback": "VLM failed but text check passed."}
        return {"passed": False, "score": 0, "feedback": "VLM verification failed to run."}

    parsed = vlm_result.get("parsed", {})
    logger.info(f"VLM Result: {parsed}")

    # Scoring Logic
    # Meeting Joined: 20 pts
    if parsed.get("meeting_joined"):
        score += 20
        feedback_parts.append("Meeting joined.")
    else:
        feedback_parts.append("Meeting NOT joined.")

    # Chat Open: 20 pts
    if parsed.get("chat_panel_open"):
        score += 20
        feedback_parts.append("Chat panel open.")

    # Message Content: 30 pts
    if parsed.get("message_content_visible"):
        score += 30
        feedback_parts.append("Message content verified.")
    elif text_matches >= 3:
        # Fallback to text check if VLM missed it (e.g., small text)
        score = max(score, score + 30) # Avoid double counting if VLM said no but text said yes? Actually text check was +20 bonus earlier. Let's cap.
        feedback_parts.append("Message content verified via text scrape.")

    # Sender Name: 10 pts
    if parsed.get("sender_name_correct"):
        score += 10
        feedback_parts.append("Display name verified.")

    # Total Score Calculation
    # Max possible via VLM: 80 + 20 (programmatic bonus) = 100
    # We verify if score > 100 cap it.
    score = min(100, score)

    # Pass threshold
    # Must have joined meeting, opened chat, and sent message (approx 70 pts)
    passed = score >= 70 and parsed.get("meeting_joined")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) + f" (Reasoning: {parsed.get('reasoning')})",
        "details": parsed
    }