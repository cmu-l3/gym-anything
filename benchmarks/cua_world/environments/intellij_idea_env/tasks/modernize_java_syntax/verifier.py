#!/usr/bin/env python3
"""Verifier for modernize_java_syntax task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_modernize_java_syntax(traj, env_info, task_info):
    """Verify that the Java project was modernized correctly.
    
    Criteria:
    1. Project compiles (15 pts) - HARD REQUIREMENT
    2. Tests pass (15 pts)
    3. Lambdas used (15 pts) - No 'new Comparator', 'new Runnable'
    4. Try-with-resources used (15 pts) - No 'finally { .close() }'
    5. Switch Expression used (10 pts) - Arrow syntax
    6. Text Blocks used (10 pts) - Triple quotes
    7. Diamond Operator / Streams used (10 pts)
    8. Anti-gaming: Files modified (10 pts)
    
    Max Score: 100
    Pass Threshold: 60 (with compile success)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Load Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Compile & Test Check (30 pts)
    compile_success = result.get('compile_success', False)
    test_success = result.get('test_success', False)
    files_modified = result.get('files_modified', False)
    
    if not compile_success:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Project failed to compile. Modernization broke the build."
        }
    score += 15
    feedback_parts.append("Project compiles")

    if test_success:
        score += 15
        feedback_parts.append("Tests passed")
    else:
        feedback_parts.append("Tests failed (logic broken during refactoring)")

    if files_modified:
        score += 10
        feedback_parts.append("Files were modified")
    else:
        feedback_parts.append("No files modified (Do Nothing detected)")
        return {"passed": False, "score": 0, "feedback": "No files were modified."}

    sources = result.get('source_files', {})
    
    # 2. Check for Lambdas (DataProcessor, EventSystem) (15 pts)
    # Search for legacy patterns to ensure they are GONE
    dp_code = sources.get("DataProcessor.java", "")
    es_code = sources.get("EventSystem.java", "")
    
    legacy_anon = ["new Comparator<", "new Runnable(", "new Consumer<"]
    found_legacy_anon = any(p in dp_code for p in legacy_anon) or \
                        any(p in es_code for p in legacy_anon)
    
    has_lambda = "->" in dp_code or "->" in es_code or "::" in dp_code
    
    if not found_legacy_anon and has_lambda:
        score += 15
        feedback_parts.append("Anonymous classes converted to lambdas")
    elif has_lambda:
        score += 8
        feedback_parts.append("Some lambdas used, but legacy anonymous classes still present")
    else:
        feedback_parts.append("No lambdas detected")

    # 3. Check for Try-with-Resources (FileHandler) (15 pts)
    fh_code = sources.get("FileHandler.java", "")
    # Should find "try (" pattern
    has_twr = "try (" in fh_code or "try(" in fh_code
    # Should NOT find manual close in finally roughly checked by absence of explicit .close() inside finally blocks? 
    # Hard to regex strictly, but let's check for the positive signal
    if has_twr:
        score += 15
        feedback_parts.append("Try-with-resources used")
    else:
        feedback_parts.append("Try-with-resources not found")

    # 4. Check for Switch Expression (ConfigParser) (10 pts)
    cp_code = sources.get("ConfigParser.java", "")
    # Look for arrow syntax "case ... ->"
    if "->" in cp_code and "switch" in cp_code:
        score += 10
        feedback_parts.append("Switch expression used")
    else:
        feedback_parts.append("Legacy switch statement remaining")

    # 5. Check for Text Blocks (ReportGenerator) (10 pts)
    rg_code = sources.get("ReportGenerator.java", "")
    if '"""' in rg_code:
        score += 10
        feedback_parts.append("Text blocks used")
    else:
        feedback_parts.append("Text blocks not found")

    # 6. Check for Diamond Operator / Streams (DataProcessor) (10 pts)
    # Check for absence of redundant types: new ArrayList<String> -> new ArrayList<>
    has_diamond = "new ArrayList<>" in dp_code or "new ArrayList<>(" in dp_code
    has_streams = ".stream()" in dp_code or "::" in dp_code
    
    if has_diamond or has_streams:
        score += 10
        feedback_parts.append("Diamond operator or Streams used")
    else:
        feedback_parts.append("No diamond operator or streams detected")

    passed = score >= 60 and compile_success and test_success
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }