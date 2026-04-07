#!/usr/bin/env python3
"""
Verifier for thread_reply_release task.

Verification Strategy:
1. API State Verification (Primary): 
   - Check if a thread reply exists attached to the correct target message ID.
   - Validate timestamp (must be created after task start).
   - Validate text content (key phrases matching the required review message).
   - Validate authorship (posted by admin).
2. Anti-Gaming Detection:
   - Check channel history to ensure the agent didn't post the text as a normal 
     top-level channel message instead of inside the thread.
3. VLM Trajectory Verification:
   - Sample frames across the trajectory to confirm the thread UI panel was actually
     opened and used.
"""

import os
import json
import logging
import tempfile
from datetime import datetime

# Attempt to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_THREAD_PROMPT = """You are analyzing chronological screenshots of an AI agent using Rocket.Chat.
The agent's task is to reply to a specific channel message IN A THREAD. 

Look at the progression of these screenshots:
1. Does the agent open the thread panel (this appears as a side panel on the right side of the screen labeled "Thread")?
2. Does the agent type its message inside that right-hand thread panel?

Note: Typing a message in the main chat input at the bottom center of the screen is a REGULAR channel message and is INCORRECT. The input MUST be inside the thread sidebar.

Respond ONLY with a JSON object:
{
    "opened_thread_panel": true/false,
    "typed_in_thread_input": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is seen in the frames"
}
"""

def verify_thread_reply(traj, env_info, task_info):
    """Verify that the agent replied in a thread correctly."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_phrases = [p.lower() for p in metadata.get('required_phrases', [
        "verified", "ubuntu 22.04", "no regressions", "staging deployment"
    ])]

    # 1. Extract and load task result from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)
    target_msg_id = result.get('target_msg_id', '')
    thread_messages = result.get('thread_messages', [])
    channel_messages = result.get('channel_messages', [])

    score = 0
    feedback_parts = []
    
    # 2. Analyze Thread Messages
    # Filter out the parent message (its _id equals the target_msg_id)
    thread_replies = [m for m in thread_messages if m.get('_id') != target_msg_id]
    
    best_reply = None
    best_phrase_count = 0
    
    for reply in thread_replies:
        msg_text = reply.get('msg', '').lower()
        phrase_count = sum(1 for p in required_phrases if p in msg_text)
        if phrase_count > best_phrase_count:
            best_phrase_count = phrase_count
            best_reply = reply

    # Score Criterion 1: Thread reply exists & content matches
    content_matches = False
    if best_reply:
        if best_phrase_count == len(required_phrases):
            score += 40
            content_matches = True
            feedback_parts.append("Thread reply found with perfect content match.")
        elif best_phrase_count >= 2:
            score += 20
            feedback_parts.append(f"Thread reply found with partial content match ({best_phrase_count}/{len(required_phrases)} phrases).")
        else:
            score += 5
            feedback_parts.append("Thread reply found but content is mostly incorrect.")
            
        # Timestamp Check (Anti-gaming)
        reply_ts = best_reply.get('ts', '')
        try:
            # Parse Rocket.Chat ISO string (e.g. "2026-03-08T21:00:00.000Z")
            if isinstance(reply_ts, str):
                dt = datetime.fromisoformat(reply_ts.replace("Z", "+00:00"))
                reply_epoch = dt.timestamp()
                if reply_epoch >= (task_start - 60):  # 60s tolerance for clock drift
                    score += 15
                    feedback_parts.append("Reply timestamp is valid.")
                else:
                    feedback_parts.append("Reply was created BEFORE task started (Stale data).")
        except Exception:
            feedback_parts.append("Could not parse reply timestamp.")
            
        # Authorship Check
        if best_reply.get('u', {}).get('username') == "admin":
            score += 15
            feedback_parts.append("Reply authored by admin.")
        else:
            feedback_parts.append("Reply not authored by admin.")
    else:
        feedback_parts.append("No thread replies found on target message.")

    # 3. Anti-Gaming Detection: Check if they just posted it to the channel
    posted_to_channel_instead = False
    for msg in channel_messages:
        # If it lacks a 'tmid', it's a top-level channel message
        if not msg.get('tmid'):
            msg_text = msg.get('msg', '').lower()
            if sum(1 for p in required_phrases if p in msg_text) >= 2:
                posted_to_channel_instead = True
                break
                
    if posted_to_channel_instead and not content_matches:
        score = 0  # Penalize completely if they failed the core constraint
        feedback_parts = ["CRITICAL FAILURE: Agent posted the text as a regular channel message instead of replying in a thread."]

    # 4. VLM Verification (Trajectory checking the UI usage)
    if VLM_AVAILABLE and 'query_vlm' in env_info and not posted_to_channel_instead and best_reply:
        try:
            query_vlm = env_info['query_vlm']
            # Sample frames from the trajectory (beginning, middle, end) + final
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            vlm_resp = query_vlm(
                prompt=VLM_THREAD_PROMPT,
                images=frames
            )
            
            if vlm_resp.get("success"):
                parsed = vlm_resp.get("parsed", {})
                if parsed.get("opened_thread_panel") and parsed.get("typed_in_thread_input"):
                    score += 30
                    feedback_parts.append("VLM confirmed interaction with the thread UI panel.")
                else:
                    feedback_parts.append("VLM did not detect interaction with the thread UI.")
            else:
                feedback_parts.append("VLM query failed or returned invalid JSON.")
                # Give partial credit if API checks passed but VLM failed technically
                score += 15 
        except Exception as e:
            logger.warning(f"VLM Exception: {e}")
            score += 15 # Fallback points if VLM crashes but API passed

    elif not VLM_AVAILABLE and best_reply and not posted_to_channel_instead:
        # Give fallback points if VLM is completely disabled in environment
        score += 30 
        feedback_parts.append("VLM verification skipped (not available).")

    # Pass logic: Must have a high score and not have posted to the channel instead
    passed = score >= 70 and not posted_to_channel_instead

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }