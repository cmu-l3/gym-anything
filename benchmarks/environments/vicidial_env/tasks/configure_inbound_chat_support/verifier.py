#!/usr/bin/env python3
import json
import os
import tempfile
import logging

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_inbound_chat_support(traj, env_info, task_info):
    """
    Verifies that the agent enabled 'allow_chats' and created the 'TECHSUP' chat group
    with specific configuration details.
    """
    
    # 1. Setup and Load Data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Infrastructure error: copy_from_env not available"}

    # Load expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_allow_chats = metadata.get('expected_setting_allow_chats', '1')
    expected_group_id = metadata.get('expected_group_id', 'TECHSUP')
    expected_group_name = metadata.get('expected_group_name', 'Tech Support Chat')
    expected_color = metadata.get('expected_group_color', 'CCCCFF')
    expected_msg = metadata.get('expected_welcome_message', 'Welcome to Tech Support. Please describe your issue.')

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result file: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Scoring Logic
    score = 0
    feedback_lines = []
    
    # Criterion 1: System Setting 'allow_chats' (30 pts)
    actual_allow_chats = str(result.get('allow_chats_setting', '0'))
    if actual_allow_chats == expected_allow_chats:
        score += 30
        feedback_lines.append(f"✅ System Setting 'Allow Chats' enabled.")
    else:
        feedback_lines.append(f"❌ System Setting 'Allow Chats' is {actual_allow_chats} (Expected: {expected_allow_chats}).")

    # Criterion 2: Group Exists (20 pts)
    group_exists = result.get('group_exists', False)
    group_details = result.get('group_details', {})
    
    if group_exists:
        score += 20
        feedback_lines.append(f"✅ Chat Group '{expected_group_id}' created.")
        
        # Criterion 3: Group Name (10 pts)
        if group_details.get('name') == expected_group_name:
            score += 10
            feedback_lines.append(f"✅ Group Name matches.")
        else:
            feedback_lines.append(f"❌ Group Name mismatch. Got: '{group_details.get('name')}'")

        # Criterion 4: Active Status (10 pts)
        if group_details.get('active') == 'Y':
            score += 10
            feedback_lines.append(f"✅ Group is Active.")
        else:
            feedback_lines.append(f"❌ Group is not Active.")

        # Criterion 5: Color (10 pts)
        if group_details.get('color') == expected_color:
            score += 10
            feedback_lines.append(f"✅ Group Color matches.")
        else:
            feedback_lines.append(f"❌ Group Color mismatch. Got: '{group_details.get('color')}'")

        # Criterion 6: Welcome Message (20 pts)
        # We allow whitespace tolerance
        actual_msg = group_details.get('welcome_message', '').strip()
        if actual_msg == expected_msg.strip():
            score += 20
            feedback_lines.append(f"✅ Welcome Message matches.")
        else:
            feedback_lines.append(f"❌ Welcome Message mismatch.")
            logger.info(f"Expected msg: {expected_msg}")
            logger.info(f"Actual msg: {actual_msg}")

    else:
        feedback_lines.append(f"❌ Chat Group '{expected_group_id}' was not created.")

    # 3. Final Determination
    # Pass threshold: 70 points. This requires enabling the setting + creating the group + getting most details right.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_lines)
    }