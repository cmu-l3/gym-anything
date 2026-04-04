#!/usr/bin/env python3
"""
Verifier for compose email task

Checks that an email was sent to recipient@example.com with subject 'Meeting Tomorrow'
and body containing the word 'agenda'
"""
import sys
import os
from pathlib import Path

# Add utils to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from thunderbird_verification_utils import *


def verify_email_sent(traj, env_info, task_info):
    """
    Verify that an email was sent with correct recipient, subject, and content
    """
    copy_from_env = env_info.get('copy_from_env')

    # Set up verification by copying Sent folder
    success, files, error = setup_thunderbird_verification(
        copy_from_env,
        ["Mail/Local Folders/Sent"],
        username="ga"
    )

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to copy Thunderbird files: {error}"
        }

    # Get the Sent mbox file
    sent_mbox = files.get("Sent")
    if not sent_mbox or not sent_mbox.exists():
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Sent folder not found"
        }

    # Check for email with correct recipient and subject
    email_found = verify_email_sent(
        sent_mbox,
        to_address="recipient@example.com",
        subject_pattern="Meeting Tomorrow"
    )

    if not email_found:
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Email not found with recipient 'recipient@example.com' and subject 'Meeting Tomorrow'"
        }

    # Now verify the email body contains 'agenda'
    email_msg = get_email_by_subject(sent_mbox, "Meeting Tomorrow")

    if not email_msg:
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Could not retrieve email message"
        }

    # Get email body
    body = ""
    if email_msg.is_multipart():
        for part in email_msg.walk():
            if part.get_content_type() == "text/plain":
                body = part.get_payload(decode=True).decode('utf-8', errors='ignore')
                break
    else:
        body = email_msg.get_payload(decode=True).decode('utf-8', errors='ignore')

    # Check if body contains 'agenda'
    has_agenda = 'agenda' in body.lower()

    # Clean up
    cleanup_verification_temp()

    if has_agenda:
        return {
            "passed": True,
            "score": 100,
            "feedback": "Email sent successfully with correct recipient, subject, and content"
        }
    else:
        return {
            "passed": False,
            "score": 50,
            "feedback": "Email sent but body does not contain the word 'agenda'"
        }
