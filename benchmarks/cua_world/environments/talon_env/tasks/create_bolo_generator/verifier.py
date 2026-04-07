#!/usr/bin/env python3
"""
Verifier for create_bolo_generator task.

Uses a mocked Python sandbox to safely execute the agent's Talon script and
dynamically evaluate its public API behavior (state preservation, defaults, string 
formatting, and template logic) without requiring an actual Talon backend on the host.
"""

import json
import os
import sys
import tempfile
import types
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_agent_code(py_content):
    """
    Executes the agent's Python script inside a mocked Talon environment
    and thoroughly tests the API endpoints required by the specification.
    """
    # 1. Mock the `talon` library
    mock_talon = types.ModuleType("talon")
    
    class MockModule:
        def action_class(self, cls):
            self.action_cls = cls
            return cls
            
    mock_mod = MockModule()
    mock_talon.Module = lambda: mock_mod

    class MockActions:
        def __init__(self):
            self.inserted = []
        def insert(self, text):
            self.inserted.append(text)
            
    mock_actions = MockActions()
    mock_talon.actions = mock_actions

    sys.modules["talon"] = mock_talon

    namespace = {}
    results = {
        "defaults_correct": False,
        "plate_formatted": False,
        "dot_formatted": False,
        "template_correct": False,
        "reset_works": False,
        "error": None
    }

    try:
        # Evaluate the agent's code in our secure namespace
        exec(py_content, namespace)
        
        # Helper to dynamically find and invoke methods, handling
        # both staticmethods and standard instance methods elegantly.
        def find_func(name):
            if hasattr(mock_mod, 'action_cls') and hasattr(mock_mod.action_cls, name):
                func = getattr(mock_mod.action_cls, name)
                def wrapper(*args):
                    try:
                        # Try to instantiate the class if it's a standard method
                        instance = mock_mod.action_cls()
                        return getattr(instance, name)(*args)
                    except TypeError:
                        # Fallback if it's a static method
                        return func(*args)
                return wrapper
            
            # Agent might have put it in global scope instead of a class
            if name in namespace:
                return namespace[name]
            return None

        # Extract functions
        reset = find_func("bolo_reset")
        set_incident = find_func("bolo_set_incident")
        set_suspect = find_func("bolo_set_suspect")
        set_vehicle = find_func("bolo_set_vehicle")
        set_plate = find_func("bolo_set_plate")
        set_dot = find_func("bolo_set_dot")
        set_armed = find_func("bolo_set_armed")
        get_text = find_func("bolo_get_text")
        insert_bolo = find_func("bolo_insert")

        if not all([reset, set_incident, set_suspect, set_vehicle, set_plate, set_dot, set_armed, get_text]):
            missing = [name for name, f in zip(
                ["bolo_reset", "bolo_set_incident", "bolo_set_suspect", "bolo_set_vehicle", "bolo_set_plate", "bolo_set_dot", "bolo_set_armed", "bolo_get_text"], 
                [reset, set_incident, set_suspect, set_vehicle, set_plate, set_dot, set_armed, get_text]
            ) if not f]
            results["error"] = f"Missing required functions: {', '.join(missing)}"
            return results

        # Test 1: Defaults Check
        reset()
        default_text = get_text()
        if default_text and default_text.count("UNSPECIFIED") >= 6:
            results["defaults_correct"] = True

        # Test 2: Text Formatting Check
        set_plate("a b c 1 2 3")
        set_dot("northbound")
        text2 = get_text()
        if text2 and "ABC123" in text2:
            results["plate_formatted"] = True
        if text2 and "NORTHBOUND" in text2:
            results["dot_formatted"] = True

        # Test 3: Standardized Template Architecture
        reset()
        set_incident("Robbery")
        set_suspect("John Doe")
        set_vehicle("Red Ford")
        set_plate("x y z 9 9")
        set_dot("south")
        set_armed("yes")

        final_text = get_text()
        expected_template = "*** BOLO ALERT ***\nINCIDENT: Robbery\nSUSPECT: John Doe\nVEHICLE: Red Ford\nPLATE: XYZ99\nDOT: SOUTH\nARMED: YES\n******************"
        
        if final_text and final_text.strip() == expected_template.strip():
            results["template_correct"] = True
        
        # Test 4: Reset Trigger Check
        if insert_bolo:
            insert_bolo()
            if len(mock_actions.inserted) > 0 and "Robbery" in mock_actions.inserted[-1]:
                if get_text().count("UNSPECIFIED") >= 6:
                    results["reset_works"] = True
        
        # Fallback reset manual check
        if not results["reset_works"]:
            reset()
            if get_text().count("UNSPECIFIED") >= 6:
                results["reset_works"] = True

    except Exception as e:
        results["error"] = f"Execution error in agent's code: {str(e)}"

    return results

def verify_create_bolo_generator(traj, env_info, task_info):
    """
    Main verification function querying the output exported from container.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Use Windows-style path corresponding to export_result.ps1
        copy_from_env("C:\\tmp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_content = result.get('py_content', '')
    talon_content = result.get('talon_content', '')

    # CRITERION 1: File check
    if py_exists and talon_exists:
        score += 10
        feedback_parts.append("✅ Both .py and .talon files exist")
    else:
        feedback_parts.append("❌ Missing required configuration files")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # CRITERION 2: Evaluate Talon mappings (.talon syntax)
    cmds = [
        "bolo set incident", "bolo set suspect", "bolo set vehicle", "bolo set plate", 
        "bolo set direction", "bolo set armed", "bolo clear all", "bolo generate"
    ]
    acts = [
        "bolo_set_incident", "bolo_set_suspect", "bolo_set_vehicle", "bolo_set_plate",
        "bolo_set_dot", "bolo_set_armed", "bolo_reset", "bolo_insert"
    ]
    
    cmd_count = sum([1 for c in cmds if c in talon_content.lower()])
    act_count = sum([1 for a in acts if a in talon_content])
    
    mapping_score = (cmd_count + act_count) / 16.0 * 20
    score += int(mapping_score)
    
    if mapping_score == 20:
        feedback_parts.append("✅ Command mappings perfect")
    else:
        feedback_parts.append(f"⚠️ Command mappings partial ({cmd_count}/8 cmds, {act_count}/8 acts)")

    # Evaluate Python Logic dynamically
    test_results = test_agent_code(py_content)
    
    if test_results.get("error"):
        feedback_parts.append(f"❌ Python error: {test_results['error']}")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
        
    # CRITERION 3: Defaults
    if test_results["defaults_correct"]:
        score += 10
        feedback_parts.append("✅ State defaults correct ('UNSPECIFIED')")
    else:
        feedback_parts.append("❌ Defaults incorrect")
        
    # CRITERION 4: Text Formatter
    if test_results["plate_formatted"] and test_results["dot_formatted"]:
        score += 20
        feedback_parts.append("✅ Formatting logic correct")
    else:
        feedback_parts.append("❌ Formatting logic failed (whitespace/case handling)")

    # CRITERION 5: Exact Multi-line Output Match
    if test_results["template_correct"]:
        score += 30
        feedback_parts.append("✅ Template matches expected output perfectly")
    else:
        feedback_parts.append("❌ Template format mismatch")

    # CRITERION 6: Reset logic
    if test_results["reset_works"]:
        score += 10
        feedback_parts.append("✅ State reset functions properly")
    else:
        feedback_parts.append("❌ State reset failed")

    passed = score >= 80 and test_results["template_correct"] and test_results["plate_formatted"]
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }