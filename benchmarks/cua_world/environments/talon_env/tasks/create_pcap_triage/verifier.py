#!/usr/bin/env python3
"""
Verifier for create_pcap_triage task.
Programmatically evaluates the syntactic validity of the .talon and .talon-list files,
and performs a dynamic isolated execution of the generated Python logic against a dummy dataset.
"""

import json
import os
import sys
import tempfile
import logging
import re
import types
import inspect

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_pcap_triage(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Directory/Files (10 points)
    if result.get("py_file_exists") and result.get("talon_file_exists") and result.get("list_file_exists"):
        score += 10
        feedback.append("All 3 required files exist.")
    else:
        missing = []
        if not result.get("py_file_exists"): missing.append(".py")
        if not result.get("talon_file_exists"): missing.append(".talon")
        if not result.get("list_file_exists"): missing.append(".talon-list")
        feedback.append(f"Missing files: {', '.join(missing)}")

    list_content = result.get("list_content", "").lower()
    py_content = result.get("py_content", "")
    talon_content = result.get("talon_content", "")

    # 2. Check List Mapping Syntax (15 points)
    if "list: user.network_protocol" in list_content or "list: user.network_protocol" in list_content.replace(' ', ''):
        expected_mappings = [
            ("secure shell", "22"),
            ("web", "80"),
            ("secure web", "443"),
            ("remote desktop", "3389")
        ]
        mappings_found = 0
        for phrase, port in expected_mappings:
            if phrase in list_content and port in list_content:
                mappings_found += 1
        
        if mappings_found >= len(expected_mappings):
            score += 15
            feedback.append("List mappings are correct.")
        elif mappings_found > 0:
            score += 5
            feedback.append("Partial list mappings found.")
        else:
            feedback.append("Failed to find proper port mappings in list.")

    # 3. Check Capture Definition (15 points)
    if '@mod.capture' in py_content and 'user.network_protocol' in py_content:
        score += 15
        feedback.append("Capture definition is present in Python file.")
    else:
        feedback.append("Capture definition missing or incorrect in Python file.")

    # 4. Check Command Binding (20 points)
    if 'block protocol' in talon_content and 'user.network_protocol' in talon_content:
        if 'user.generate_blocklist' in talon_content:
            score += 20
            feedback.append("Talon voice command rule successfully bound to action.")
        else:
            score += 10
            feedback.append("Talon rule exists but action call missing/incorrect.")
    else:
        feedback.append("Talon voice command rule missing.")

    # 5. Data Parsing Logic & Data Extraction (40 points)
    # We will test the generated python script dynamically against an unseen dummy dataset
    logic_score, logic_feedback = test_python_logic_dynamically(py_content)
    score += logic_score
    feedback.append(logic_feedback)

    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }

def test_python_logic_dynamically(py_content):
    if not py_content:
        return 0, "No Python content to test."

    # Setup dummy host files for execution to isolate the agent logic
    test_csv = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.csv', encoding='utf-8')
    test_csv.write("Timestamp,SourceIP,DestinationIP,DestinationPort,Protocol,Bytes\n")
    test_csv.write("2023-10-01T10:00:00Z,10.0.0.1,10.0.0.5,80,TCP,500\n")
    test_csv.write("2023-10-01T10:05:00Z,10.0.0.2,10.0.0.5,3389,TCP,1500\n")
    test_csv.write("2023-10-01T10:10:00Z,10.0.0.2,10.0.0.5,3389,TCP,800\n") # Duplicate IP for uniqueness check
    test_csv.write("2023-10-01T10:15:00Z,10.0.0.3,10.0.0.6,3389,TCP,2000\n")
    test_csv.close()

    test_out = tempfile.NamedTemporaryFile(delete=False, mode='w', suffix='.txt', encoding='utf-8')
    test_out.close()

    # Patch paths to route agent logic to our dummy host files instead of container paths
    # Match various ways path could be formatted in code (raw string, forward slashes, escaped backslashes)
    path_pattern_csv = re.compile(r'C:\\\\workspace\\\\data\\\\network_traffic\.csv|C:/workspace/data/network_traffic\.csv|C:\\workspace\\data\\network_traffic\.csv', re.IGNORECASE)
    py_content = path_pattern_csv.sub(test_csv.name.replace('\\', '/'), py_content)

    path_pattern_txt = re.compile(r'C:\\\\workspace\\\\data\\\\firewall_rules\.txt|C:/workspace/data/firewall_rules\.txt|C:\\workspace\\data\\firewall_rules\.txt', re.IGNORECASE)
    py_content = path_pattern_txt.sub(test_out.name.replace('\\', '/'), py_content)

    # Mock Talon API to permit execution without Talon engine
    dummy_talon = types.ModuleType('talon')
    class DummyModule:
        def capture(self, *args, **kwargs):
            return lambda f: f
        def action_class(self, cls):
            return cls
        def list(self, *args, **kwargs):
            pass
    dummy_talon.Module = DummyModule
    dummy_talon.Context = type('Context', (), {})
    sys.modules['talon'] = dummy_talon

    local_env = {}
    logic_score = 0
    logic_feedback = []

    try:
        exec(py_content, globals(), local_env)
        
        # Discover the action method defined by the agent
        target_func = None
        target_class = None
        
        for name, obj in local_env.items():
            if isinstance(obj, type):
                for attr_name in dir(obj):
                    if 'generate_blocklist' in attr_name:
                        attr = getattr(obj, attr_name)
                        if callable(attr):
                            target_func = attr
                            target_class = obj
                            break
            elif callable(obj) and 'generate_blocklist' in name:
                target_func = obj

        if target_func:
            # Safely invoke target mapping (handle self bindings if required)
            sig = inspect.signature(target_func)
            try:
                if 'self' in sig.parameters and target_class:
                    instance = target_class()
                    getattr(instance, target_func.__name__)("3389")
                else:
                    target_func("3389")
            except Exception as invoke_err:
                try: # try as int just in case they casted it differently
                    if 'self' in sig.parameters and target_class:
                        instance = target_class()
                        getattr(instance, target_func.__name__)(3389)
                    else:
                        target_func(3389)
                except Exception:
                    logic_feedback.append(f"Execution Error during logic invocation: {invoke_err}")

            # Verify extraction formatting
            with open(test_out.name, 'r') as out_f:
                written_lines = [l.strip() for l in out_f.readlines() if l.strip()]

            if "deny in from 10.0.0.2 to any" in written_lines and "deny in from 10.0.0.3 to any" in written_lines:
                if len(written_lines) == 2:
                    logic_score += 40
                    logic_feedback.append("Data parsing completely correct (unique IPs filtered and properly formatted).")
                else:
                    logic_score += 25
                    logic_feedback.append("Data parsed but contains duplicates or incorrect rows.")
            elif len(written_lines) > 0:
                logic_score += 15
                logic_feedback.append("Data parsed but formatting or extraction conditions were incorrect.")
            else:
                logic_feedback.append("Python logic executed but no rules were generated in the output file.")

        else:
            logic_feedback.append("Could not locate 'generate_blocklist' action in Python logic.")
    except Exception as e:
        # Static fallback if syntactic errors prevented execution
        logic_feedback.append(f"Dynamic Python logic execution failed: {e}")
        if 'csv' in py_content or 'open' in py_content:
            if 'DestinationPort' in py_content and 'deny in from' in py_content:
                logic_score += 15
                logic_feedback.append("Static check awarded partial points for matching relevant CSV operations.")

    finally:
        os.unlink(test_csv.name)
        os.unlink(test_out.name)

    return logic_score, " ".join(logic_feedback)