#!/usr/bin/env python3
"""
Verifier for process_bounced_emails task.

Verification Criteria:
1. `bounced_contacts.txt` exists and was modified during the task.
2. The text file contains exactly the 4 expected email addresses.
3. The `Bounces` folder was created in Thunderbird.
4. The 4 NDR emails were moved to the `Bounces` folder.
5. The Inbox no longer contains the 4 NDR emails.
6. VLM trajectory verification to ensure GUI usage.
"""

import os
import re
import json
import tempfile
import logging
import sys

# Add utils to path to use Thunderbird verification utilities
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from thunderbird_verification_utils import setup_thunderbird_verification, cleanup_verification_temp, parse_mbox_file
except ImportError:
    # Fallback if utils are missing
    pass

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_bounces_in_mbox(mbox_path, patterns):
    """Count how many bounce messages (by subject pattern) are in an mbox file."""
    if not mbox_path or not os.path.exists(mbox_path):
        return 0
    
    try:
        # Import dynamically in case it's not available globally
        import mailbox
        mbox = mailbox.mbox(str(mbox_path))
        count = 0
        for msg in mbox:
            subject = msg.get('Subject', '')
            for pattern in patterns:
                if re.search(pattern, subject, re.IGNORECASE):
                    count += 1
                    break  # Found a match, move to next message
        return count
    except Exception as e:
        logger.error(f"Error parsing mbox {mbox_path}: {e}")
        return 0


def verify_bounced_emails(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_addresses = [addr.lower() for addr in metadata.get('expected_addresses', [])]
    bounce_patterns = metadata.get('ndr_subject_patterns', [])
    
    feedback_parts = []
    score = 0

    # ================================================================
    # Read the JSON result exported from the container
    # ================================================================
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

    # ================================================================
    # CRITERION 1: Text File Checks (30 points)
    # ================================================================
    text_file_exists = result.get('text_file_exists', False)
    file_created_during_task = result.get('file_created_during_task', False)
    file_content = result.get('file_content', '')

    if text_file_exists:
        if file_created_during_task:
            score += 10
            feedback_parts.append("Contacts file successfully created during task")
        else:
            feedback_parts.append("Contacts file exists but was not modified during the task (Gaming attempt?)")

        # Extract emails using regex
        found_emails = re.findall(r'[\w\.-]+@[\w\.-]+\.\w+', file_content)
        found_emails_lower = [e.lower() for e in found_emails]
        
        # Check against expected
        matches = [e for e in expected_addresses if e in found_emails_lower]
        
        if len(matches) == len(expected_addresses):
            score += 40
            feedback_parts.append(f"All {len(expected_addresses)} expected email addresses extracted perfectly")
        elif len(matches) > 0:
            score += len(matches) * 10
            feedback_parts.append(f"Extracted {len(matches)}/{len(expected_addresses)} expected addresses")
        else:
            feedback_parts.append("Contacts file does not contain the expected failed email addresses")
    else:
        feedback_parts.append("Contacts text file (~/Desktop/bounced_contacts.txt) was not created")

    # ================================================================
    # CRITERION 2: Thunderbird Folder Checks (30 points)
    # ================================================================
    # We use the generic copy_from_env to pull the mbox files
    temp_bounces = tempfile.NamedTemporaryFile(delete=False)
    temp_inbox = tempfile.NamedTemporaryFile(delete=False)
    
    bounces_mbox_exists = False
    try:
        copy_from_env("/home/ga/.thunderbird/default-release/Mail/Local Folders/Bounces", temp_bounces.name)
        if os.path.getsize(temp_bounces.name) > 0:
            bounces_mbox_exists = True
    except:
        pass

    try:
        copy_from_env("/home/ga/.thunderbird/default-release/Mail/Local Folders/Inbox", temp_inbox.name)
    except:
        pass

    if bounces_mbox_exists:
        score += 10
        feedback_parts.append("'Bounces' folder created successfully")
        
        bounces_count = count_bounces_in_mbox(temp_bounces.name, bounce_patterns)
        if bounces_count == len(bounce_patterns):
            score += 20
            feedback_parts.append(f"All {bounces_count} NDR emails moved to 'Bounces' folder")
        elif bounces_count > 0:
            score += bounces_count * 5
            feedback_parts.append(f"Only {bounces_count} NDR emails moved to 'Bounces' folder")
        else:
            feedback_parts.append("No NDR emails found in the 'Bounces' folder")
    else:
        feedback_parts.append("'Bounces' folder was not created in Thunderbird")
        
    # Check Inbox to ensure they were removed (moved, not copied)
    inbox_count = count_bounces_in_mbox(temp_inbox.name, bounce_patterns)
    if inbox_count == 0 and bounces_mbox_exists:
        score += 20
        feedback_parts.append("Inbox successfully cleaned of NDR emails")
    elif inbox_count > 0:
        feedback_parts.append(f"{inbox_count} NDR emails still remain in the Inbox")
        
    # Cleanup temp mbox files
    if os.path.exists(temp_bounces.name): os.unlink(temp_bounces.name)
    if os.path.exists(temp_inbox.name): os.unlink(temp_inbox.name)

    # ================================================================
    # CRITERION 3: VLM Trajectory Verification
    # ================================================================
    vlm_prompt = """You are verifying an agent's desktop automation trajectory.
    
The agent was tasked with:
1. Reading bounce emails in Thunderbird.
2. Opening a text editor to write down the failed email addresses.
3. Creating a 'Bounces' folder in Thunderbird and moving the emails there.

Look at these trajectory screenshots. Does the sequence show the agent interacting with a text editor (like gedit/nano/mousepad) and Thunderbird?

Respond with JSON:
{
    "text_editor_used": true/false,
    "thunderbird_used": true/false,
    "emails_selected_or_moved": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""
    frames = sample_trajectory_frames(traj, n=4)
    if frames:
        vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
        if vlm_result and vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("text_editor_used") and parsed.get("thunderbird_used"):
                feedback_parts.append("VLM confirmed realistic workflow (GUI text editor and Thunderbird used)")
            else:
                feedback_parts.append(f"VLM Note: {parsed.get('reasoning', 'Workflow not fully observed')}")

    # Determine pass/fail
    passed = score >= 80 and file_created_during_task and bounces_mbox_exists
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }