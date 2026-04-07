#!/usr/bin/env python3
"""
Verifier for create_latex_voice_builder task.

VERIFICATION STRATEGY:
- Uses `copy_from_env` to extract the generated files from the Windows container.
- Parses Python content dynamically looking for expected logic (CSV handling, AST methods).
- Parses Talon code for exact regex matches bridging the voice-to-Python gap.
- Incorporates anti-gaming timestamps exported by PowerShell.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_latex_voice_builder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    metadata = task_info.get('metadata', {})
    csv_name = metadata.get('csv_name', 'latex_symbols.csv')

    # ================================================================
    # 1. Read task metadata json
    # ================================================================
    result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", result_file.name)
        with open(result_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(result_file.name):
            os.unlink(result_file.name)

    py_exists = result.get('py_exists', False)
    talon_exists = result.get('talon_exists', False)
    py_created = result.get('py_created', False)
    talon_created = result.get('talon_created', False)

    # Criterion: File Creation (10 pts) - Requires anti-gaming timestamp compliance
    if py_created and talon_created:
        score += 10
        feedback_parts.append("Files successfully created during task")
    elif py_exists and talon_exists:
        score += 5
        feedback_parts.append("Files exist but were not modified/created during this session")
    else:
        feedback_parts.append("Required files do not exist")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # ================================================================
    # 2. Extract and Parse Source Files
    # ================================================================
    py_file = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    talon_file = tempfile.NamedTemporaryFile(delete=False, suffix='.talon')
    py_content = ""
    talon_content = ""

    try:
        copy_from_env("C:/tmp/latex_math.py", py_file.name)
        with open(py_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            py_content = f.read()

        copy_from_env("C:/tmp/latex_math.talon", talon_file.name)
        with open(talon_file.name, 'r', encoding='utf-8', errors='ignore') as f:
            talon_content = f.read()
    except Exception as e:
        feedback_parts.append(f"Error reading source files: {e}")
    finally:
        if os.path.exists(py_file.name): os.unlink(py_file.name)
        if os.path.exists(talon_file.name): os.unlink(talon_file.name)

    # ================================================================
    # 3. Python Module Logic Checks (70 points)
    # ================================================================
    csv_score = 0
    list_score = 0
    frac_score = 0
    env_score = 0

    if py_content:
        # CSV Data Loading (25 pts)
        if 'open(' in py_content and csv_name in py_content:
            csv_score = 25
            feedback_parts.append("CSV loading logic present")
        else:
            feedback_parts.append("Missing CSV loading logic")

        # Context List Population (15 pts)
        if 'ctx.lists' in py_content and 'user.latex_symbols' in py_content:
            list_score = 15
            feedback_parts.append("Context list correctly populated")
        else:
            feedback_parts.append("Missing context list population")

        # Fraction Action (15 pts)
        if 'def latex_insert_fraction' in py_content:
            # check string insertions handling escaping variations
            if 'frac{}{}' in py_content.replace('\\\\', '\\'): 
                if 'left' in py_content.lower():
                    frac_score = 15
                    feedback_parts.append("Fraction action fully implemented")
                else:
                    frac_score = 10
                    feedback_parts.append("Fraction action missing cursor left movement")
            else:
                frac_score = 5
                feedback_parts.append("Fraction action defined but missing expected LaTeX string")
        else:
            feedback_parts.append("Missing latex_insert_fraction action")

        # Environment Action (15 pts)
        if 'def latex_environment' in py_content:
            if 'begin{' in py_content and 'end{' in py_content:
                if 'up' in py_content.lower():
                    env_score = 15
                    feedback_parts.append("Environment action fully implemented")
                else:
                    env_score = 10
                    feedback_parts.append("Environment action missing cursor up movement")
            else:
                env_score = 5
                feedback_parts.append("Environment action defined but missing begin/end formatters")
        else:
            feedback_parts.append("Missing latex_environment action")

    score += (csv_score + list_score + frac_score + env_score)

    # ================================================================
    # 4. Talon Voice Mappings Check (20 points)
    # ================================================================
    map_score = 0
    macro_score = 0

    if talon_content:
        # Talon Command Mappings (10 pts)
        mappings = 0
        if re.search(r'math symbol\s*[{<]user\.latex_symbols[}>]', talon_content): mappings += 1
        if re.search(r'math fraction\s*:', talon_content): mappings += 1
        if re.search(r'math begin\s*<user\.text>', talon_content): mappings += 1

        if mappings == 3:
            map_score = 10
            feedback_parts.append("All primary Talon mappings mapped")
        elif mappings > 0:
            map_score = 5
            feedback_parts.append(f"Partial primary Talon mappings ({mappings}/3)")
        else:
            feedback_parts.append("Missing primary Talon mappings")

        # Sub/Superscript Macros (10 pts)
        macros = 0
        if re.search(r'math superscript\s*:', talon_content) and '^' in talon_content and 'left' in talon_content.lower():
            macros += 1
        if re.search(r'math subscript\s*:', talon_content) and '_' in talon_content and 'left' in talon_content.lower():
            macros += 1

        if macros == 2:
            macro_score = 10
            feedback_parts.append("Sub/Superscript macros fully mapped")
        elif macros == 1:
            macro_score = 5
            feedback_parts.append("Partial Sub/Superscript macro mappings")
        else:
            feedback_parts.append("Missing Sub/Superscript inline macros")

    score += (map_score + macro_score)

    # ================================================================
    # 5. Final Threshold Checks
    # ================================================================
    key_criteria_met = (csv_score >= 15) and (frac_score >= 10)
    passed = (score >= 70) and key_criteria_met

    if passed:
        feedback_parts.insert(0, "✅ SUCCESS")
    else:
        feedback_parts.insert(0, "❌ FAILED")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }