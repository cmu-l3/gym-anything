#!/usr/bin/env python3
"""Verifier for take_gui_screenshot task.
Programmatically checks if a new screenshot was created in the Screenshots/ subfolder.
"""
import os
import glob

def verify_take_gui_screenshot(traj, env_info, task_info):
    """Check if a new screenshot file was created in ~/Documents/OpenBCI_GUI/Screenshots/."""
    screenshots_dir = os.path.expanduser('~/Documents/OpenBCI_GUI/Screenshots/')

    # Find screenshot files - OpenBCI saves as .jpg in Expert Mode
    screenshot_files = glob.glob(os.path.join(screenshots_dir, 'OpenBCI-*.jpg'))
    screenshot_files += glob.glob(os.path.join(screenshots_dir, 'OpenBCI-*.png'))

    # Read the before-count if available
    try:
        with open('/tmp/openbci_screenshot_count_before.txt', 'r') as f:
            before_count = int(f.read().strip())
    except Exception:
        before_count = 0

    current_count = len(set(screenshot_files))

    if current_count > before_count:
        return {
            "passed": True,
            "score": 100,
            "feedback": f"Screenshot taken successfully. Found {current_count} screenshot file(s) in Screenshots folder."
        }
    else:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"No new screenshot found in Screenshots/ folder. Count before: {before_count}, after: {current_count}. "
                       f"Make sure Expert Mode is enabled and press 'm' key while the GUI has keyboard focus."
        }
