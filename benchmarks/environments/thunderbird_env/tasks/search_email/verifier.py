#!/usr/bin/env python3
"""
Verifier for search email task

Checks that the email with subject 'Welcome to Thunderbird' was found and flagged
"""
import sys
import os
from pathlib import Path

# Add utils to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from thunderbird_verification_utils import *


def verify_email_flagged(traj, env_info, task_info):
    """
    Verify that the email was found and flagged/starred
    """
    copy_from_env = env_info.get('copy_from_env')

    # Set up verification by copying Inbox
    success, files, error = setup_thunderbird_verification(
        copy_from_env,
        ["Mail/Local Folders/Inbox", "Mail/Local Folders/Inbox.msf"],
        username="ga"
    )

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to copy Thunderbird files: {error}"
        }

    # Get the Inbox mbox file
    inbox_mbox = files.get("Inbox")
    if not inbox_mbox or not inbox_mbox.exists():
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Inbox not found"
        }

    # Verify the email exists
    email_msg = get_email_by_subject(inbox_mbox, "Welcome to Thunderbird")

    if not email_msg:
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Email with subject 'Welcome to Thunderbird' not found in Inbox"
        }

    # Check if email is flagged
    # Thunderbird stores flags in X-Mozilla-Status header
    # X-Mozilla-Status: 0001 means flagged
    mozilla_status = email_msg.get('X-Mozilla-Status', '0000')
    mozilla_status2 = email_msg.get('X-Mozilla-Status2', '00000000')

    # Flag is typically stored in X-Mozilla-Status
    # 0x0002 (bit 1) = flagged/starred
    try:
        status_int = int(mozilla_status, 16) if mozilla_status else 0
        is_flagged = bool(status_int & 0x0002)  # Check bit 1
    except:
        is_flagged = False

    # Alternative: check X-Mozilla-Keys header which may contain "Flagged"
    mozilla_keys = email_msg.get('X-Mozilla-Keys', '')
    if 'flagged' in mozilla_keys.lower():
        is_flagged = True

    # Clean up
    cleanup_verification_temp()

    if is_flagged:
        return {
            "passed": True,
            "score": 100,
            "feedback": "Email found and successfully marked as starred/flagged"
        }
    else:
        return {
            "passed": False,
            "score": 50,
            "feedback": "Email found but not marked as starred/flagged. Make sure to star/flag the email after finding it."
        }
