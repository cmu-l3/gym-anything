#!/usr/bin/env python3
"""Verifier for refactor_code task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_refactor_code(traj, env_info, task_info):
    """Verify that Calculator.java was refactored correctly.

    Criteria:
    1. Method 'calc' renamed to 'calculate' (25 pts)
    2. Parameters renamed: x->firstOperand, y->secondOperand, o->operation (25 pts)
    3. Extracted method 'logOperation' exists and is called (25 pts)
    4. Project compiles successfully (25 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/refactor-demo')
    target_file = metadata.get('target_file', 'src/main/java/org/lable/oss/helloworld/Calculator.java')

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    calc_content = copy_and_read(f"{project_dir}/{target_file}")
    if not calc_content:
        return {"passed": False, "score": 0, "feedback": "Calculator.java not found"}

    # --- Criterion 1: Method renamed calc -> calculate (25 pts) ---
    has_calculate = bool(re.search(r'(public|private|protected)\s+double\s+calculate\s*\(', calc_content))
    has_calc = bool(re.search(r'(public|private|protected)\s+double\s+calc\s*\(', calc_content))

    if has_calculate and not has_calc:
        score += 25
        feedback_parts.append("Method renamed: calc -> calculate")
    elif has_calculate and has_calc:
        score += 15
        feedback_parts.append("Method 'calculate' exists but 'calc' also still present")
    elif has_calc:
        feedback_parts.append("Method still named 'calc' (not renamed)")
    else:
        feedback_parts.append("Neither 'calc' nor 'calculate' method found")

    # --- Criterion 2: Parameters renamed (25 pts) ---
    param_score = 0
    has_first_operand = 'firstOperand' in calc_content
    has_second_operand = 'secondOperand' in calc_content
    has_operation = re.search(r'String\s+operation', calc_content) is not None

    # Check old parameter names are gone from method signature
    # Allow them in other contexts (strings, comments)
    method_sig = re.search(r'(calculate|calc)\s*\((.*?)\)', calc_content)
    old_params_in_sig = False
    if method_sig:
        sig_text = method_sig.group(2)
        old_params_in_sig = (
            re.search(r'\bdouble\s+x\b', sig_text) is not None or
            re.search(r'\bdouble\s+y\b', sig_text) is not None or
            re.search(r'\bString\s+o\b', sig_text) is not None
        )

    if has_first_operand:
        param_score += 8
    if has_second_operand:
        param_score += 8
    if has_operation:
        param_score += 9

    if param_score > 0 and not old_params_in_sig:
        feedback_parts.append(f"Parameters renamed: {param_score}/25 pts")
    elif param_score > 0:
        param_score = max(param_score - 5, 0)
        feedback_parts.append(f"Parameters partially renamed (old names still in signature): {param_score}/25 pts")
    else:
        feedback_parts.append("Parameters not renamed")

    score += param_score

    # --- Criterion 3: Extract method logOperation (25 pts) ---
    # Check for a method named logOperation
    has_log_method = bool(re.search(
        r'(private|public|protected|static|\s)+\s*(void|static\s+void)\s+logOperation\s*\(',
        calc_content
    ))
    # Also accept any method with "log" in its name
    has_any_log_method = bool(re.search(
        r'(private|public|protected)\s+\w+\s+log\w*\s*\(',
        calc_content
    ))
    calls_log_method = 'logOperation(' in calc_content

    if has_log_method and calls_log_method:
        score += 25
        feedback_parts.append("Method 'logOperation' extracted and called")
    elif has_log_method:
        score += 15
        feedback_parts.append("Method 'logOperation' exists but not called from main method")
    elif has_any_log_method:
        score += 10
        feedback_parts.append("A logging method was extracted (different name than 'logOperation')")
    else:
        # Check if repeated code was at least reduced
        println_count = calc_content.count('System.out.println')
        if println_count <= 6:  # Original has 12 println calls (3 per branch * 4 branches)
            score += 5
            feedback_parts.append(f"Some code deduplication done ({println_count} println calls remain)")
        else:
            feedback_parts.append("No method extraction performed")

    # --- Criterion 4: Compiles (25 pts) ---
    try:
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/classes/org/lable/oss/helloworld/Calculator.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)
        if magic == b'\xca\xfe\xba\xbe':
            score += 25
            feedback_parts.append("Build successful (Calculator.class verified)")
        else:
            feedback_parts.append("Calculator.class found but invalid")
    except Exception:
        feedback_parts.append("Build not completed (no .class files)")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task

        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description="Refactor Calculator.java in IntelliJ IDEA: rename method 'calc' to 'calculate', "
                           "rename parameters (x->firstOperand, y->secondOperand, o->operation), "
                           "extract repeated logging code into 'logOperation' method.",
            checklist_items=[
                "IntelliJ IDEA is open with the refactor-demo project loaded",
                "Calculator.java is open in the editor",
                "IntelliJ refactoring tools were used (Refactor menu or rename dialog visible)",
                "The method name was changed from 'calc' to 'calculate'",
                "Code structure shows an extracted helper method",
                "The project compiles without errors after refactoring",
            ]
        )
        if vlm_result:
            if vlm_result.get('vlm_passed'):
                score = min(score + 10, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Build success is mandatory - refactored code must compile
    build_successful = 'Build successful' in ' '.join(feedback_parts)

    # Must have build success AND good score to pass
    passed = score >= 70 and build_successful

    if not build_successful and score >= 50:
        feedback_parts.append("NOTE: Task incomplete - refactored code must compile")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
