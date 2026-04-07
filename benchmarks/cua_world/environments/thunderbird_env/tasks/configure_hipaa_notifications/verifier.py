#!/usr/bin/env python3
"""
Verifier for configure_hipaa_notifications task.

Verification Strategy:
1. PRIMARY (File-based): Parse Thunderbird's 'prefs.js' file for the required user_pref modifications.
   - mail.biff.play_sound.type == 1
   - mail.biff.play_sound.url contains urgent_chime.wav
   - mail.biff.alert.show_preview == false
   - mailnews.tags.<label>.tag == "URGENT LABS"
2. SECONDARY (Anti-gaming): Verify 'prefs.js' modification timestamp against task duration.
3. TERTIARY (VLM): Ensure agent traversed the Settings UI via trajectory screenshots.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Attempt to import VLM utilities
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    logger.warning("gym_anything.vlm not available. VLM checks will be skipped.")
    VLM_AVAILABLE = False

VLM_PROMPT = """You are verifying an AI agent's trajectory in Mozilla Thunderbird.

The agent's task was to configure HIPAA-compliant settings:
1. Change notification sound to a custom file.
2. Disable 'Message Preview Text' in Desktop Alerts.
3. Create a custom Tag named "URGENT LABS".

Look at the provided sequence of screenshots and determine if the agent meaningfully interacted with the Thunderbird Settings interface. 

Are ANY of the following visible in the screenshot sequence?
1. The Thunderbird "Settings" or "Preferences" tab open.
2. The "Customize Alert" dialog box for incoming mail.
3. A file picker dialog selecting an audio file.
4. The Tags management interface within Settings.

Respond in JSON format:
{
    "settings_tab_visible": true/false,
    "customize_alert_visible": true/false,
    "tags_interface_visible": true/false,
    "meaningful_gui_interaction": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation of what is observed."
}"""

def verify_hipaa_notifications(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.js')
    
    try:
        # Read the export result
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        if not result.get("prefs_copied", False):
            return {"passed": False, "score": 0, "feedback": "prefs.js was not found or copied during export."}

        # Read prefs.js contents
        copy_from_env("/tmp/task_prefs.js", temp_prefs.name)
        with open(temp_prefs.name, 'r', encoding='utf-8', errors='ignore') as f:
            prefs_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result files: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_prefs.name):
            os.unlink(temp_prefs.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Anti-Gaming: Check if prefs.js was modified during task
    # ---------------------------------------------------------
    initial_mtime = result.get("initial_prefs_mtime", 0)
    final_mtime = result.get("final_prefs_mtime", 0)
    task_start = result.get("task_start", 0)
    
    if final_mtime < task_start and initial_mtime == final_mtime:
        feedback_parts.append("WARNING: prefs.js was not modified during the task duration.")
        # We don't instantly fail here, but this is a red flag. If settings were changed from default, it should have updated.

    # ---------------------------------------------------------
    # Criterion 1: Custom Sound Configuration (30 points total)
    # ---------------------------------------------------------
    sound_type_match = re.search(r'user_pref\("mail\.biff\.play_sound\.type",\s*1\);', prefs_content)
    if sound_type_match:
        score += 15
        feedback_parts.append("Custom sound type enabled (15/15)")
    else:
        feedback_parts.append("Custom sound type NOT enabled (0/15)")

    sound_url_match = re.search(r'user_pref\("mail\.biff\.play_sound\.url",\s*"[^"]*urgent_chime\.wav"\);', prefs_content)
    if sound_url_match:
        score += 15
        feedback_parts.append("Correct custom sound file set (15/15)")
    else:
        feedback_parts.append("Correct custom sound file NOT set (0/15)")

    # ---------------------------------------------------------
    # Criterion 2: HIPAA Privacy / Preview Disabled (30 points)
    # ---------------------------------------------------------
    # CRITICAL: This must be explicitly set to false to pass
    preview_match = re.search(r'user_pref\("mail\.biff\.alert\.show_preview",\s*false\);', prefs_content)
    if preview_match:
        score += 30
        feedback_parts.append("Message preview disabled for privacy (30/30)")
    else:
        feedback_parts.append("Message preview NOT disabled [CRITICAL] (0/30)")

    # Ensure alerts aren't entirely disabled (default is true, so we just check it isn't false)
    alert_disabled_match = re.search(r'user_pref\("mail\.biff\.show_alert",\s*false\);', prefs_content)
    if not alert_disabled_match:
        score += 10
        feedback_parts.append("Alerts remain enabled (10/10)")
    else:
        feedback_parts.append("Alerts were entirely disabled instead of just hiding previews (0/10)")

    # ---------------------------------------------------------
    # Criterion 3: Custom Tag "URGENT LABS" (20 points)
    # ---------------------------------------------------------
    tag_match = re.search(r'user_pref\("mailnews\.tags\.[^"]+\.tag",\s*"URGENT LABS"\);', prefs_content)
    if tag_match:
        score += 20
        feedback_parts.append("Custom tag 'URGENT LABS' created (20/20)")
    else:
        feedback_parts.append("Custom tag 'URGENT LABS' NOT created (0/20)")

    # ---------------------------------------------------------
    # Criterion 4: VLM Process Verification (10 points)
    # ---------------------------------------------------------
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
            
            vlm_result = query_vlm(images=frames, prompt=VLM_PROMPT)
            if vlm_result and isinstance(vlm_result, dict):
                gui_interacted = vlm_result.get("meaningful_gui_interaction", False)
                settings_seen = vlm_result.get("settings_tab_visible", False)
                
                if gui_interacted or settings_seen:
                    vlm_score = 10
                    score += 10
                    feedback_parts.append("VLM confirms GUI interaction (10/10)")
                else:
                    feedback_parts.append("VLM did not observe Settings UI interaction (0/10)")
            else:
                feedback_parts.append("VLM query returned invalid format.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped due to error.")
    else:
        # Give free points if VLM isn't available to prevent environment penalization
        score += 10
        feedback_parts.append("VLM not available, granting GUI interaction points (10/10)")

    # ---------------------------------------------------------
    # Final Scoring Determination
    # ---------------------------------------------------------
    # To pass, they must achieve >= 70 points AND have explicitly disabled the message preview (critical for HIPAA)
    privacy_passed = bool(preview_match)
    
    passed = (score >= 70) and privacy_passed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }