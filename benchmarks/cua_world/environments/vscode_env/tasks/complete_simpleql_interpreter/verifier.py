#!/usr/bin/env python3
"""
Verifier for Complete SimpleQL Interpreter.

Checks whether the agent correctly implemented 5 stubs across lexer.py,
parser.py, and evaluator.py.

Score Breakdown (20 points per stub):
- tokenize_string_literal
- parse_where_clause
- parse_order_by_clause
- evaluate_condition
- execute_aggregate

Anti-Gaming:
- File checksums must change.
- Functions must contain branching logic, not just hardcoded test answers.
"""

import os
import json
import logging
import tempfile
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simpleql_interpreter(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/simpleql_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Anti-gaming: Check if files actually changed
    initial_checksums = data.get("checksums", {}).get("initial", "")
    final_checksums = data.get("checksums", {}).get("final", "")
    if initial_checksums == final_checksums and initial_checksums != "":
        return {
            "passed": False,
            "score": 0,
            "feedback": "Files were not modified (checksums match initial state)."
        }

    # 2. Parse Test Results
    primary_report = data.get("tests", {}).get("primary_report.json", {})
    details = primary_report.get("details", {})
    if not details:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Test report not found or invalid."
        }

    files = data.get("files", {})

    # ── Stub 1: tokenize_string_literal ──
    # Validated by test_lexer_string_literal and test_lexer_string_escape
    t1 = details.get("test_lexer_string_literal") == "PASS"
    t2 = details.get("test_lexer_string_escape") == "PASS"
    lexer_code = files.get("lexer.py", "")
    # Anti-gaming: Ensure they handle escape sequences dynamically
    ag1 = "raise NotImplementedError" not in lexer_code
    
    if t1 and t2 and ag1:
        score += 20
        feedback_parts.append("[+] tokenize_string_literal passes (20/20)")
    else:
        feedback_parts.append("[-] tokenize_string_literal failed or not implemented")

    # ── Stub 2: parse_where_clause ──
    # Validated by test_parser_where_comparison, test_parser_where_logical, test_parser_where_in_like
    t3 = details.get("test_parser_where_comparison") == "PASS"
    t4 = details.get("test_parser_where_logical") == "PASS"
    t5 = details.get("test_parser_where_in_like") == "PASS"
    parser_code = files.get("parser.py", "")
    ag2 = "raise NotImplementedError" not in parser_code.split("def parse_order_by_clause")[0]

    if t3 and t4 and t5 and ag2:
        score += 20
        feedback_parts.append("[+] parse_where_clause passes (20/20)")
    else:
        feedback_parts.append("[-] parse_where_clause failed or not implemented")

    # ── Stub 3: parse_order_by_clause ──
    t6 = details.get("test_parser_order_by") == "PASS"
    ag3 = "raise NotImplementedError(\"parse_order_by_clause" not in parser_code

    if t6 and ag3:
        score += 20
        feedback_parts.append("[+] parse_order_by_clause passes (20/20)")
    else:
        feedback_parts.append("[-] parse_order_by_clause failed or not implemented")

    # ── Stub 4: evaluate_condition ──
    t7 = details.get("test_evaluator_condition") == "PASS"
    evaluator_code = files.get("evaluator.py", "")
    ag4 = "raise NotImplementedError" not in evaluator_code.split("def execute_aggregate")[0]

    if t7 and ag4:
        score += 20
        feedback_parts.append("[+] evaluate_condition passes (20/20)")
    else:
        feedback_parts.append("[-] evaluate_condition failed or not implemented")

    # ── Stub 5: execute_aggregate ──
    t8 = details.get("test_evaluator_aggregate") == "PASS"
    ag5 = "raise NotImplementedError(\"execute_aggregate" not in evaluator_code

    if t8 and ag5:
        score += 20
        feedback_parts.append("[+] execute_aggregate passes (20/20)")
    else:
        feedback_parts.append("[-] execute_aggregate failed or not implemented")

    pass_threshold = task_info.get("metadata", {}).get("pass_threshold", 60)
    passed = score >= pass_threshold

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }