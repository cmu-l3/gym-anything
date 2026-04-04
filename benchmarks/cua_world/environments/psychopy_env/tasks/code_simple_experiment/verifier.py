#!/usr/bin/env python3
"""
Verifier for code_simple_experiment task.

Verification Strategy (Hybrid: Programmatic + VLM):

Programmatic checks (55 points max):
  1. File exists, valid Python, created during task (10 pts)
  2. Has psychopy imports (visual, core, event) (10 pts)
     - `import psychopy` alone only gives 3 pts (must use specific submodules)
  3. Creates Window object (5 pts)
  4. Creates TextStim with expected text (10 pts)
  5. Uses draw() and flip() (5 pts)
  6. Uses waitKeys() (10 pts)
  7. Cleanup: win.close() or core.quit() (5 pts)

VLM checks (45 points):
  8. Shows PsychoPy Coder view with Python code (25 pts)
  9. Final state shows saved script (20 pts)

Pass threshold: 60 points (requires VLM to pass — cannot pass via terminal scripting)
Nonce gate: instant fail on mismatch
Independent file re-analysis: verifier pulls and re-parses the actual .py script
"""

import json
import tempfile
import os
import ast
import logging

logger = logging.getLogger(__name__)


def _parse_script(filepath):
    """Independently parse a Python script for PsychoPy constructs via AST."""
    data = {
        'syntax_valid': False,
        'line_count': 0,
        'code_line_count': 0,
        'has_visual_import': False,
        'has_core_import': False,
        'has_event_import': False,
        'has_bare_psychopy_import': False,
        'has_window': False,
        'has_textstim': False,
        'has_expected_text': False,
        'has_draw': False,
        'has_flip': False,
        'has_waitkeys': False,
        'has_close': False,
    }

    with open(filepath) as f:
        source = f.read()

    data['line_count'] = source.count("\n") + 1
    code_lines = [l.strip() for l in source.split("\n")
                  if l.strip() and not l.strip().startswith("#")]
    data['code_line_count'] = len(code_lines)

    try:
        compile(source, filepath, "exec")
        data['syntax_valid'] = True
    except SyntaxError:
        return data

    try:
        tree = ast.parse(source)

        for node in ast.walk(tree):
            if isinstance(node, (ast.Import, ast.ImportFrom)):
                module = ""
                if isinstance(node, ast.ImportFrom) and node.module:
                    module = node.module
                names = [alias.name for alias in node.names]

                if "psychopy" in module or "psychopy" in names:
                    # Check specific submodule imports
                    if "visual" in names or "visual" in module:
                        data['has_visual_import'] = True
                    if "core" in names or "core" in module:
                        data['has_core_import'] = True
                    if "event" in names or "event" in module:
                        data['has_event_import'] = True
                    # Bare `import psychopy` — flag separately
                    if "psychopy" in names and "visual" not in names:
                        data['has_bare_psychopy_import'] = True

            if isinstance(node, ast.Call):
                func = node.func
                if isinstance(func, ast.Attribute):
                    attr = func.attr
                    if attr == "Window":
                        data['has_window'] = True
                    elif attr == "TextStim":
                        data['has_textstim'] = True
                        # Check text argument specifically in TextStim call
                        for kw in node.keywords:
                            if kw.arg == "text" and isinstance(kw.value, ast.Constant):
                                val = str(kw.value.value).lower()
                                if "press" in val and "space" in val:
                                    data['has_expected_text'] = True
                        for arg in node.args:
                            if isinstance(arg, ast.Constant) and isinstance(arg.value, str):
                                val = arg.value.lower()
                                if "press" in val and "space" in val:
                                    data['has_expected_text'] = True
                    elif attr == "waitKeys":
                        data['has_waitkeys'] = True
                    elif attr == "draw":
                        data['has_draw'] = True
                    elif attr == "flip":
                        data['has_flip'] = True
                    elif attr in ("close", "quit"):
                        data['has_close'] = True
                elif isinstance(func, ast.Name):
                    if func.id == "Window":
                        data['has_window'] = True
                    elif func.id == "TextStim":
                        data['has_textstim'] = True
                    elif func.id == "waitKeys":
                        data['has_waitkeys'] = True

    except Exception as e:
        logger.warning(f"AST analysis error: {e}")

    return data


def verify_code_simple_experiment(traj, env_info, task_info):
    """Verify that a simple PsychoPy script was written in Coder view."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    output_file = metadata.get('output_file', '/home/ga/PsychoPyExperiments/simple_rt.py')

    feedback_parts = []
    score = 0

    # Load export result
    result = {}
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as tmp:
            tmp_path = tmp.name
        copy_from_env("/tmp/code_simple_experiment_result.json", tmp_path)
        with open(tmp_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Could not read export result: {e}")
    finally:
        if 'tmp_path' in locals() and os.path.exists(tmp_path):
            os.unlink(tmp_path)

    # ================================================================
    # NONCE GATE
    # ================================================================
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as tmp:
            nonce_path = tmp.name
        copy_from_env("/home/ga/.task_nonce", nonce_path)
        with open(nonce_path, 'r') as f:
            expected_nonce = f.read().strip()
        result_nonce = result.get('result_nonce', '')
        if expected_nonce and result_nonce != expected_nonce:
            return {
                "passed": False,
                "score": 0,
                "feedback": "FAIL: Result nonce mismatch — export result may have been tampered with",
                "details": {"nonce_mismatch": True}
            }
    except Exception as e:
        logger.warning(f"Nonce check skipped: {e}")
    finally:
        if 'nonce_path' in locals() and os.path.exists(nonce_path):
            os.unlink(nonce_path)

    # ================================================================
    # INDEPENDENT FILE RE-ANALYSIS
    # ================================================================
    file_data = None
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix='.py') as tmp:
            script_path = tmp.name
        copy_from_env(output_file, script_path)
        file_data = _parse_script(script_path)
    except Exception as e:
        logger.warning(f"Independent file re-analysis failed: {e}")
    finally:
        if 'script_path' in locals() and os.path.exists(script_path):
            os.unlink(script_path)

    d = file_data if file_data else result

    # ================================================================
    # PROGRAMMATIC CHECKS (55 points max)
    # ================================================================

    # Criterion 1: File exists, valid Python syntax, and created during task (10 pts)
    syntax_valid = d.get('syntax_valid', False)
    file_exists = (file_data is not None) or result.get('file_exists', False)
    file_modified = result.get('file_modified', False)

    if file_exists and file_modified and syntax_valid:
        score += 10
        feedback_parts.append(f"Script file exists, valid Python ({d.get('code_line_count', 0)} code lines)")
    elif file_exists and file_modified:
        score += 5
        feedback_parts.append("File exists but has Python syntax errors")
    elif file_exists:
        score += 3
        feedback_parts.append("File exists but may not be from this task")
    else:
        feedback_parts.append("FAIL: Script file not found")

    # Criterion 2: PsychoPy imports (10 pts)
    # `import psychopy` alone only gets 3 pts — must use specific submodule imports
    has_bare = d.get('has_bare_psychopy_import', False)
    imports_found = 0
    if d.get('has_visual_import'):
        imports_found += 1
    if d.get('has_core_import'):
        imports_found += 1
    if d.get('has_event_import'):
        imports_found += 1

    # If only bare import with no specific submodule imports, cap at 3
    if has_bare and imports_found == 0:
        score += 3
        feedback_parts.append("Bare 'import psychopy' — no specific submodule imports")
    elif imports_found == 3:
        score += 10
        feedback_parts.append("All 3 PsychoPy imports present (visual, core, event)")
    elif imports_found == 2:
        score += 7
        feedback_parts.append(f"{imports_found}/3 PsychoPy imports found")
    elif imports_found == 1:
        score += 4
        feedback_parts.append(f"Only {imports_found}/3 PsychoPy imports found")
    else:
        feedback_parts.append("FAIL: No PsychoPy imports found")

    # Criterion 3: Window object (5 pts)
    if d.get('has_window'):
        score += 5
        feedback_parts.append("Window creation found")
    else:
        feedback_parts.append("FAIL: No Window creation found")

    # Criterion 4: TextStim with expected text (10 pts)
    # has_expected_text now requires both "press" AND "space" (not just "space")
    if d.get('has_textstim') and d.get('has_expected_text'):
        score += 10
        feedback_parts.append("TextStim with expected text content found")
    elif d.get('has_textstim'):
        score += 7
        feedback_parts.append("TextStim found but without expected 'Press SPACE' text")
    else:
        feedback_parts.append("FAIL: No TextStim found")

    # Criterion 5: draw() and flip() (5 pts)
    if d.get('has_draw') and d.get('has_flip'):
        score += 5
        feedback_parts.append("draw() and flip() calls found")
    elif d.get('has_draw') or d.get('has_flip'):
        score += 3
        feedback_parts.append("Partial rendering calls found")
    else:
        feedback_parts.append("FAIL: No draw()/flip() calls found")

    # Criterion 6: waitKeys() (10 pts)
    if d.get('has_waitkeys'):
        score += 10
        feedback_parts.append("waitKeys() call found")
    else:
        feedback_parts.append("FAIL: No waitKeys() call found")

    # Criterion 7: Cleanup (5 pts)
    if d.get('has_close'):
        score += 5
        feedback_parts.append("Cleanup code present (close/quit)")
    else:
        feedback_parts.append("Note: No cleanup code found")

    # ================================================================
    # STRUCTURAL COMPLEXITY GATE
    # A real PsychoPy script with imports, Window, TextStim, draw, flip,
    # waitKeys, and close needs at least 8 non-comment lines.
    # Penalize trivially short scripts that might be terminal-crafted.
    # ================================================================
    code_lines = d.get('code_line_count', 0)
    if code_lines < 5:
        penalty = min(score, 10)
        score -= penalty
        feedback_parts.append(f"PENALTY: Extremely short script ({code_lines} code lines, -{penalty} pts)")
    elif code_lines < 8:
        penalty = min(score, 5)
        score -= penalty
        feedback_parts.append(f"PENALTY: Very short script ({code_lines} code lines, -{penalty} pts)")

    # ================================================================
    # VLM CHECKS (45 points)
    # These are essential — programmatic max is 55, below the 60-point
    # pass threshold. An agent MUST use PsychoPy Coder (not terminal)
    # to pass this task.
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_trajectory_frames = env_info.get('sample_trajectory_frames')
    get_final_screenshot = env_info.get('get_final_screenshot')

    if query_vlm and sample_trajectory_frames:
        try:
            frames = sample_trajectory_frames(traj, 4)
            if frames:
                vlm_response = query_vlm(
                    "Is the user writing Python code in the PsychoPy Coder view? "
                    "The PsychoPy Coder has a specific toolbar and shell panel. "
                    "Can you see PsychoPy's Coder interface (not a generic text editor like nano or vim)? "
                    "Answer yes or no.",
                    frames
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 25
                    feedback_parts.append("VLM: Code writing in PsychoPy Coder view confirmed")
                else:
                    feedback_parts.append("VLM: PsychoPy Coder view not clearly visible")
        except Exception as e:
            feedback_parts.append(f"VLM trajectory check skipped: {e}")

    if query_vlm and get_final_screenshot:
        try:
            final_screenshot = get_final_screenshot(traj)
            if final_screenshot:
                vlm_response = query_vlm(
                    "Does this screenshot show PsychoPy's Coder view with a saved Python script? "
                    "Can you see code with PsychoPy imports (from psychopy import)? "
                    "Answer yes or no.",
                    [final_screenshot]
                )
                vlm_text = (vlm_response or "").strip().lower()
                if vlm_text.startswith('yes'):
                    score += 20
                    feedback_parts.append("VLM: Saved script visible in PsychoPy Coder")
                else:
                    feedback_parts.append("VLM: Script not clearly visible in PsychoPy Coder")
        except Exception as e:
            feedback_parts.append(f"VLM final check skipped: {e}")

    # ================================================================
    # SCORE CAP AND PASS CRITERIA
    # ================================================================
    score = min(score, 100)
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "file_exists": file_exists,
            "syntax_valid": syntax_valid,
            "imports": {
                "visual": d.get('has_visual_import', False),
                "core": d.get('has_core_import', False),
                "event": d.get('has_event_import', False),
                "bare_psychopy": d.get('has_bare_psychopy_import', False),
            },
            "elements": {
                "window": d.get('has_window', False),
                "textstim": d.get('has_textstim', False),
                "has_expected_text": d.get('has_expected_text', False),
                "waitkeys": d.get('has_waitkeys', False),
                "draw": d.get('has_draw', False),
                "flip": d.get('has_flip', False)
            },
            "independent_analysis": file_data is not None,
        }
    }
