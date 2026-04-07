#!/usr/bin/env python3
"""
Verifier for plsql_sql_injection_remediation task.

Scoring:
- Package Valid: 10 pts
- Search Functional: 15 pts (Returns correct rows)
- Search Secure: 25 pts (Bind variables used, injection fails)
- Sort Functional: 15 pts (Returns rows, doesn't crash on valid input)
- Sort Secure: 25 pts (Uses DBMS_ASSERT or Whitelist, rejects injection)
- File Exported: 10 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_plsql_sql_injection_remediation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
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

    score = 0
    feedback_parts = []
    
    # 1. Package Valid (10)
    if result.get("package_valid"):
        score += 10
        feedback_parts.append("Package compiles (10/10)")
    else:
        feedback_parts.append("Package invalid (0/10)")

    # 2. Search Functional (15)
    if result.get("search_functional"):
        score += 15
        feedback_parts.append("Search functional (15/15)")
    else:
        feedback_parts.append("Search broken (0/15)")

    # 3. Search Secure (25)
    # Must pass the injection test AND (Static check: have USING clause)
    if result.get("search_secure"):
        if result["source_checks"].get("using_clause"):
            score += 25
            feedback_parts.append("Search secure & uses Binds (25/25)")
        else:
            # Passed injection test but didn't find USING? Maybe sanitized manually?
            # Partial credit if functional test passed
            score += 15
            feedback_parts.append("Search secure but no Bind vars detected? (15/25)")
    else:
        feedback_parts.append("Search vulnerable to injection (0/25)")

    # 4. Sort Functional (15)
    if result.get("sort_functional"):
        score += 15
        feedback_parts.append("Sort functional (15/15)")
    else:
        feedback_parts.append("Sort broken (0/15)")

    # 5. Sort Secure (25)
    # Must use DBMS_ASSERT or Whitelist.
    # We check the flags set by the internal verifier.
    source_checks = result.get("source_checks", {})
    secure_method_used = source_checks.get("dbms_assert") or source_checks.get("explicit_whitelist")
    
    if result.get("sort_secure"):
        # If the DB raised ORA-44003 or similar
        score += 25
        feedback_parts.append("Sort secure (Validation active) (25/25)")
    elif secure_method_used:
        # Static analysis found the right tools, but dynamic test might have been ambiguous
        # (e.g. whitelist logic didn't raise error but defaulted to safe sort)
        score += 25
        feedback_parts.append("Sort secure (Code analysis) (25/25)")
    else:
        feedback_parts.append("Sort vulnerable or no validation found (0/25)")

    # 6. File Exported (10)
    if result.get("file_exported"):
        score += 10
        feedback_parts.append("File exported (10/10)")
    else:
        feedback_parts.append("No export file (0/10)")

    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result.get("errors", [])
    }