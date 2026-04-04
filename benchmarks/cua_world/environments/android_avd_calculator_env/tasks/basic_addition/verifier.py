#!/usr/bin/env python3
"""
Verifier for Android Calculator basic_addition task.

Checks if the calculator displays the expected result (42) by:
1. Using copy_from_env to get UI dump from the device
2. Searching for the expected result in text fields

Expected: 25 + 17 = 42
"""

import re
import tempfile
import os
from pathlib import Path
from typing import Dict, Any


def check_calculator_result(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify the calculator shows the expected result.

    Args:
        traj: Trajectory data with steps, frames, episode_dir, etc.
        env_info: Environment info with copy_from_env, copy_to_env, env_id
        task_info: Task info with task_id

    Returns:
        dict with keys:
            - passed: bool indicating if verification passed
            - score: int score (0-100)
            - feedback: str describing the result
    """
    expected_result = "42"

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify"
        }

    # Create temp directory for the UI dump
    temp_dir = tempfile.mkdtemp(prefix='android_calc_verify_')
    local_ui_dump = os.path.join(temp_dir, "ui_dump.xml")

    try:
        # Copy the UI dump from the device
        # The UI dump should have been created during the task or by a post_task hook
        # First try the standard location
        ui_dump_path = "/sdcard/ui_dump.xml"

        try:
            copy_from_env(ui_dump_path, local_ui_dump)
        except Exception as e:
            # UI dump might not exist - try to give helpful feedback
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not get UI dump from device: {e}. Make sure the calculator result is displayed."
            }

        # Read the UI dump
        if not os.path.exists(local_ui_dump):
            return {
                "passed": False,
                "score": 0,
                "feedback": "UI dump file not found on device"
            }

        with open(local_ui_dump, 'r', encoding='utf-8', errors='ignore') as f:
            ui_xml = f.read()

        if not ui_xml or len(ui_xml) < 100:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"UI dump is empty or too small (length: {len(ui_xml) if ui_xml else 0})"
            }

        # Search for the expected result in various UI attributes
        # Calculator apps typically show result in text attribute
        patterns = [
            # Exact match
            rf'text="{expected_result}"',
            rf'text="= {expected_result}"',
            rf'text="{expected_result}.0"',
            rf'text="={expected_result}"',
            # With spaces
            rf'text="\s*{expected_result}\s*"',
            # Content description
            rf'content-desc="{expected_result}"',
            rf'content-desc=".*{expected_result}.*"',
            # Resource ID patterns for calculator result display
            rf'resource-id=".*result.*"[^>]*text="[^"]*{expected_result}[^"]*"',
            rf'resource-id=".*formula.*"[^>]*text="[^"]*{expected_result}[^"]*"',
        ]

        for pattern in patterns:
            if re.search(pattern, ui_xml, re.IGNORECASE):
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": f"Calculator correctly displays result: {expected_result}"
                }

        # Try to find any numbers that might be displayed
        # Look for text attributes containing numbers
        numbers_found = re.findall(r'text="([0-9.=+\-*/×÷\s]+)"', ui_xml)

        # Check if any of the found numbers contain our expected result
        for num_str in numbers_found:
            clean_str = num_str.replace(" ", "").replace("×", "*").replace("÷", "/")
            if expected_result in clean_str:
                return {
                    "passed": True,
                    "score": 100,
                    "feedback": f"Found expected result {expected_result} in display: {num_str}"
                }

        # Partial credit if we see the calculation in progress
        if "6" in str(numbers_found) and "7" in str(numbers_found):
            return {
                "passed": False,
                "score": 25,
                "feedback": f"Found 6 and 7 but not the result 42. Numbers found: {numbers_found[:5]}"
            }

        return {
            "passed": False,
            "score": 0,
            "feedback": f"Expected result '{expected_result}' not found. Numbers found: {numbers_found[:10] if numbers_found else 'none'}"
        }

    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        # Cleanup temp directory
        try:
            if os.path.exists(local_ui_dump):
                os.remove(local_ui_dump)
            os.rmdir(temp_dir)
        except:
            pass


def main():
    """Standalone test mode."""
    print("Verifier for Android Calculator basic_multiplication task")
    print("Expected result: 42 (from 6 × 7)")
    print("Run this through gym-anything framework for actual verification")
