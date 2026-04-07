#!/usr/bin/env python3
"""
Verifier for the fix_markdown_docs_builder task.

Evaluates 5 distinct bugs in a Node.js documentation builder.
To reduce non-determinism, we evaluate both the actual HTML artifacts 
(generated directly by the export script executing the agent's code) and
the Javascript source codebase itself.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_docs_builder(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    html_files = result.get('html_files', {})
    src_files = result.get('src_files', {})
    build_log = result.get('build_log', '')

    score = 0
    feedback = []

    # -------------------------------------------------------------------------
    # Bug 1: Async Race Condition (src/index.js)
    # -------------------------------------------------------------------------
    src_index = src_files.get('src/index.js', '')
    
    # Original buggy pattern uses files.forEach(async (file) => { ... })
    has_foreach_async = bool(re.search(r'files\.forEach\s*\(\s*async', src_index))
    
    # Valid fixes: Promise.all, for...of, standard for loop
    fixed_async = not has_foreach_async and (
        'Promise.all' in src_index or
        bool(re.search(r'for\s*\([^)]+of\s', src_index)) or
        bool(re.search(r'for\s*\(let\s+[a-zA-Z0-9_]+\s*=\s*0', src_index))
    )

    if fixed_async:
        score += 20
        feedback.append("[+] Async race condition fixed (Iterators/Promises awaited correctly)")
    else:
        feedback.append("[-] Async race condition persists (forEach used with un-awaited async callbacks)")

    # -------------------------------------------------------------------------
    # Bug 2: Greedy Regex Swallowing Frontmatter (src/parser.js)
    # -------------------------------------------------------------------------
    src_parser = src_files.get('src/parser.js', '')
    middleware_html = html_files.get('advanced/middleware.html', '')
    
    # Expected content from the second horizontal rule:
    expected_note = 'important note after a horizontal rule'
    fixed_greedy = expected_note in middleware_html
    
    # Fallback to source check if output HTML wasn't generated due to Bug 1
    if not fixed_greedy and ('[\\s\\S]*?' in src_parser or '(.*?)' in src_parser):
        fixed_greedy = True

    if fixed_greedy:
        score += 20
        feedback.append("[+] Frontmatter regex fixed (non-greedy, content preserved)")
    else:
        feedback.append("[-] Frontmatter regex still greedy (content after second horizontal rule swallowed)")

    # -------------------------------------------------------------------------
    # Bug 3: Missing Global Flag on Wiki-Links (src/parser.js)
    # -------------------------------------------------------------------------
    # The file has two links on the same line: "advanced/routing" and "getting started"
    fixed_wiki = 'getting%20started.html' in middleware_html or 'getting started.html' in middleware_html
    
    # Fallback source check looking for the global 'g' flag on the wiki regex
    if not fixed_wiki and re.search(r'wikiRegex\s*=\s*/[^/]+/g', src_parser):
        fixed_wiki = True

    if fixed_wiki:
        score += 20
        feedback.append("[+] Wiki-link global regex fixed (all links per line parsed)")
    else:
        feedback.append("[-] Wiki-link regex missing global flag (only first link parsed)")

    # -------------------------------------------------------------------------
    # Bug 4: Validator Missing URL Decoding (src/validator.js)
    # -------------------------------------------------------------------------
    src_validator = src_files.get('src/validator.js', '')
    fixed_validator = False
    
    # The log should not report DEAD LINKS if decoded properly
    # Check that execution actually happened ('Validating internal links...')
    if build_log and 'DEAD LINK in' not in build_log and 'Validation failed' not in build_log and 'Validating internal links' in build_log:
        fixed_validator = True
    elif 'decodeURIComponent' in src_validator or 'decodeURI' in src_validator:
        fixed_validator = True

    if fixed_validator:
        score += 20
        feedback.append("[+] Validator URL decoding fixed (No false positive dead links for spaces)")
    else:
        feedback.append("[-] Validator still reports false dead links due to lack of URI decoding")

    # -------------------------------------------------------------------------
    # Bug 5: Nested Asset Depth Calculation (src/assets.js)
    # -------------------------------------------------------------------------
    src_assets = src_files.get('src/assets.js', '')
    routing_html = html_files.get('advanced/routing.html', '')
    
    fixed_assets = '../assets/logo.png' in routing_html and '../../assets/logo.png' not in routing_html
    
    # Original buggy code subtracts 1 (includes root docs/ folder as nesting depth). Fix is subtracting 2.
    if not fixed_assets and ('length - 2' in src_assets or 'length -2' in src_assets or "replace('docs/'" in src_assets):
        fixed_assets = True

    if fixed_assets:
        score += 20
        feedback.append("[+] Asset relative path depth fixed")
    else:
        feedback.append("[-] Asset relative path depth still incorrect (calculating root folder as depth)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }