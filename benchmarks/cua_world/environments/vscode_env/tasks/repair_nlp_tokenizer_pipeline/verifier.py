#!/usr/bin/env python3
"""
Verifier for the repair_nlp_tokenizer_pipeline task.

Performs static analysis on the exported code files to check if the 5 injected 
bugs in the custom BPE tokenizer pipeline were identified and resolved.

Each fix is worth 20 points (total 100, pass threshold 60).
"""
import sys
import os
import json
import re
import logging
import tempfile
import shutil

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_tokenizer_pipeline(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='tokenizer_verify_')
    
    try:
        result_src = "/tmp/tokenizer_result.json"
        local_result = os.path.join(temp_dir, "tokenizer_result.json")
        
        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not access result file: {e}"}

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty"}

        with open(local_result, 'r') as f:
            file_contents = json.load(f)

        score = 0
        feedback = []

        # ── Bug 1: Lossy Whitespace (pre_tokenizers.py) ──────────
        pt_content = file_contents.get("tokenizer/pre_tokenizers.py", "")
        if pt_content and not pt_content.startswith("ERROR"):
            has_strip_split = "text.strip().split()" in pt_content
            # Check if whitespace handling was added (e.g. \s+, \S+, matching spaces)
            handles_whitespace = bool(re.search(r'\\s\+', pt_content) or re.search(r'\\S\+', pt_content) or "split(' ')" in pt_content or 'split(" ")' in pt_content)
            
            if not has_strip_split and handles_whitespace:
                score += 20
                feedback.append("[+] pre_tokenizers.py: Whitespace preservation fixed (20/20)")
            elif not has_strip_split:
                score += 10
                feedback.append("[~] pre_tokenizers.py: strip().split() removed, but whitespace handling strategy is unclear (10/20)")
            else:
                feedback.append("[-] pre_tokenizers.py: Still uses strip().split() which destroys whitespace (0/20)")
        else:
            feedback.append("[-] pre_tokenizers.py: File missing or unable to read")

        # ── Bug 2: CJK Bloat (pre_tokenizers.py) ──────────
        if pt_content and not pt_content.startswith("ERROR"):
            # Original code grouped \w+ tightly which is fatal for CJK
            has_buggy_w_plus = r"\w+|[^\w\s]+" in pt_content or r"\\w+\|\[\^\\w\\s\]\+" in pt_content
            has_general_w_plus = r"\w+" in pt_content

            if not has_buggy_w_plus and not has_general_w_plus:
                score += 20
                feedback.append("[+] pre_tokenizers.py: CJK massive grouping mitigated (20/20)")
            elif not has_buggy_w_plus:
                score += 20
                feedback.append("[+] pre_tokenizers.py: Regex modified correctly to split CJK (20/20)")
            else:
                feedback.append("[-] pre_tokenizers.py: Still uses raw \\w+ grouping which bloats CJK vocabulary (0/20)")

        # ── Bug 3: Sub-optimal BPE merge (bpe_builder.py) ──────────
        bpe_content = file_contents.get("tokenizer/bpe_builder.py", "")
        if bpe_content and not bpe_content.startswith("ERROR"):
            has_max = "max(" in bpe_content and "key=" in bpe_content
            has_sort = "sorted(" in bpe_content or "sort(" in bpe_content
            has_list_0 = "list(pair_counts.keys())[0]" in bpe_content
            
            if (has_max or has_sort) and not has_list_0:
                score += 20
                feedback.append("[+] bpe_builder.py: Optimal pair selection using max/sort implemented (20/20)")
            elif not has_list_0:
                score += 10
                feedback.append("[~] bpe_builder.py: First-element selection removed, but max() logic not explicitly found (10/20)")
            else:
                feedback.append("[-] bpe_builder.py: Still selects the arbitrary first pair instead of the most frequent (0/20)")
        else:
            feedback.append("[-] bpe_builder.py: File missing or unable to read")

        # ── Bug 4: Regex metacharacter injection (bpe_builder.py) ──────────
        if bpe_content and not bpe_content.startswith("ERROR"):
            has_escape = "re.escape" in bpe_content
            if has_escape:
                score += 20
                feedback.append("[+] bpe_builder.py: Regex metacharacters escaped safely (20/20)")
            else:
                feedback.append("[-] bpe_builder.py: Regex metacharacters are unescaped (0/20)")

        # ── Bug 5: Invalid UTF-8 Decoding (decoder.py) ──────────
        dec_content = file_contents.get("tokenizer/decoder.py", "")
        if dec_content and not dec_content.startswith("ERROR"):
            has_errors_replace = "errors='replace'" in dec_content or 'errors="replace"' in dec_content
            has_errors_ignore = "errors='ignore'" in dec_content or 'errors="ignore"' in dec_content
            
            if has_errors_replace or has_errors_ignore:
                score += 20
                feedback.append("[+] decoder.py: Invalid UTF-8 bytes handled safely without crashing (20/20)")
            else:
                feedback.append("[-] decoder.py: Still crashes on invalid UTF-8 bytes (0/20)")
        else:
            feedback.append("[-] decoder.py: File missing or unable to read")

        passed = score >= 60
        
        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }
        
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)