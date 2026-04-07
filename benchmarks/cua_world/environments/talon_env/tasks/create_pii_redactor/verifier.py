#!/usr/bin/env python3
"""
Verifier for create_pii_redactor task in Talon.
Validates file structure, Talon list/command syntax, and dynamically evaluates
the Python code using a mock Talon environment to verify regex scrubbing accuracy.
"""

import sys
import os
import re
import json
import tempfile
import types
import importlib.util
import logging
from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def setup_mock_talon():
    """Sets up a sandboxed mock of the Talon API so agent code can be imported."""
    mock_talon = types.ModuleType('talon')
    
    class MockModule:
        def __init__(self):
            self.list = {}
        def action_class(self, cls):
            # Expose methods so we can test them easily
            for name, method in cls.__dict__.items():
                if not name.startswith('_'):
                    globals()[f"_mocked_{name}"] = method
            return cls

    mock_talon.Module = MockModule
    mock_talon.Context = type('Context', (), {'matches': '', 'action_class': lambda self, x: lambda cls: cls})
    mock_talon.actions = type('actions', (), {'edit': type('edit', (), {'paste': lambda: None})})
    mock_talon.clip = type('clip', (), {'text': lambda: "clipboard_content", 'set_text': lambda x: None})
    
    sys.modules['talon'] = mock_talon

def verify_create_pii_redactor(traj, env_info, task_info):
    """
    Verify the PII Redactor files and execution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Extract metadata test strings
    metadata = task_info.get('metadata', {})
    test_strings = metadata.get('test_strings', {
        "email": "Contact me at test.user@example.com today.",
        "phone": "Call 555-123-4567 now.",
        "ssn": "My SSN is 123-45-6789."
    })

    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch the main result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        copy_from_env("C:\\tmp\\task_result.json", result_json_path)
        
        with open(result_json_path, 'r') as f:
            result = json.load(f)
            
        # File Structure evaluation (10 points)
        if result.get('dir_exists') and result.get('list_exists') and result.get('talon_exists') and result.get('py_exists'):
            score += 10
            feedback_parts.append("All required files created.")
        else:
            feedback_parts.append("Missing one or more required files.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        # Anti-gaming evaluation
        if not result.get('py_modified_during_task'):
            feedback_parts.append("Python file was not modified during the task window (Anti-Gaming Trigger).")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # Fetch the individual agent files
        list_file = os.path.join(temp_dir, "redact_types.talon-list.txt")
        talon_file = os.path.join(temp_dir, "pii_redactor.talon.txt")
        py_file = os.path.join(temp_dir, "pii_redactor.py.txt")
        
        copy_from_env("C:\\tmp\\redact_types.talon-list.txt", list_file)
        copy_from_env("C:\\tmp\\pii_redactor.talon.txt", talon_file)
        copy_from_env("C:\\tmp\\pii_redactor.py.txt", py_file)

        # 2. List Declaration evaluation (10 points)
        with open(list_file, 'r', encoding='utf-8') as f:
            list_content = f.read().lower()
            
        has_header = "list: user.redact_types" in list_content
        has_email = re.search(r"emails\s*:\s*email", list_content)
        has_phone = re.search(r"phones\s*:\s*phone", list_content)
        has_ssn = re.search(r"socials\s*:\s*ssn", list_content)
        
        if has_header and has_email and has_phone and has_ssn:
            score += 10
            feedback_parts.append("Talon list syntax and mappings correct.")
        else:
            feedback_parts.append("Talon list file missing correct header or mappings.")

        # 3. Command Syntax evaluation (15 points)
        with open(talon_file, 'r', encoding='utf-8') as f:
            talon_content = f.read().lower()
            
        has_capture = "{user.redact_types}" in talon_content or "<user.redact_types>" in talon_content
        has_action_call = "user.redact_clipboard(" in talon_content or "redact_clipboard(" in talon_content
        
        if has_capture and has_action_call:
            score += 15
            feedback_parts.append("Talon command syntax correct.")
        else:
            feedback_parts.append("Talon command syntax missing capture or action call.")

        # 4. Clipboard logic inspection (20 points)
        with open(py_file, 'r', encoding='utf-8') as f:
            py_content = f.read()
            
        has_read = "clip.text()" in py_content
        has_write = "clip.set_text(" in py_content
        has_paste = "actions.edit.paste()" in py_content or "key(ctrl-v)" in py_content
        
        if has_read and has_write and has_paste:
            score += 20
            feedback_parts.append("Clipboard flow APIs implemented safely.")
        else:
            feedback_parts.append("Missing correct Talon clipboard APIs.")

        # 5. Regex Logic dynamically via mocked environment (45 points total)
        setup_mock_talon()
        
        try:
            # Dynamically import the agent's python file
            spec = importlib.util.spec_from_file_location("agent_pii_redactor", py_file)
            agent_module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(agent_module)
            
            # Locate redact_text function
            redact_func = None
            if hasattr(agent_module, 'redact_text'):
                redact_func = getattr(agent_module, 'redact_text')
            elif '_mocked_redact_text' in globals():
                redact_func = globals()['_mocked_redact_text']
            else:
                # Search classes
                for item_name in dir(agent_module):
                    item = getattr(agent_module, item_name)
                    if isinstance(item, type) and hasattr(item, 'redact_text'):
                        raw_func = getattr(item, 'redact_text')
                        if hasattr(raw_func, '__get__'):
                            redact_func = raw_func.__get__(item())
                            
            if redact_func:
                regex_passes = 0
                
                # Check email (15 points)
                out_email = redact_func(test_strings['email'], "email")
                if out_email and "test.user@example.com" not in out_email and "[EMAIL REDACTED]" in out_email:
                    score += 15
                    regex_passes += 1
                    feedback_parts.append("Email regex correct.")
                    
                # Check phone (15 points)
                out_phone = redact_func(test_strings['phone'], "phone")
                if out_phone and "555-123-4567" not in out_phone and "[PHONE REDACTED]" in out_phone:
                    score += 15
                    regex_passes += 1
                    feedback_parts.append("Phone regex correct.")
                    
                # Check SSN (15 points)
                out_ssn = redact_func(test_strings['ssn'], "ssn")
                if out_ssn and "123-45-6789" not in out_ssn and "[SSN REDACTED]" in out_ssn:
                    score += 15
                    regex_passes += 1
                    feedback_parts.append("SSN regex correct.")
                    
                if regex_passes == 0:
                    feedback_parts.append("Regex logic failed to redact properly.")
                    
            else:
                feedback_parts.append("Function 'redact_text' not found in module.")
                
        except Exception as e:
            logger.error(f"Error evaluating python logic: {str(e)}")
            feedback_parts.append(f"Python execution error: {str(e)[:50]}")
            
    finally:
        # Cleanup mock and temp files
        if 'talon' in sys.modules:
            del sys.modules['talon']
        
        for file in os.listdir(temp_dir):
            os.remove(os.path.join(temp_dir, file))
        os.rmdir(temp_dir)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }