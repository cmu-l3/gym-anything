#!/usr/bin/env python3
import json
import os
import tempfile

def verify_fix_molecular_mass_calculator(traj, env_info, task_info):
    """
    Verify fixes for the molecular mass calculator:
    1. Chlorine atomic weight data fix (20 pts)
    2. Multi-digit subscript parsing logic fix (30 pts)
    3. Parentheses multiplier logic fix (30 pts)
    4. No regression on basic tests (20 pts)
    
    Pass threshold: 70/100
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env not available",
        }

    task_name = "fix_molecular_mass_calculator"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r", encoding="utf-8-sig") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found — export_result.sh may not have run",
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Result JSON malformed: {e}",
        }

    score = 0
    parts = []
    
    # Criterion 1: Chlorine Data Fix (20 pts)
    if result.get("cl_data_fixed", False):
        score += 20
        parts.append("Fixed Chlorine atomic weight (20/20)")
    else:
        parts.append("Chlorine atomic weight incorrect or test failed (0/20)")

    # Criterion 2: Subscript Parsing Fix (30 pts)
    if result.get("subscript_parsing_fixed", False):
        score += 30
        parts.append("Fixed multi-digit subscript parsing (30/30)")
    else:
        parts.append("Multi-digit parsing failed (C12H22O11 test failed) (0/30)")

    # Criterion 3: Parentheses Logic Fix (30 pts)
    if result.get("parens_logic_fixed", False):
        score += 30
        parts.append("Fixed parentheses multiplier logic (30/30)")
    else:
        parts.append("Parentheses multiplier logic failed (Mg(OH)2 test failed) (0/30)")

    # Criterion 4: Regression Check (20 pts)
    if result.get("regression_ok", False):
        score += 20
        parts.append("Basic functionality preserved (20/20)")
    else:
        parts.append("Regression detected: basic tests failed (0/20)")

    passed = score >= 70
    tests_passed = result.get("tests_passed", 0)
    tests_failed = result.get("tests_failed", 0)
    
    summary = f"Score: {score}/100 | Tests: {tests_passed} passing, {tests_failed} failing"
    
    return {
        "passed": passed,
        "score": score,
        "feedback": f"{summary} | " + " | ".join(parts)
    }