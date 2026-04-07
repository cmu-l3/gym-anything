#!/usr/bin/env python3
"""
Verifier for build_icd10_voice_assistant task.

Verification Strategy:
1. Static check: Validates file existence, file modification timestamps.
2. Syntax check: Uses AST and Regex to confirm .talon file structure and log errors.
3. VLM Trajectory: Verifies the agent used an editor to write the code.
4. Dynamic Eval (Primary): Mocks the `talon` Python API environment, dynamically executes
   the agent's `icd_assistant.py` code, and fires hidden test queries to verify the 
   search algorithm and `actions.insert` payload accuracy.
"""

import json
import os
import sys
import types
import builtins
import tempfile
import re
import logging

from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Mocked actions class to intercept Talon API calls
class MockActions:
    def __init__(self):
        self.inserted_text = []
        # Create a mock user namespace
        self.user = types.SimpleNamespace()

    def insert(self, text):
        self.inserted_text.append(str(text))

# Dummy CSV content for host-side execution
DUMMY_CSV = """Code,Description
A00.0,Cholera due to Vibrio cholerae 01 biovar cholerae
A00.1,Cholera due to Vibrio cholerae 01 biovar eltor
A00.9,Cholera unspecified
E11.9,Type 2 diabetes mellitus without complications
E11.00,Type 2 diabetes mellitus with hyperosmolarity without nonketotic hyperglycemic-hyperosmolar coma (NKHHC)
R51.9,Headache unspecified
J01.90,Acute sinusitis unspecified
J01.00,Acute maxillary sinusitis unspecified
I10,Essential (primary) hypertension
J45.909,Unspecified asthma uncomplicated
J18.9,Pneumonia unspecified organism
K35.80,Unspecified acute appendicitis
M54.5,Low back pain
F41.1,Generalized anxiety disorder"""

def verify_icd10_voice_assistant(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Fetch result JSON from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    task_start = result.get('task_start', 0)
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_mtime = result.get('py_mtime', 0)
    talon_mtime = result.get('talon_mtime', 0)

    # 1. File Structure and Anti-Gaming
    if py_exists and talon_exists:
        if py_mtime >= task_start and talon_mtime >= task_start:
            score += 10
            feedback_parts.append("Files created successfully during task")
        else:
            feedback_parts.append("Files exist but were created before task started (gaming detected)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("Missing required files (icd_assistant.py or icd_assistant.talon)")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Log Analysis & Talon Syntax
    talon_content = result.get('talon_content', '')
    if re.search(r'diagnosis\s+search\s+<user\.text>', talon_content) and re.search(r'diagnosis\s+insert\s+<user\.text>', talon_content):
        score += 10
        feedback_parts.append(".talon file syntax is correct")
    else:
        feedback_parts.append(".talon file is missing required command syntax")

    talon_log = result.get('talon_log', '')
    if "SyntaxError" not in talon_log and "Exception" not in talon_log[-500:]:
        score += 10
        feedback_parts.append("No critical Python syntax errors in log")

    # 3. VLM Verification - Trajectory Frame Analysis
    vlm_score = 0
    try:
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Did the agent use a text editor (like Notepad, VSCode, etc.) to write or edit code files at any point? 
Look for editor windows containing Python or Talon syntax.
Respond in JSON format: {"used_editor": true/false, "confidence": "high/medium/low"}"""
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                if parsed.get("used_editor", False):
                    score += 15
                    vlm_score = 15
                    feedback_parts.append("VLM confirms editor was used")
                else:
                    feedback_parts.append("VLM did not detect editor usage")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")

    # 4. Dynamic Execution & Simulation
    agent_code = result.get('py_content', '')
    eval_score = 0
    
    # Create the host-side temporary CSV
    host_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv', mode='w', encoding='utf-8')
    try:
        host_csv.write(DUMMY_CSV)
        host_csv.close()

        # Mock the talon module
        talon_mock = types.ModuleType('talon')
        class MockModule:
            def __init__(self):
                self.action_class_obj = None
            def action_class(self, cls):
                self.action_class_obj = cls
                return cls
        
        talon_mock.Module = MockModule
        actions_mock = MockActions()
        talon_mock.actions = actions_mock
        talon_mock.app = types.SimpleNamespace(notify=lambda title, body: None)

        # Inject into sys.modules
        sys.modules['talon'] = talon_mock

        # Intercept built-in open() to redirect to our dummy CSV regardless of the path the agent hardcoded
        original_open = builtins.open
        def mocked_open(file, *args, **kwargs):
            if isinstance(file, str) and 'icd10_codes.csv' in file:
                return original_open(host_csv.name, *args, **kwargs)
            return original_open(file, *args, **kwargs)
        builtins.open = mocked_open

        # Execute agent code in restricted globals
        exec_globals = {}
        exec_success = False
        try:
            exec(agent_code, exec_globals)
            exec_success = True
        except Exception as e:
            feedback_parts.append(f"Python Execution Error: {e}")
        
        # Restore open() immediately
        builtins.open = original_open

        if exec_success:
            # Find the registered module instance
            mod_instance = None
            for var in exec_globals.values():
                if isinstance(var, MockModule):
                    mod_instance = var
                    break
            
            if mod_instance and mod_instance.action_class_obj:
                score += 10  # Correct Talon module setup
                
                # Instantiate the agent's action class
                ActionClass = mod_instance.action_class_obj
                agent_actions = ActionClass()
                
                # Test the logic with 3 hidden queries
                tests = [
                    ("cholera vibrio biovar", "A00.0"),
                    ("type 2 diabetes without complications", "E11.9"),
                    ("headache unspecified", "R51.9")
                ]
                
                tests_passed = 0
                for query, expected_code in tests:
                    actions_mock.inserted_text = []  # Reset mock
                    try:
                        agent_actions.icd_insert(query)
                        if any(expected_code in text for text in actions_mock.inserted_text):
                            tests_passed += 1
                    except Exception as e:
                        logger.warning(f"Error executing icd_insert for '{query}': {e}")
                
                if tests_passed == 3:
                    eval_score += 45
                    score += 45
                    feedback_parts.append("All dynamic insertion tests passed (3/3)")
                elif tests_passed > 0:
                    eval_score += tests_passed * 15
                    score += tests_passed * 15
                    feedback_parts.append(f"Some insertion tests passed ({tests_passed}/3)")
                else:
                    feedback_parts.append("Dynamic tests failed: did not insert expected ICD-10 codes")
            else:
                feedback_parts.append("Could not find @mod.action_class in agent code")

    except Exception as e:
        feedback_parts.append(f"Verification framework error: {e}")
    finally:
        if os.path.exists(host_csv.name):
            os.unlink(host_csv.name)
        if 'talon' in sys.modules:
            del sys.modules['talon']
        # Double check restoration
        builtins.open = original_open

    # Final logic
    key_criteria_met = (py_exists and talon_exists and eval_score >= 15 and vlm_score > 0)
    passed = score >= 70 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }