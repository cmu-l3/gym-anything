#!/usr/bin/env python3
"""
Verifier for create_custom_project_tags task.

Verification Strategy:
1. Copy `prefs.js` and `Inbox` via copy_from_env.
2. Parse `prefs.js` to confirm the tag "Audit 2026" was created and identify its internal key.
3. Validate the color of the custom tag is a purple hue (R>G, B>G).
4. Parse the `Inbox` mbox file to verify the 3 target emails have the internal tag key applied.
5. Anti-gaming check: Deduct points if the tag is applied to too many emails (bulk-tagging).
6. Hybrid VLM: Use trajectory frames to verify settings and UI interaction.
"""

import os
import json
import re
import tempfile
import mailbox
import logging
import email

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Fallback path if environment uses a different profile name structure
DEFAULT_PROFILE_PATH = "/home/ga/.thunderbird/default-release"


def verify_custom_tags(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tag_name = metadata.get('expected_tag_name', 'Audit 2026')
    target_subjects = metadata.get('target_subjects', [])
    bulk_limit = metadata.get('bulk_tagging_limit', 5)

    score = 0
    feedback_parts = []
    
    # 1. Read task result metadata
    result_data = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
        try:
            copy_from_env("/tmp/task_result.json", tmp.name)
            with open(tmp.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            logger.warning(f"Could not load task_result.json: {e}")
        finally:
            os.unlink(tmp.name)

    # Check timestamps to detect 'do nothing'
    if not result_data.get('prefs_modified_during_task', False):
        feedback_parts.append("prefs.js was not modified (No preferences changed)")
    if not result_data.get('inbox_modified_during_task', False):
        feedback_parts.append("Inbox was not modified (No tags applied)")

    # 2. Copy and parse prefs.js
    prefs_content = ""
    with tempfile.NamedTemporaryFile(delete=False, suffix='.js') as tmp:
        try:
            copy_from_env(f"{DEFAULT_PROFILE_PATH}/prefs.js", tmp.name)
            with open(tmp.name, 'r', encoding='utf-8', errors='ignore') as f:
                prefs_content = f.read()
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read prefs.js: {e}"}
        finally:
            os.unlink(tmp.name)

    # Regex to find: user_pref("mail.tags.something.tag", "Audit 2026");
    # We want to extract 'something'
    tag_key = None
    tag_name_pattern = re.compile(r'user_pref\("mail\.tags\.([^.]+)\.tag",\s*"([^"]+)"\);')
    
    for match in tag_name_pattern.finditer(prefs_content):
        extracted_key, extracted_name = match.groups()
        if extracted_name.strip().lower() == expected_tag_name.lower():
            tag_key = extracted_key
            break

    if tag_key:
        score += 30
        feedback_parts.append(f"Custom tag '{expected_tag_name}' created (internal key: {tag_key})")
    else:
        feedback_parts.append(f"Custom tag '{expected_tag_name}' NOT found in preferences")
        # If the tag wasn't created, they can't pass the rest of the programmatic checks reliably.
        # But we will continue to check VLM.

    # 3. Check tag color
    color_valid = False
    if tag_key:
        color_pattern = re.compile(fr'user_pref\("mail\.tags\.{tag_key}\.color",\s*"#([0-9a-fA-F]{{6}})"\);')
        color_match = color_pattern.search(prefs_content)
        if color_match:
            hex_color = color_match.group(1)
            r = int(hex_color[0:2], 16)
            g = int(hex_color[2:4], 16)
            b = int(hex_color[4:6], 16)
            
            # Check if it's a purple hue: Red and Blue must both be significantly higher than Green
            if r > g * 1.1 and b > g * 1.1 and (r + b) > 100:
                color_valid = True
                score += 10
                feedback_parts.append(f"Tag color is purple (#{hex_color})")
            else:
                feedback_parts.append(f"Tag color (#{hex_color}) does not appear to be purple")
        else:
            feedback_parts.append("No color assigned to the custom tag")

    # 4. Copy and parse Inbox mbox
    targets_tagged_count = 0
    total_emails_tagged = 0
    
    if tag_key:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.mbox') as tmp:
            try:
                copy_from_env(f"{DEFAULT_PROFILE_PATH}/Mail/Local Folders/Inbox", tmp.name)
                mbox = mailbox.mbox(tmp.name)
                
                for msg in mbox:
                    subject = str(msg.get('Subject', '')).strip()
                    keys_header = str(msg.get('X-Mozilla-Keys', '')).strip().lower()
                    
                    # Check if our tag key is applied to this email
                    has_tag = tag_key.lower() in keys_header.split()
                    
                    if has_tag:
                        total_emails_tagged += 1
                        
                        # Is it one of our targets?
                        for target in target_subjects:
                            if target.lower() in subject.lower():
                                targets_tagged_count += 1
                                break
                                
            except Exception as e:
                logger.warning(f"Error reading Inbox mbox: {e}")
                feedback_parts.append(f"Error reading Inbox: {e}")
            finally:
                os.unlink(tmp.name)

        # Score target emails
        if targets_tagged_count > 0:
            points_per_target = 45 / len(target_subjects)
            score += int(targets_tagged_count * points_per_target)
            feedback_parts.append(f"Applied tag to {targets_tagged_count}/{len(target_subjects)} target emails")
        else:
            feedback_parts.append("Did not apply custom tag to any target emails")

        # 5. Anti-gaming check
        if total_emails_tagged > bulk_limit:
            score -= 100
            feedback_parts.append(f"PENALTY: Tag applied to {total_emails_tagged} emails (bulk tagging detected)")

    # 6. Hybrid VLM Verification (Trajectory checking)
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=6)
        
        prompt = """You are assessing an AI agent using Thunderbird email client.
The agent was tasked to create a custom tag named 'Audit 2026' (colored purple) and apply it to specific emails.

Look at these screenshots taken during the agent's workflow.
1. SETTINGS_OPEN: Did the agent open the Thunderbird Settings / Options window, specifically the Tags section?
2. PURPLE_TAG_VISIBLE: In the email list (Inbox), can you see any emails labeled with a new purple-colored tag indicator (like 'Audit 2026')?

Respond in JSON format:
{
    "settings_opened": true/false,
    "purple_tag_visible": true/false,
    "reasoning": "Briefly explain what UI elements you observed"
}
"""
        if frames:
            vlm_res = query_vlm(images=frames, prompt=prompt)
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('settings_opened'):
                    score += 5
                    feedback_parts.append("VLM confirmed Settings/Tags menu was accessed")
                if parsed.get('purple_tag_visible'):
                    score += 10
                    feedback_parts.append("VLM visually confirmed purple tag on emails")
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Ensure score bounds
    score = max(0, min(100, score))
    
    # Pass condition
    # Must have created the tag AND tagged at least 2 out of 3 targets (without triggering the bulk penalty)
    passed = tag_key is not None and targets_tagged_count >= 2 and score >= 65

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }