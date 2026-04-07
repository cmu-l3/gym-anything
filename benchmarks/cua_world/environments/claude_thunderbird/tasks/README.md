# Thunderbird Tasks

This directory contains task definitions for the Thunderbird environment.

## Task Structure

Each task should be in its own subdirectory with the following files:

```
task_name/
├── task.json           # Task specification (required)
├── setup_task.sh       # Pre-task setup script
├── export_result.sh    # Post-task export script (optional)
├── verifier.py         # Verification logic (required)
├── assets/             # Optional task-specific files
└── README.md           # Task documentation (optional)
```

## Example Task: Compose Email

### task.json

```json
{
  "id": "compose_email@1",
  "version": "1.0",
  "env_id": "claude.thunderbird_env@0.1",
  "description": "Compose and send an email with specific subject and recipient",
  "difficulty": "easy",
  "init": {
    "timeout_sec": 120,
    "max_steps": 15,
    "reward_type": "sparse"
  },
  "hooks": {
    "pre_task": "/workspace/tasks/compose_email/setup_task.sh",
    "post_task": "/workspace/tasks/compose_email/export_result.sh"
  },
  "success": {
    "mode": "program",
    "spec": {
      "program": "verifier.py::verify_email_sent"
    }
  }
}
```

### setup_task.sh

```bash
#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Compose Email Task ==="

# Wait for Thunderbird to be ready
if ! wait_for_thunderbird_ready 30; then
    echo "ERROR: Thunderbird not ready"
    exit 1
fi

# Click center of desktop to focus
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Thunderbird window
echo "Focusing Thunderbird window..."
wid=$(get_thunderbird_window_id)
if [ -n "$wid" ]; then
    focus_window "$wid"
    safe_xdotool ga :1 key F11  # Maximize
    sleep 0.5
fi

echo "=== Task Setup Complete ==="
echo "📧 Instructions:"
echo "  1. Click 'Write' or press Ctrl+N to compose new email"
echo "  2. Enter recipient: test@example.com"
echo "  3. Enter subject: Test Email from Agent"
echo "  4. Write email body"
echo "  5. Send with Ctrl+Enter or click Send button"
```

### export_result.sh

```bash
#!/bin/bash
set -euo pipefail

echo "=== Exporting Email Results ==="

# Give Thunderbird time to save the sent email
sleep 2

# Export the Sent folder for verification
EXPORT_DIR="/home/ga/Documents/results"
sudo -u ga mkdir -p "$EXPORT_DIR"

# Copy Sent mbox file
TB_PROFILE="/home/ga/.thunderbird/default"
if [ -f "$TB_PROFILE/Mail/Local Folders/Sent" ]; then
    cp "$TB_PROFILE/Mail/Local Folders/Sent" "$EXPORT_DIR/Sent.mbox"
    echo "✅ Exported Sent folder"
fi

echo "=== Export Complete ==="
```

### verifier.py

```python
#!/usr/bin/env python3
"""
Verifier for compose email task
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
    Verify that an email was sent to test@example.com with subject 'Test Email from Agent'
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

    # Verify email was sent
    sent_mbox = files.get("Sent")
    if not sent_mbox:
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": "Sent folder not found"
        }

    # Check for email with correct recipient and subject
    email_sent = verify_email_sent(
        sent_mbox,
        to_address="test@example.com",
        subject_pattern="Test Email from Agent"
    )

    # Clean up
    cleanup_verification_temp()

    if email_sent:
        return {
            "passed": True,
            "score": 100,
            "feedback": "Email sent successfully to test@example.com"
        }
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Email not found in Sent folder or incorrect recipient/subject"
        }
```

## Task Categories

### Email Operations
- Compose and send email
- Reply to email
- Forward email
- Add attachment
- Delete email
- Mark as read/unread

### Organization
- Create folder
- Move emails to folder
- Add tags to emails
- Search emails
- Create email filter

### Calendar
- Create event
- Edit event
- Delete event
- Set reminder
- Create recurring event

### Contacts
- Add contact
- Edit contact
- Delete contact
- Create contact group
- Import contacts

### Advanced
- Configure IMAP account
- Set up email signature
- Create template
- Export/import emails
- Configure encryption

## Best Practices

1. **Always source task_utils.sh** for common functions
2. **Wait for Thunderbird** before performing actions
3. **Click desktop center** to ensure focus (600, 600)
4. **Focus and maximize window** before task starts
5. **Use verification utilities** for consistent checking
6. **Clean up temp files** after verification
7. **Provide clear feedback** in verifier return values
8. **Handle errors gracefully** with try/except blocks

## Utility Functions Available

From `task_utils.sh`:
- `wait_for_window`
- `wait_for_file`
- `wait_for_process`
- `focus_window`
- `get_thunderbird_window_id`
- `safe_xdotool`
- `wait_for_thunderbird_ready`
- `send_test_email`
- `count_emails_in_folder`
- `check_email_exists`

From `thunderbird_verification_utils.py`:
- `get_thunderbird_profile_dir`
- `setup_thunderbird_verification`
- `cleanup_verification_temp`
- `parse_mbox_file`
- `count_emails_in_mbox`
- `get_email_subjects`
- `verify_email_sent`
- `verify_email_received`
- `read_address_book`
- `verify_contact_exists`
- `get_calendar_events`
- `verify_event_exists`
- `check_email_filter`
- `verify_folder_exists`

## Testing Tasks Locally

```bash
# Test task setup
cd /data/Gym-Anything
python -c "
import gym_anything as ga
env = ga.from_config('examples/claude_thunderbird', task_id='compose_email')
obs = env.reset()
# Interact with environment
env.close()
"
```
