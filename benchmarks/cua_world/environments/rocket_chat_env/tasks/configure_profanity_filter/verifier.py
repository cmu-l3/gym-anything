#!/usr/bin/env python3
"""
Verifier for configure_profanity_filter task.

Checks:
1. Message_AllowBadWordsFilter is true (30 pts)
2. Message_BadWordsFilterList contains required words (40 pts)
3. Test message exists in #general and shows censorship (15 pts)
4. VLM verifies admin panel navigation (15 pts)
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any, List

# Import VLM utilities from framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REQUIRED_WORDS = ["classified", "confidential", "proprietary", "restricted"]

def verify_configure_profanity_filter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result data
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
    
    # 1. Check Filter Enabled (30 pts)
    settings_enabled = result.get("settings_enabled", "false")
    if str(settings_enabled).lower() == "true":
        score += 30
        feedback_parts.append("Bad Words Filter enabled (+30)")
    else:
        feedback_parts.append("Bad Words Filter NOT enabled")

    # 2. Check Custom Words (40 pts)
    settings_list = result.get("settings_list", "").lower()
    words_found = [w for w in REQUIRED_WORDS if w in settings_list]
    
    if len(words_found) == 4:
        score += 40
        feedback_parts.append("All 4 custom words found in list (+40)")
    elif len(words_found) > 0:
        partial_score = len(words_found) * 10
        score += partial_score
        feedback_parts.append(f"Found {len(words_found)}/4 custom words (+{partial_score})")
    else:
        feedback_parts.append("No required custom words found in list")

    # 3. Check Test Message (15 pts)
    recent_messages = result.get("recent_messages", [])
    task_start = result.get("task_start", 0)
    
    # Sort messages by timestamp (ts) descending
    # Rocket.Chat timestamps are often milliseconds, task_start is seconds
    # Convert ts from ms to s for comparison if needed, or just look at recent list
    
    found_censored_msg = False
    found_uncensored_test = False
    
    for msg in recent_messages:
        text = msg.get("msg", "")
        # Check if message is from this session (simple heuristic: exists in the recent fetch)
        # We really care about content.
        
        # Check for asterisks indicating censorship
        if "*" * 3 in text:
            found_censored_msg = True
            break
            
        # Check if they posted the test word but it WASN'T censored (filter failed)
        if any(w in text.lower() for w in REQUIRED_WORDS):
            found_uncensored_test = True

    if found_censored_msg:
        score += 15
        feedback_parts.append("Verification message posted and correctly censored (+15)")
    elif found_uncensored_test:
        score += 5
        feedback_parts.append("Test message posted but NOT censored (filter inactive?) (+5)")
    else:
        feedback_parts.append("No test message found in #general")

    # 4. VLM Verification (15 pts)
    # Use trajectory frames to verify they actually navigated the admin panel
    frames = sample_trajectory_frames(traj, n=6)
    
    if frames:
        vlm_prompt = """
        Analyze these screenshots of a user configuring Rocket.Chat.
        I am looking for evidence that the user navigated to the Administration/Settings panel.
        
        Look for:
        1. The 'Administration' sidebar or menu.
        2. A 'Settings' screen, specifically 'Message' settings.
        3. A toggle for 'Bad Words Filter'.
        4. A text input field where words like 'classified' or 'restricted' are being typed.
        
        Did the user navigate to the admin settings based on these frames?
        Return JSON: {"admin_navigation_confirmed": true/false, "reason": "..."}
        """
        
        vlm_resp = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_resp.get("success"):
            parsed = vlm_resp.get("parsed", {})
            if parsed.get("admin_navigation_confirmed"):
                score += 15
                feedback_parts.append("VLM confirmed admin navigation (+15)")
            else:
                # Fallback: if they got the settings right programmatically, give them the points
                # because they must have navigated there to change them.
                if str(settings_enabled).lower() == "true" and len(words_found) >= 3:
                     score += 15
                     feedback_parts.append("Implicit navigation confirmation via settings change (+15)")
                else:
                    feedback_parts.append("VLM did not observe admin navigation")
        else:
             # Fallback on failure
             if str(settings_enabled).lower() == "true":
                 score += 15
                 feedback_parts.append("VLM unavailable, trusting settings change (+15)")
    else:
        # No frames? Fallback to trusting the settings check
        if str(settings_enabled).lower() == "true" and len(words_found) >= 1:
            score += 15
            feedback_parts.append("No frames, trusting settings change (+15)")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }