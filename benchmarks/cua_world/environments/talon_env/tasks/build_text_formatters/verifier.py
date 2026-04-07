#!/usr/bin/env python3
"""
Verifier for build_text_formatters task.

Uses robust multi-signal verification:
1. File Creation & Anti-Gaming: Checks modification timestamps against task start.
2. File Existence: Verifies Python action file, Talon command file, and test script.
3. Code Syntax & Semantics: Parses the Talon Python file with AST to ensure it uses the Talon API.
4. Correctness: Reads the output text file to verify 8 exact string transformations.
5. VLM Trajectory: Verifies the agent actually interacted with a code editor.
"""

import os
import json
import ast
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM prompt to check if the agent actually worked in the environment
VLM_PROMPT = """You are verifying an AI agent's trajectory. The agent's task was to create a Python module and text files for Talon Voice.

Look at these screenshots taken during the agent's work and answer:
1. Is there clear visual evidence that the agent opened and used a text editor or IDE (like Notepad, VS Code, PowerShell text editors, etc.)?
2. Did the agent type code or text into this editor?

Respond in JSON format:
{
    "used_text_editor": true/false,
    "typed_code_or_text": true/false,
    "confidence": "high/medium/low",
    "reasoning": "Brief explanation"
}
"""

def verify_build_text_formatters(traj, env_info, task_info):
    """Verify that the text formatters were properly implemented and produced correct output."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env function not available"}

    metadata = task_info.get('metadata', {})
    expected_lines = metadata.get('expected_lines', {})

    score = 0
    feedback_parts = []
    
    # -------------------------------------------------------------------------
    # 1. Retrieve the exported JSON from the container
    # -------------------------------------------------------------------------
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # We use standard forward slashes for the copy utility which translates to C:\ inside
        copy_from_env("C:/Users/Docker/Documents/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result from environment: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    task_start = result.get('task_start', 0)
    files = result.get('files', {})
    
    test_output = files.get('test_output', {})
    formatters_py = files.get('formatters_py', {})
    formatters_talon = files.get('formatters_talon', {})
    test_script = files.get('test_script', {})

    # -------------------------------------------------------------------------
    # 2. Verify Output File & Content (Max 45 points)
    # -------------------------------------------------------------------------
    output_exists = test_output.get('exists', False)
    output_valid = False
    lines_correct = 0

    if output_exists:
        score += 5
        feedback_parts.append("Test output file exists")
        
        content = test_output.get('content', '')
        actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
        
        # Check each of the 8 expected lines
        for key, expected_str in expected_lines.items():
            if expected_str in actual_lines:
                lines_correct += 1
                score += 5
        
        feedback_parts.append(f"{lines_correct}/8 formatted lines correct")
        if lines_correct == 8:
            output_valid = True
    else:
        feedback_parts.append("Test output file NOT found")

    # -------------------------------------------------------------------------
    # 3. Verify Python Action Module (Max 15 points)
    # -------------------------------------------------------------------------
    py_exists = formatters_py.get('exists', False)
    py_valid = False

    if py_exists:
        score += 5
        py_content = formatters_py.get('content', '')
        
        try:
            tree = ast.parse(py_content)
            score += 5
            
            # Check for Module usage and functions
            has_module = any("Module" in ast.unparse(node) for node in ast.walk(tree) if isinstance(node, (ast.Import, ast.ImportFrom, ast.Assign)))
            functions = [n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
            
            # Check if at least some formatter functions are defined
            has_formatters = any(f.startswith('format_') for f in functions)
            
            if has_module and has_formatters:
                score += 5
                py_valid = True
                feedback_parts.append("Talon Python module is valid and uses API")
            else:
                feedback_parts.append("Python module lacks Talon API components or formatter functions")
                
        except SyntaxError:
            feedback_parts.append("Python module has SYNTAX ERRORS")
    else:
        feedback_parts.append("Python module NOT found")

    # -------------------------------------------------------------------------
    # 4. Verify Talon Command File (Max 10 points)
    # -------------------------------------------------------------------------
    talon_exists = formatters_talon.get('exists', False)
    if talon_exists:
        score += 5
        talon_content = formatters_talon.get('content', '')
        if '<user.text>' in talon_content or 'user.format_' in talon_content:
            score += 5
            feedback_parts.append("Talon command file valid")
        else:
            feedback_parts.append("Talon file missing required capture/action syntax")
    else:
        feedback_parts.append("Talon command file NOT found")

    # -------------------------------------------------------------------------
    # 5. Verify Test Script Existence (Max 5 points)
    # -------------------------------------------------------------------------
    if test_script.get('exists', False):
        score += 5
        feedback_parts.append("Test script found")

    # -------------------------------------------------------------------------
    # 6. Anti-Gaming Timestamp Check (Max 10 points)
    # -------------------------------------------------------------------------
    files_created_during_task = True
    for f in [test_output, formatters_py, formatters_talon]:
        if f.get('exists') and f.get('mtime', 0) < task_start:
            files_created_during_task = False
            
    if files_created_during_task and output_exists and py_exists:
        score += 10
        feedback_parts.append("Files correctly created during task timeline")
    elif not files_created_during_task:
        feedback_parts.append("WARNING: Some files existed before task started (gaming detected)")

    # -------------------------------------------------------------------------
    # 7. VLM Trajectory Verification (Max 15 points)
    # -------------------------------------------------------------------------
    query_vlm = env_info.get('query_vlm')
    from gym_anything.vlm import sample_trajectory_frames
    
    frames = sample_trajectory_frames(traj, n=4)
    if query_vlm and frames:
        vlm_result = query_vlm(prompt=VLM_PROMPT, images=frames)
        if vlm_result.get("success"):
            parsed = vlm_result.get("parsed", {})
            if parsed.get("used_text_editor") and parsed.get("typed_code_or_text"):
                score += 15
                feedback_parts.append("VLM confirmed text editor interaction")
            else:
                feedback_parts.append("VLM did not observe editor interaction")
    else:
        # Give free points if VLM isn't available to prevent unfair failure
        score += 15
        feedback_parts.append("VLM verification skipped (assumed OK)")

    # -------------------------------------------------------------------------
    # Final Decision
    # -------------------------------------------------------------------------
    # Maximum possible score is 100.
    # Pass threshold: 75 points + required output lines + python valid
    
    passed = score >= 75 and output_valid and py_valid

    return {
        "passed": passed,
        "score": min(score, 100),  # Cap at 100
        "feedback": " | ".join(feedback_parts)
    }