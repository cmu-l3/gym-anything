#!/usr/bin/env python3
"""
Verifier for create_crypto_voice_tool task.

Verification Strategy (Multi-Signal):
1. FILE SYSTEM: Checks that .py and .talon files were created in the correct Talon path.
2. DYNAMIC PYTHON TESTING: Pulls the agent's .py file, safely strips Talon-specific decorators,
   mocks Talon core modules, and executes the code to verify cryptographic output and error handling.
3. STATIC TALON TESTING: Parses the .talon file to ensure the voice commands map correctly to 
   the Python actions and that clipboard chaining was implemented.
4. VLM TRAJECTORY: Validates the agent actively performed work in the editor.
"""

import json
import os
import tempfile
import base64
import hashlib
import logging

from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_agent_python(py_content):
    """Dynamically tests the agent's Python logic by mocking Talon dependencies."""
    # Setup mock Talon namespace
    setup_code = """
class MockApp:
    def __init__(self):
        self.notified = False
    def notify(self, msg):
        self.notified = True

class MockActions:
    def __init__(self):
        self.app = MockApp()
        
actions = MockActions()

class MockModule:
    def action_class(self, cls): 
        return cls

Module = MockModule
"""
    # Strip decorators to prevent instantiation errors on unknown decorators
    clean_code = "\n".join([line for line in py_content.split('\n') if not line.strip().startswith('@')])
    
    exec_globals = {}
    try:
        exec(setup_code + clean_code, exec_globals)
    except Exception as e:
        return {"error": f"Failed to parse/execute python code: {str(e)}"}

    # Helper to find functions dynamically (handles class-based or module-level definitions)
    def call_func(name, val):
        if name in exec_globals and callable(exec_globals[name]):
            return exec_globals[name](val)
        for obj in exec_globals.values():
            if isinstance(obj, type) and hasattr(obj, name):
                return getattr(obj(), name)(val)
        return None

    results = {"error": None, "tests": {}}
    
    try:
        # Test 1: Base64 Encode
        target = "test_string"
        expected = base64.b64encode(target.encode()).decode()
        results["tests"]["b64_encode"] = (call_func("crypto_b64_encode", target) == expected)
        
        # Test 2: Base64 Decode Valid
        results["tests"]["b64_decode_valid"] = (call_func("crypto_b64_decode", expected) == target)
        
        # Test 3: Base64 Decode Invalid (Exception Catching)
        invalid_str = "not_valid_base64!!!"
        returned = call_func("crypto_b64_decode", invalid_str)
        notified = exec_globals['actions'].app.notified if 'actions' in exec_globals else False
        results["tests"]["b64_decode_invalid"] = (returned == invalid_str) and notified
        
        # Test 4: SHA-256
        expected_sha = hashlib.sha256(target.encode()).hexdigest()
        results["tests"]["sha256"] = (call_func("crypto_hash_sha256", target) == expected_sha)
        
        # Test 5: MD5
        expected_md5 = hashlib.md5(target.encode()).hexdigest()
        results["tests"]["md5"] = (call_func("crypto_hash_md5", target) == expected_md5)
        
    except Exception as e:
        results["error"] = f"Runtime error during logic test: {str(e)}"
        
    return results

def test_agent_talon(talon_content):
    """Statically analyzes the agent's Talon file for correct command mapping."""
    content = talon_content.lower()
    
    return {
        "encode_cmd": "crypto base encode" in content and "crypto_b64_encode" in content,
        "decode_cmd": "crypto base decode" in content and "crypto_b64_decode" in content,
        "sha256_cmd": "crypto hash two fifty six" in content and "crypto_hash_sha256" in content,
        "md5_cmd": "crypto hash md five" in content and "crypto_hash_md5" in content,
        "clipboard_used": ("clip.text" in content or "edit.copy" in content) and "insert" in content
    }

def verify_crypto_tool(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback = []

    # 1. READ RESULT JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to fetch JSON export: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # File Existence Check (15 points)
    if result.get('py_exists') and result.get('talon_exists'):
        score += 15
        feedback.append("Both required files created.")
        if result.get('py_created_during_task'):
            feedback.append("Files correctly created during task timeline.")
    else:
        feedback.append("Required files missing from target directory.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # 2. EVALUATE PYTHON LOGIC (40 points)
    temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    py_content = ""
    try:
        copy_from_env("C:\\tmp\\agent_crypto_actions.py", temp_py.name)
        with open(temp_py.name, 'r', encoding='utf-8') as f:
            py_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_py.name):
            os.unlink(temp_py.name)

    py_eval = test_agent_python(py_content)
    
    if py_eval["error"]:
        feedback.append(f"Python execution failed: {py_eval['error']}")
    else:
        pts_per_test = 8
        tests_passed = 0
        for test_name, passed in py_eval["tests"].items():
            if passed:
                score += pts_per_test
                tests_passed += 1
        feedback.append(f"Python dynamic logic: {tests_passed}/5 tests passed.")

    # 3. EVALUATE TALON MAPPING (25 points)
    temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
    talon_content = ""
    try:
        copy_from_env("C:\\tmp\\agent_crypto_actions.talon", temp_talon.name)
        with open(temp_talon.name, 'r', encoding='utf-8') as f:
            talon_content = f.read()
    except Exception:
        pass
    finally:
        if os.path.exists(temp_talon.name):
            os.unlink(temp_talon.name)

    talon_eval = test_agent_talon(talon_content)
    talon_tests_passed = sum(talon_eval.values())
    score += talon_tests_passed * 5
    feedback.append(f"Talon static analysis: {talon_tests_passed}/5 mappings correct.")

    # 4. VLM TRAJECTORY VERIFICATION (20 points)
    # Check if the agent actively wrote code and operated within an editor.
    frames = sample_trajectory_frames(traj, n=4)
    final = get_final_screenshot(traj)
    
    if frames and env_info.get('query_vlm'):
        prompt = """
        Review these screenshots from an AI agent's session.
        Did the agent use a text editor/IDE (like Notepad or VSCode) to write Python and/or Talon code?
        Are there indicators that it was editing crypto/hashing related functions?
        Respond with exactly 'YES' or 'NO'.
        """
        vlm_resp = query_vlm(images=frames + [final] if final else frames, prompt=prompt)
        if vlm_resp and "YES" in str(vlm_resp.get("response", "")).upper():
            score += 20
            feedback.append("VLM verified active trajectory work.")
        else:
            feedback.append("VLM could not verify active editing in trajectory.")

    # Pass Criteria: >= 75 points
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }