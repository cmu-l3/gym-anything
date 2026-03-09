#!/usr/bin/env python3
"""
Verifier for refactor_sql_to_text_blocks task.

Criteria:
1. Tests Pass (40 pts): The Maven test suite passes (proving SQL syntax is valid).
2. Typo Fixed (30 pts): 'GROUP BY' is present, 'GROU BY' is absent.
3. Text Block Used (20 pts): The `\"\"\"` syntax is found in the source.
4. Formatting (10 pts): The query string spans multiple lines (contains newlines).

Anti-gaming:
- File must be modified.
"""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_refactor_sql_to_text_blocks(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    content = result.get('file_content', '')
    tests_passed = result.get('tests_passed', False)
    file_modified = result.get('file_modified', False)
    
    score = 0
    feedback = []

    # Check 0: Anti-gaming
    if not file_modified:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "No changes detected in ReportQuery.java. Task incomplete."
        }

    # Check 1: Tests Passed (40 pts)
    # This proves the SQL syntax is valid (meaning GROU BY was likely fixed)
    if tests_passed:
        score += 40
        feedback.append("Tests passed (SQL syntax valid)")
    else:
        feedback.append("Tests failed (SQL syntax invalid)")

    # Check 2: Typo Fix Verification (30 pts)
    # Specifically check for the keywords in the source code
    has_group_by = "GROUP BY" in content
    has_grou_by = "GROU BY" in content
    
    if has_group_by and not has_grou_by:
        score += 30
        feedback.append("Typo 'GROU BY' fixed to 'GROUP BY'")
    elif has_group_by and has_grou_by:
        # Maybe they added the fix but didn't remove the old one?
        score += 10
        feedback.append("Found 'GROUP BY' but 'GROU BY' is still present")
    elif not has_group_by:
        feedback.append("Did not find 'GROUP BY' in source code")

    # Check 3: Text Block Syntax (20 pts)
    # Look for """ (Java 15+ text block delimiter)
    if '"""' in content:
        score += 20
        feedback.append("Java Text Block syntax (\"\"\") used")
    else:
        feedback.append("Standard string literals used (Text Block \"\"\" not found)")

    # Check 4: Formatting (10 pts)
    # Extract the query content and check for newlines
    # Regex tries to find content between text block delimiters or standard quotes
    query_match = re.search(r'QUERY\s*=\s*"""(.*?)"""', content, re.DOTALL)
    if query_match:
        query_body = query_match.group(1)
        if '\n' in query_body.strip():
            score += 10
            feedback.append("SQL query formatted across multiple lines")
        else:
            feedback.append("Text block used but content is still on one line")
    else:
        # Fallback check if they didn't use text blocks but still split the string
        # e.g. "SELECT ... " + \n "FROM ..."
        if '\n' in content and 'QUERY' in content and not '"""' in content:
            # If they used concatenation with newlines, we give partial credit (5 pts)
            # But the instructions explicitly asked for Text Blocks
            score += 5
            feedback.append("Multi-line string found (concatenation), but Text Block preferred")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }