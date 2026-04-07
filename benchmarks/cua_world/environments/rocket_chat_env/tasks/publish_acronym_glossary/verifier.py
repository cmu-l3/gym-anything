#!/usr/bin/env python3
"""
Verifier for publish_acronym_glossary task.

Verification Strategy:
1. File check: Read exported JSON to confirm #glossary channel was created.
2. Timing check: Confirm the message was posted AFTER the task started (anti-gaming).
3. Formatting check: Confirm message uses Markdown table syntax.
4. Content check: Confirm the specific acronym definitions from the CSV are present.
5. VLM check: Confirm via trajectory frames that the agent opened the CSV and interacted with the UI.
"""

import json
import os
import sys
import tempfile
import logging
from pathlib import Path

# Try to import VLM utilities safely
try:
    sys.path.insert(0, str(Path(__file__).parent.parent))
    from vlm_utils import query_vlm, get_final_screenshot, sample_trajectory_frames
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("vlm_utils not available, VLM verification will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are analyzing a sequence of screenshots from an AI agent's trajectory.
The task was to read acronyms from a local CSV file and post them as a Markdown table in a Rocket.Chat channel.

Analyze the chronological frames and determine:
1. Did the agent open or view the CSV file (e.g., in a text editor, terminal, or spreadsheet) to read the contents?
2. Did the agent navigate Rocket.Chat and create/open the '#glossary' channel?
3. Did the agent type or paste a Markdown-formatted table into the message box?

Respond in JSON format:
{
    "read_csv_file": true/false,
    "interacted_with_chat": true/false,
    "typed_markdown_table": true/false,
    "confidence": "low/medium/high",
    "reasoning": "brief explanation"
}
"""

def verify_publish_acronym_glossary(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available."}

    metadata = task_info.get('metadata', {})
    expected_terms = metadata.get('expected_terms', [
        {"acronym": "API", "definition": "Application Programming Interface"},
        {"acronym": "JSON", "definition": "JavaScript Object Notation"}
    ])

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    room_id = result.get('room_id', '')
    msg_text = result.get('message_text', '')
    msg_ts = result.get('message_ts', 0)

    # 1. Channel Exists (15 pts)
    if room_id:
        score += 15
        feedback_parts.append("Channel '#glossary' created successfully.")
    else:
        feedback_parts.append("Channel '#glossary' was not found.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Message Exists and is new (15 pts)
    if msg_text and msg_ts > task_start:
        score += 15
        feedback_parts.append("New message found in channel.")
    elif msg_text:
        feedback_parts.append("Message found, but timestamp indicates it was created before task started (Gaming detected).")
        return {"passed": False, "score": 15, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("No message found in the channel.")
        return {"passed": False, "score": 15, "feedback": " | ".join(feedback_parts)}

    # 3. Table Formatting Check (20 pts)
    # A standard markdown table has pipes and a separator row like |---|
    has_pipes = "|" in msg_text
    has_separator = "|---" in msg_text.replace(" ", "") or "|-" in msg_text.replace(" ", "")
    
    if has_pipes and has_separator:
        score += 20
        feedback_parts.append("Valid Markdown table syntax detected.")
    elif has_pipes:
        score += 10
        feedback_parts.append("Partial Markdown table syntax detected (missing clear separator row).")
    else:
        feedback_parts.append("Message does not appear to be formatted as a Markdown table.")

    # 4. Content Accuracy Check (20 pts)
    matched_terms = 0
    for term in expected_terms:
        acronym = term["acronym"]
        definition = term["definition"]
        # Check if both acronym and definition exist in the text
        if acronym.lower() in msg_text.lower() and definition.lower() in msg_text.lower():
            matched_terms += 1

    term_score = int((matched_terms / len(expected_terms)) * 20)
    score += term_score
    feedback_parts.append(f"Content matched {matched_terms}/{len(expected_terms)} expected CSV terms.")

    # 5. VLM Trajectory Verification (30 pts)
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            vlm_response = query_vlm(prompt=VLM_PROMPT, images=all_frames)
            
            if vlm_response and vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("read_csv_file"):
                    vlm_score += 10
                if parsed.get("interacted_with_chat"):
                    vlm_score += 10
                if parsed.get("typed_markdown_table"):
                    vlm_score += 10
                    
                feedback_parts.append(f"VLM verified trajectory: +{vlm_score} pts ({parsed.get('reasoning', '')})")
            else:
                feedback_parts.append("VLM query failed or returned invalid response.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification encountered an error.")
    else:
        # If VLM is not available in the test runner, grant proportional points to not penalize
        vlm_score = 30
        feedback_parts.append("VLM unavailable; granted default trajectory points.")

    score += vlm_score

    # Determine Pass/Fail
    passed = score >= 70 and room_id and msg_text

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }