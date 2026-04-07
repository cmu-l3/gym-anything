#!/usr/bin/env python3
"""
Verifier for the repair_historical_nlp_pipeline task.

Checks whether the agent identified and fixed 5 bugs in the NLP
pipeline modules, without modifying the test suite.

Scoring:
- Bug 1 (Diacritics): 15 pts
- Bug 2 (Hex Entities): 15 pts
- Bug 3 (Hyphens): 15 pts
- Bug 4 (Sentence Split): 15 pts
- Bug 5 (BPE Sort): 15 pts
- VLM Trajectory (Interacted with code/tests): 25 pts
Total: 100 points. Pass threshold: 70.
"""

import os
import json
import re
import logging
import tempfile
from gym_anything.vlm import sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_nlp_pipeline(traj, env_info, task_info):
    """
    Verify that the agent fixed the NLP pipeline bugs.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='nlp_verify_')
    local_result = os.path.join(temp_dir, "nlp_pipeline_result.json")

    try:
        copy_from_env("/tmp/nlp_pipeline_result.json", local_result)
        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty"}

        with open(local_result, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to process result file: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    files = result_data.get("files", {})
    score = 0
    feedback = []

    # ── Anti-gaming check: Did they tamper with the tests? ──
    initial_hash = result_data.get("initial_test_hash")
    final_hash = result_data.get("final_test_hash")
    if initial_hash != final_hash:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Test suite files were modified. Modifying tests to pass is not permitted."
        }

    # ── Bug 1: Diacritics (normalizer.py) [15 pts] ──
    norm_src = files.get("pipeline/normalizer.py", "")
    if norm_src and "text.encode('ascii'" not in norm_src:
        if "façade" in files.get("pytest_output.txt", "") and "Diacritics were destroyed" not in files.get("pytest_output.txt", ""):
            # We can also check if pytest output indicates test_diacritics_preserved passed
            pass
        score += 15
        feedback.append("[+] Bug 1: ASCII encoding removed, preserving diacritics (15/15)")
    else:
        feedback.append("[-] Bug 1: ASCII encoding still destroying diacritics (0/15)")

    # ── Bug 2: Hex Entities (normalizer.py) [15 pts] ──
    if norm_src:
        # Check if the regex was fixed (e.g. &#?[a-zA-Z0-9]+;) or html.unescape is applied directly on text
        has_better_regex = bool(re.search(r'&#?\[?[a-zA-Z0-9]+\]?;?', norm_src))
        has_direct_unescape = bool(re.search(r'html\.unescape\s*\(\s*text\s*\)', norm_src))
        if has_better_regex or has_direct_unescape:
            score += 15
            feedback.append("[+] Bug 2: HTML unescape applied correctly for hex entities (15/15)")
        else:
            feedback.append("[-] Bug 2: Hex entity regex not properly fixed (0/15)")
    else:
        feedback.append("[-] Bug 2: normalizer.py missing (0/15)")

    # ── Bug 3: Line-wrap hyphens (cleaner.py) [15 pts] ──
    clean_src = files.get("pipeline/cleaner.py", "")
    if clean_src:
        # Looking for a newline constraint instead of just '\s+'
        if r'-\n' in clean_src or r'-\r\n' in clean_src or 'replace("-\\n", "")' in clean_src or r'-\s*\n' in clean_src:
            score += 15
            feedback.append("[+] Bug 3: Line-wrap hyphens correctly handled via newline constraint (15/15)")
        else:
            feedback.append("[-] Bug 3: Line-wrap hyphen removal still too greedy (0/15)")
    else:
        feedback.append("[-] Bug 3: cleaner.py missing (0/15)")

    # ── Bug 4: Sentence Splitter (sentence_splitter.py) [15 pts] ──
    split_src = files.get("pipeline/sentence_splitter.py", "")
    if split_src:
        has_negative_lookbehind = r'(?<!Mr)(?<!Mrs)' in split_src or r'(?<!\bMr)(?<!\bMrs)' in split_src or r'(?<!Mr)' in split_src
        has_custom_rule = 'Mr.' not in split_src and 'replace' in split_src  # Alt fix approach
        if has_negative_lookbehind or has_custom_rule:
            score += 15
            feedback.append("[+] Bug 4: Sentence splitter updated to ignore abbreviations (15/15)")
        else:
            feedback.append("[-] Bug 4: Sentence splitter still breaks on honorifics (0/15)")
    else:
        feedback.append("[-] Bug 4: sentence_splitter.py missing (0/15)")

    # ── Bug 5: BPE Tokenizer (bpe_tokenizer.py) [15 pts] ──
    bpe_src = files.get("pipeline/bpe_tokenizer.py", "")
    if bpe_src:
        if "lambda x: x[1]" in bpe_src or "lambda x:x[1]" in bpe_src:
            score += 15
            feedback.append("[+] Bug 5: BPE merges correctly sorted by frequency score (15/15)")
        else:
            feedback.append("[-] Bug 5: BPE merges still sorting by token string alphabetically (0/15)")
    else:
        feedback.append("[-] Bug 5: bpe_tokenizer.py missing (0/15)")

    # ── VLM Trajectory Verification [25 pts] ──
    if query_vlm:
        frames = sample_trajectory_frames(traj, n=5)
        if frames:
            prompt = """You are evaluating an agent solving a Python debugging task in VS Code.
Look at these sampled frames from the agent's screen recording.
Determine if the agent:
1. Navigated the file system and opened Python code files.
2. Edited Python source code to fix bugs.
3. Used the integrated terminal to run tests (e.g., pytest).

Return JSON:
{
    "interacted_with_code": true/false,
    "ran_terminal_commands": true/false
}
"""
            vlm_response = query_vlm(images=frames, prompt=prompt)
            if vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('interacted_with_code') and parsed.get('ran_terminal_commands'):
                    score += 25
                    feedback.append("[+] VLM confirmed active interaction with code and terminal (25/25)")
                elif parsed.get('interacted_with_code'):
                    score += 15
                    feedback.append("[~] VLM confirmed code editing but not test execution (15/25)")
                else:
                    feedback.append("[-] VLM could not confirm agent actively completed the task workflow (0/25)")
            else:
                feedback.append("[-] VLM verification failed to process.")
        else:
            feedback.append("[-] No trajectory frames available for VLM verification.")
    else:
        feedback.append("[-] VLM verification unavailable in env_info.")

    # E2E test context summary
    e2e_output = files.get("output/cleaned.jsonl")
    if e2e_output and "façade" in e2e_output and "well-known" in e2e_output:
        feedback.append("\n[*] End-to-End run produced high-quality cleaned text output.")

    passed = score >= task_info.get("metadata", {}).get("pass_threshold", 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }