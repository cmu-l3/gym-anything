#!/usr/bin/env python3
"""
Verifier for Subway Surfers score_1000_points task.

Checks if the player achieved at least 1000 points by:
1. Using copy_from_env to get UI dump from the device
2. Parsing for score-related text fields
3. Extracting numeric scores and comparing to target

The score can appear in various UI elements:
- During gameplay: top of screen score counter
- Game over screen: final score display
- High score display
"""

import re
import tempfile
import os
from pathlib import Path
from typing import Dict, Any, List, Tuple, Optional


def extract_scores_from_ui(ui_xml: str) -> List[Tuple[int, str]]:
    """Extract potential score values from UI dump XML.

    Returns:
        List of tuples (score_value, context_string) sorted by value descending
    """
    scores = []

    # Pattern 1: Direct text attributes with numbers
    # Look for text attributes containing numbers
    text_matches = re.findall(r'text="([^"]*)"', ui_xml)

    for text in text_matches:
        # Skip empty or very short texts
        if len(text) < 1:
            continue

        # Extract numbers from the text
        # Handle formats like "1234", "1,234", "Score: 1234", "1234 pts"
        numbers = re.findall(r'[\d,]+', text)
        for num_str in numbers:
            try:
                # Remove commas and convert to int
                num = int(num_str.replace(',', ''))
                if num >= 100:  # Scores below 100 are likely not game scores
                    scores.append((num, text))
            except ValueError:
                continue

    # Pattern 2: Content descriptions
    content_desc_matches = re.findall(r'content-desc="([^"]*)"', ui_xml)
    for desc in content_desc_matches:
        numbers = re.findall(r'[\d,]+', desc)
        for num_str in numbers:
            try:
                num = int(num_str.replace(',', ''))
                if num >= 100:
                    scores.append((num, f"content-desc: {desc}"))
            except ValueError:
                continue

    # Pattern 3: Look for score-related resource IDs with nearby text
    score_patterns = [
        r'resource-id="[^"]*score[^"]*"[^>]*text="([^"]*)"',
        r'resource-id="[^"]*point[^"]*"[^>]*text="([^"]*)"',
        r'resource-id="[^"]*result[^"]*"[^>]*text="([^"]*)"',
    ]

    for pattern in score_patterns:
        matches = re.findall(pattern, ui_xml, re.IGNORECASE)
        for match in matches:
            numbers = re.findall(r'[\d,]+', match)
            for num_str in numbers:
                try:
                    num = int(num_str.replace(',', ''))
                    if num >= 10:  # Lower threshold for explicitly labeled score fields
                        scores.append((num, f"score field: {match}"))
                except ValueError:
                    continue

    # Remove duplicates and sort by value descending
    unique_scores = list(set(scores))
    unique_scores.sort(key=lambda x: x[0], reverse=True)

    return unique_scores


def check_score(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify the player achieved the target score in Subway Surfers.

    Args:
        traj: Trajectory data with steps, frames, episode_dir, etc.
        env_info: Environment info with copy_from_env, copy_to_env, env_id
        task_info: Task info with task_id and metadata

    Returns:
        dict with keys:
            - passed: bool indicating if verification passed
            - score: int score (0-100)
            - feedback: str describing the result
    """
    # Get target score from task metadata
    metadata = task_info.get('metadata', {})
    target_score = metadata.get('target_score', 1000)

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify"
        }

    # Create temp directory for files
    temp_dir = tempfile.mkdtemp(prefix='subway_surfers_verify_')
    local_ui_dump = os.path.join(temp_dir, "ui_dump.xml")
    local_screenshot = os.path.join(temp_dir, "final_screenshot.png")

    try:
        # Copy the UI dump from the device
        ui_dump_path = "/sdcard/ui_dump.xml"

        try:
            copy_from_env(ui_dump_path, local_ui_dump)
        except Exception as e:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not get UI dump from device: {e}. Make sure the game is running."
            }

        # Also try to get screenshot for debugging
        try:
            copy_from_env("/sdcard/final_screenshot.png", local_screenshot)
        except Exception:
            pass  # Screenshot is optional

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

        # Extract potential scores from UI
        scores = extract_scores_from_ui(ui_xml)

        if not scores:
            # No scores found - check if game is even running
            if "subway" in ui_xml.lower() or "kiloo" in ui_xml.lower():
                return {
                    "passed": False,
                    "score": 10,
                    "feedback": "Subway Surfers is running but no score detected. Game may be at menu or loading."
                }
            return {
                "passed": False,
                "score": 0,
                "feedback": "No score values found in UI. Is Subway Surfers running?"
            }

        # Get the highest score found (most likely the game score)
        highest_score, context = scores[0]

        # Determine success based on target
        if highest_score >= target_score:
            return {
                "passed": True,
                "score": 100,
                "feedback": f"Success! Score {highest_score} >= target {target_score}. Found in: {context}"
            }

        # Partial credit based on how close they got
        percentage = min(100, int((highest_score / target_score) * 100))

        # Give partial credit: 50% weight on reaching the target
        partial_score = int(percentage * 0.5)

        return {
            "passed": False,
            "score": partial_score,
            "feedback": f"Score {highest_score} is below target {target_score}. Progress: {percentage}%. Found in: {context}"
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
            for f in os.listdir(temp_dir):
                os.remove(os.path.join(temp_dir, f))
            os.rmdir(temp_dir)
        except:
            pass


def main():
    """Standalone test mode."""
    print("Verifier for Subway Surfers score_1000_points task")
    print("Target: Achieve score >= 1000 points")
    print()

    # Test with mock UI dump
    test_xml = '''
    <hierarchy>
        <node text="1,234" resource-id="score_display"/>
        <node text="Coins: 50" />
        <node content-desc="Score: 1234"/>
    </hierarchy>
    '''

    scores = extract_scores_from_ui(test_xml)
    print("Test extraction:")
    for score, context in scores:
        print(f"  Score: {score}, Context: {context}")
