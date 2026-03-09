#!/usr/bin/env python3
"""
Verifier for add contact task

Checks that a contact with email 'john.doe@example.com' and name 'John Doe' was added
"""
import sys
import os
from pathlib import Path

# Add utils to path
# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from thunderbird_verification_utils import *


def verify_contact_added(traj, env_info, task_info):
    """
    Verify that a contact was added to the address book
    """
    copy_from_env = env_info.get('copy_from_env')

    # Set up verification by copying address book
    success, files, error = setup_thunderbird_verification(
        copy_from_env,
        ["abook.sqlite"],
        username="ga"
    )

    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to copy address book: {error}"
        }

    # Get the address book file
    abook_path = files.get("abook.sqlite")
    if not abook_path or not abook_path.exists():
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Address book database not found"
        }

    # Verify contact exists by email
    contact_exists_email = verify_contact_exists(
        abook_path,
        email="john.doe@example.com"
    )

    # Verify contact exists by name
    contact_exists_name = verify_contact_exists(
        abook_path,
        name="John Doe"
    )

    # Clean up
    cleanup_verification_temp()

    if contact_exists_email and contact_exists_name:
        return {
            "passed": True,
            "score": 100,
            "feedback": "Contact 'John Doe <john.doe@example.com>' added successfully"
        }
    elif contact_exists_email:
        return {
            "passed": False,
            "score": 75,
            "feedback": "Contact with email 'john.doe@example.com' found, but name may not be 'John Doe'"
        }
    elif contact_exists_name:
        return {
            "passed": False,
            "score": 75,
            "feedback": "Contact with name 'John Doe' found, but email may not be 'john.doe@example.com'"
        }
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Contact not found in address book"
        }
