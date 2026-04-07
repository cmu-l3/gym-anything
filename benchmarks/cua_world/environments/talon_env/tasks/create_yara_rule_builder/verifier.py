#!/usr/bin/env python3
"""
Verifier for Create Voice-Controlled YARA Rule Builder task.

VERIFICATION STRATEGY:
1. File Creation (10 pts)
2. Python Syntax & Action Class Integrity (20 pts)
3. Talon Syntax & Voice Command Mapping (15 pts) - Statically parsed from the .talon file
4. String Manipulation via Action Class (15 pts) - Assessed dynamically
5. State Management via Action Class (15 pts) - Assessed dynamically
6. Export Formatting Verification (25 pts) - Assessed via generated .yar file
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_yara_rule_builder(traj, env_info, task_info):
    """
    Main verification logic using the exported task_result.json.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Safely retrieve JSON payload from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Directory and Files (10 points)
    if result.get("files_exist"):
        score += 10
        feedback_parts.append("✅ Files created successfully")
    else:
        feedback_parts.append("❌ yara_builder.py or yara_builder.talon missing in target directory")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Python Syntax & Action Class (20 points)
    if result.get("python_syntax_ok"):
        score += 10
        feedback_parts.append("✅ Python syntax valid")
    else:
        feedback_parts.append(f"❌ Python syntax error: {result.get('error')}")

    if result.get("actions_defined"):
        score += 10
        feedback_parts.append("✅ Action class correctly defined")
    else:
        feedback_parts.append(f"❌ Missing required action methods. {result.get('error')}")

    # 3. Talon Voice Commands (15 points)
    talon_content = result.get("talon_file_content", "").lower()
    commands_found = 0
    required_commands = [
        "yara rule", "yara meta", "yara text", 
        "yara hex", "yara condition", "yara export rule"
    ]
    
    for cmd in required_commands:
        if cmd in talon_content:
            commands_found += 1
            
    cmd_score = int((commands_found / 6.0) * 15)
    score += cmd_score
    if commands_found == 6:
        feedback_parts.append("✅ Talon voice commands defined")
    else:
        feedback_parts.append(f"⚠️ Partial Talon voice commands ({commands_found}/6)")

    # 4. Logic & Format Verification via Execution Mock (55 points)
    if result.get("string_manipulation"):
        score += 15
        feedback_parts.append("✅ String manipulation correct (spaces converted to underscores)")
    else:
        feedback_parts.append("❌ String manipulation missing (variables contain spaces)")

    if result.get("state_managed"):
        score += 15
        feedback_parts.append("✅ Stateful tracking accumulated elements correctly")
    else:
        feedback_parts.append("❌ State management failed to preserve multiple properties")

    if result.get("export_formatting"):
        score += 25
        feedback_parts.append("✅ Export generated valid YARA syntax")
    else:
        feedback_parts.append("❌ Exported .yar formatting incorrect or missing")

    # Final logic calculations
    # Must achieve at least a 75 and successfully execute the primary YARA structure
    passed = score >= 75 and result.get("export_formatting")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }