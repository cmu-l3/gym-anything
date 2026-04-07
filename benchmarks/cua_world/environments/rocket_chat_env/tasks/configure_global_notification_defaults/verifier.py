#!/usr/bin/env python3
"""
Verifier for configure_global_notification_defaults task.

Verification Strategy:
1. PRIMARY (API): Check `Accounts_Default_User_Preferences` value for Desktop/Mobile 'all' setting.
2. ANTI-GAMING: Compare the `_updatedAt` API timestamp to ensure the agent actually made changes.
3. SECONDARY (VLM): Evaluate the trajectory frames to verify the agent used the Settings interface.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_TRAJECTORY_PROMPT = """You are evaluating a sequence of screenshots from an agent configuring Rocket.Chat.
The images are sampled sequentially across the agent's interaction.

The agent's task is to navigate to Administration -> Settings -> Accounts -> Default User Preferences and change the Desktop and Mobile notification settings to "All Messages".

Assess the following:
1. DID_NAVIGATE_TO_ADMIN: Did the agent open the Administration panel at any point?
2. DID_OPEN_ACCOUNTS_SETTINGS: Is the 'Settings > Accounts' panel visible in any frame?
3. DID_CONFIG_PREFERENCES: Is there evidence the agent modified 'Default User Preferences' (specifically Desktop or Mobile notifications)?

Respond EXACTLY in this JSON format:
{
    "did_navigate_to_admin": true/false,
    "did_open_accounts_settings": true/false,
    "did_config_preferences": true/false,
    "reasoning": "Brief explanation of what is visible across the frames"
}
"""

def verify_configure_global_notification_defaults(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve the exported task data
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
    
    initial_updated_at = result.get('initial_updated_at', '')
    final_updated_at = result.get('final_updated_at', '')
    setting_value = result.get('setting_value', {})
    
    # In RC, the setting value might be stringified JSON or an actual dictionary
    if isinstance(setting_value, str):
        try:
            setting_value = json.loads(setting_value)
        except json.JSONDecodeError:
            setting_value = {}

    # 2. Check API changes and Values
    setting_updated = False
    desktop_all = False
    mobile_all = False
    
    # Check Timestamp difference
    if final_updated_at and initial_updated_at and (final_updated_at != initial_updated_at):
        setting_updated = True
        score += 20
        feedback_parts.append("Settings successfully updated during task.")
    else:
        feedback_parts.append("Settings were NOT modified during task (timestamp unchanged).")

    # Check Desktop Notifications
    desktop_pref = setting_value.get('desktopNotifications', '')
    if str(desktop_pref).lower() == 'all':
        desktop_all = True
        score += 30
        feedback_parts.append("Desktop Notifications correctly set to 'all'.")
    else:
        feedback_parts.append(f"Desktop Notifications incorrect (found: {desktop_pref}).")

    # Check Mobile/Push Notifications
    mobile_pref = setting_value.get('mobileNotifications', '')
    push_pref = setting_value.get('pushNotifications', '')
    if str(mobile_pref).lower() == 'all' or str(push_pref).lower() == 'all':
        mobile_all = True
        score += 30
        feedback_parts.append("Mobile/Push Notifications correctly set to 'all'.")
    else:
        feedback_parts.append(f"Mobile Notifications incorrect (found: mobile={mobile_pref}, push={push_pref}).")

    # 3. Trajectory VLM Verification
    vlm_success = False
    if env_info.get('vlm'):
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            images_to_eval = frames + [final_frame] if final_frame else frames
            
            if images_to_eval:
                vlm_result = env_info['vlm'](prompt=VLM_TRAJECTORY_PROMPT, images=images_to_eval)
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('did_open_accounts_settings') and parsed.get('did_config_preferences'):
                        vlm_success = True
                        score += 20
                        feedback_parts.append("VLM verified Administration Accounts UI usage.")
                    else:
                        feedback_parts.append("VLM did not observe Accounts UI interaction.")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification skipped/failed.")

    # Determine passing grade
    # Must have actually updated the setting AND successfully set both dropdowns correctly.
    passed = setting_updated and desktop_all and mobile_all
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }