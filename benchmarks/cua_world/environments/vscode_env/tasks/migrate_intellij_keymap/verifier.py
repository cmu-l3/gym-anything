#!/usr/bin/env python3
"""
Verifier for Migrate IntelliJ Keymap task
"""

import sys
import os
import json
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import copy_and_parse_json, cleanup_verification_temp

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_intellij_keymap(traj, env_info, task_info):
    """
    Verify that IntelliJ-style keybindings were configured correctly.
    
    Required keybindings (key -> command):
    1. ctrl+alt+l -> editor.action.formatDocument
    2. ctrl+b -> editor.action.revealDefinition
    3. alt+f7 -> references-view.findReferences
    4. ctrl+alt+o -> editor.action.organizeImports
    5. ctrl+alt+m -> editor.action.refactor
    
    Scoring:
    - 100: All 5 correct
    - 80: 4 correct
    - 60: 3 correct
    - 40: 2 correct
    - 20: 1 correct
    - 0: None correct or invalid JSON
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Define required mappings (keys are case-insensitive, commands are case-sensitive)
    required_mappings = {
        "ctrl+alt+l": "editor.action.formatDocument",
        "ctrl+b": "editor.action.revealDefinition",
        "alt+f7": "references-view.findReferences",
        "ctrl+alt+o": "editor.action.organizeImports",
        "ctrl+alt+m": "editor.action.refactor"
    }
    
    # Try primary location first, then backup
    keybindings_paths = [
        "/tmp/keybindings.json",
        "/home/ga/.config/Code/User/keybindings.json"
    ]
    
    data = None
    error_msg = ""
    
    for keybindings_path in keybindings_paths:
        success, data, error_msg = copy_and_parse_json(keybindings_path, copy_from_env)
        if success:
            logger.info(f"Successfully loaded keybindings from {keybindings_path}")
            break
    
    if not success or data is None:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to read or parse keybindings.json: {error_msg}"
        }
    
    # Validate that data is an array
    if not isinstance(data, list):
        return {
            "passed": False,
            "score": 0,
            "feedback": f"keybindings.json must be an array, got {type(data).__name__}"
        }
    
    # Parse keybindings from the file
    found_mappings = {}
    
    for binding in data:
        if not isinstance(binding, dict):
            continue
        
        key = binding.get("key", "")
        command = binding.get("command", "")
        
        if not key or not command:
            continue
        
        # Normalize key to lowercase for comparison
        key_normalized = key.lower().strip()
        
        # Store if it matches one of our required keys
        if key_normalized in required_mappings:
            found_mappings[key_normalized] = command.strip()
    
    # Count correct mappings
    correct_mappings = []
    incorrect_mappings = []
    missing_mappings = []
    
    for required_key, required_command in required_mappings.items():
        if required_key in found_mappings:
            if found_mappings[required_key] == required_command:
                correct_mappings.append(required_key)
            else:
                incorrect_mappings.append({
                    "key": required_key,
                    "expected": required_command,
                    "found": found_mappings[required_key]
                })
        else:
            missing_mappings.append(required_key)
    
    # Calculate score
    correct_count = len(correct_mappings)
    total_required = len(required_mappings)
    score = int((correct_count / total_required) * 100)
    
    # Determine pass/fail (need at least 3 out of 5 = 60%)
    passed = score >= 60
    
    # Build detailed feedback
    feedback_parts = []
    
    if correct_count == total_required:
        feedback_parts.append(f"✅ All {total_required} keybindings configured correctly")
    elif correct_count > 0:
        feedback_parts.append(f"✅ {correct_count}/{total_required} keybindings correct: {', '.join(correct_mappings)}")
    else:
        feedback_parts.append(f"❌ No correct keybindings found")
    
    if missing_mappings:
        feedback_parts.append(f"❌ Missing keybindings: {', '.join(missing_mappings)}")
    
    if incorrect_mappings:
        for wrong in incorrect_mappings:
            feedback_parts.append(
                f"❌ {wrong['key']}: expected '{wrong['expected']}', got '{wrong['found']}'"
            )
    
    feedback = " | ".join(feedback_parts)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "correct_count": correct_count,
            "total_required": total_required,
            "correct_mappings": correct_mappings,
            "incorrect_mappings": incorrect_mappings,
            "missing_mappings": missing_mappings
        }
    }
