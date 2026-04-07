#!/usr/bin/env python3
"""
Verifier for build_genomic_voice_search task.
Uses pure programmatic validation against the agent's Talon code, ensuring edge cases
and custom business logic were properly implemented.
"""

import json
import os
import tempfile
import sys
import importlib.util
import inspect
import builtins
import io
import re
import types

# -------------------------------------------------------------------
# Talon Mock Framework
# Ensures the user's `from talon import ...` imports succeed, while
# trapping calls to `actions.insert` and `app.notify` for unit testing.
# -------------------------------------------------------------------
mock_talon = types.ModuleType('talon')

class MockTalonState:
    inserted = []
    notified = []
    @classmethod
    def reset(cls):
        cls.inserted = []
        cls.notified = []

class MockModule:
    def __init__(self, *args, **kwargs):
        pass
    def action_class(self, cls):
        # Return the original class unmodified so we can instantiate it and call its methods.
        return cls

class MockApp:
    @staticmethod
    def notify(*args, **kwargs):
        text = args[0] if args else kwargs.get('body', '')
        MockTalonState.notified.append(str(text))

class MockActions:
    def insert(self, text, *args, **kwargs):
        MockTalonState.inserted.append(str(text))
    def __getattr__(self, name):
        return lambda *args, **kwargs: None

mock_talon.Module = MockModule
mock_talon.app = MockApp()
mock_talon.actions = MockActions()

# -------------------------------------------------------------------
# Helper to extract methods securely 
# -------------------------------------------------------------------
def get_method(module, method_name):
    """Safely extract a method from a module or its classes."""
    if hasattr(module, method_name):
        func = getattr(module, method_name)
        if inspect.isfunction(func) or inspect.ismethod(func):
            return lambda *args: func(*args)
            
    for attr_name in dir(module):
        attr = getattr(module, attr_name)
        if type(attr) is type: # it's a class
            if hasattr(attr, method_name):
                func = getattr(attr, method_name)
                if inspect.isfunction(func) or inspect.ismethod(func):
                    try:
                        instance = attr()
                        return lambda *args: getattr(instance, method_name)(*args)
                    except:
                        pass
    return None

# -------------------------------------------------------------------
# Verifier
# -------------------------------------------------------------------
def verify_genomic_voice_search(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    temp_talon = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
    
    try:
        # Load exported metrics
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
            
        py_exists = result.get('py_exists', False)
        talon_exists = result.get('talon_exists', False)
        
        # Check structure
        if py_exists:
            score += 5
            feedback_parts.append("genomics.py created")
            copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\genomics.py", temp_py.name)
        else:
            feedback_parts.append("genomics.py missing")
            
        if talon_exists:
            score += 5
            feedback_parts.append("genomics.talon created")
            copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\genomics.talon", temp_talon.name)
        else:
            feedback_parts.append("genomics.talon missing")
            
        if not (py_exists and talon_exists):
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}
            
        # Check .talon file content via Regex
        with open(temp_talon.name, 'r') as f:
            talon_content = f.read()
            
        has_type_cmd = re.search(r"dictate sequence <user\.text>\s*:\s*user\.type_sequence\((user\.)?text\)", talon_content, re.IGNORECASE)
        has_search_cmd = re.search(r"search motif <user\.text>\s*:\s*user\.search_motif\((user\.)?text\)", talon_content, re.IGNORECASE)
        
        if has_type_cmd and has_search_cmd:
            score += 10
            feedback_parts.append("Talon commands bound correctly")
        else:
            feedback_parts.append("Talon commands missing or malformed")
            
        # Dynamically import genomics.py for programmatic validation
        sys.modules['talon'] = mock_talon
        
        # Intercept and mock FASTA file reads strictly for the genome reference path.
        original_open = builtins.open
        original_io_open = io.open
        
        def custom_open(file, *args, **kwargs):
            file_str = str(file).replace('\\', '/')
            if 'workspace/data/reference.fasta' in file_str.lower():
                from io import StringIO
                # Note: Sequence is broken across newlines to ensure agent strips them correctly!
                return StringIO(">chr1 mock\nACGT\nTGCA\n")
            return original_open(file, *args, **kwargs)
            
        builtins.open = custom_open
        io.open = custom_open
        
        try:
            # Import module
            spec = importlib.util.spec_from_file_location("genomics", temp_py.name)
            genomics = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(genomics)
            
            parse_nucleotides = get_method(genomics, 'parse_nucleotides')
            type_sequence = get_method(genomics, 'type_sequence')
            search_motif = get_method(genomics, 'search_motif')
            
            # Unit Test: parse_nucleotides
            if parse_nucleotides:
                try:
                    res = parse_nucleotides("adenine random cytosine guanine junk thymine uracil")
                    if res == "ACGTU":
                        score += 25
                        feedback_parts.append("parse_nucleotides logic correct")
                    else:
                        feedback_parts.append(f"parse_nucleotides logic failed: got '{res}'")
                except Exception as e:
                    feedback_parts.append(f"parse_nucleotides threw error: {str(e)}")
            else:
                feedback_parts.append("parse_nucleotides missing")
                
            # Unit Test: type_sequence
            if type_sequence:
                try:
                    MockTalonState.reset()
                    type_sequence("thymine uracil")
                    if "TU" in MockTalonState.inserted:
                        score += 15
                        feedback_parts.append("type_sequence integration works")
                    else:
                        feedback_parts.append("type_sequence did not invoke actions.insert with correct text")
                except Exception as e:
                    feedback_parts.append(f"type_sequence threw error: {str(e)}")
            else:
                feedback_parts.append("type_sequence missing")
                
            # Unit Test: search_motif
            if search_motif:
                try:
                    # 1. Length constraint check
                    MockTalonState.reset()
                    search_motif("adenine cytosine") # Length 2
                    if "Motif too short" in MockTalonState.notified:
                        score += 10
                        feedback_parts.append("search_motif handles short length gracefully")
                    else:
                        feedback_parts.append("search_motif failed <4 length check logic")
                        
                    # 2. Missing sequence check
                    MockTalonState.reset()
                    search_motif("adenine adenine adenine adenine") # AAAA
                    if "AAAA [MISSING]" in MockTalonState.inserted:
                        score += 10
                        feedback_parts.append("search_motif handles absent sequences")
                    else:
                        feedback_parts.append("search_motif logic failed when motif is missing")
                        
                    # 3. Present sequence AND newline stripping check
                    MockTalonState.reset()
                    search_motif("adenine cytosine guanine thymine thymine guanine cytosine adenine") # ACGTTGCA
                    if "ACGTTGCA [FOUND]" in MockTalonState.inserted:
                        score += 20
                        feedback_parts.append("search_motif properly parses FASTA layout and finds motif")
                    else:
                        feedback_parts.append("search_motif failed FASTA parsing/newline stripping logic")
                        
                except Exception as e:
                    feedback_parts.append(f"search_motif threw error: {str(e)}")
            else:
                feedback_parts.append("search_motif missing")
                
        except Exception as e:
            feedback_parts.append(f"Fatal error evaluating genomics.py logic: {str(e)}")
        finally:
            # Restore environment builtins
            builtins.open = original_open
            io.open = original_io_open
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verifier crash: {str(e)}"}
    finally:
        # Secure cleanup 
        for f in [temp_json, temp_py, temp_talon]:
            if os.path.exists(f.name):
                os.unlink(f.name)
                
    # Pass constraint evaluates full execution mapping
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }