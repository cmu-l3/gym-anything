#!/usr/bin/env python3
"""
Verifier for the fix_genomic_qc_pipeline task.

Checks whether the agent identified and fixed 5 algorithmic bugs in the
genomics NGS processing pipeline.

Each fix is worth 20 points (total 100). Pass threshold: 60.
Also requires the output.json to have been generated during the task.
"""

import sys
import os
import json
import re
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_genomic_pipeline(traj, env_info, task_info):
    """
    Verify that the agent found and fixed all 5 pipeline bugs.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='genomic_verify_')

    try:
        result_src = "/tmp/genomic_pipeline_result.json"
        local_result = os.path.join(temp_dir, "genomic_pipeline_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not access result file: {str(e)}"
            }

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Result file not found or empty"
            }

        with open(local_result, 'r') as f:
            file_contents = json.load(f)

        score = 0
        feedback = []
        
        # Check meta information about output.json
        meta = file_contents.get("meta", {})
        output_exists = meta.get("output_json_exists", False)
        output_created = meta.get("output_json_created_during_task", False)
        
        if output_created:
            feedback.append("[+] output.json successfully generated during task")
        else:
            feedback.append("[-] output.json was NOT generated or updated during the task")

        # ── Bug 1: Phred Quality Score (fastq_parser.py) ──────────
        parser_src = file_contents.get("src/fastq_parser.py", "")
        if parser_src is None:
            feedback.append("[-] fastq_parser.py: file missing")
        else:
            still_uses_64 = bool(re.search(r'-\s*64', parser_src))
            uses_33 = bool(re.search(r'-\s*33', parser_src))
            
            if uses_33 and not still_uses_64:
                score += 20
                feedback.append("[+] fastq_parser.py: Phred+33 offset fixed (20/20)")
            else:
                feedback.append("[-] fastq_parser.py: still uses incorrect Phred offset (0/20)")

        # ── Bug 2: Reverse Complement (sequence_utils.py) ───────────
        seq_utils_src = file_contents.get("src/sequence_utils.py", "")
        if seq_utils_src is None:
            feedback.append("[-] sequence_utils.py: file missing")
        else:
            # We look for logic that replaces bases AND reverses
            has_reversal = bool(re.search(r'\[::-1\]|reversed\(', seq_utils_src))
            has_complement = bool(
                re.search(r'maketrans|replace|translate|dict|A.*T|C.*G', seq_utils_src)
            )
            
            if has_reversal and has_complement:
                score += 20
                feedback.append("[+] sequence_utils.py: reverse complement fixed (20/20)")
            elif has_complement:
                score += 10
                feedback.append("[~] sequence_utils.py: complements but does not reverse (10/20)")
            elif has_reversal:
                feedback.append("[-] sequence_utils.py: still only reverses without complementing (0/20)")
            else:
                feedback.append("[-] sequence_utils.py: reverse complement logic is incorrect (0/20)")

        # ── Bug 3: GC Content Case Sensitivity (sequence_utils.py) ─
        if seq_utils_src is None:
            pass # Already logged
        else:
            # Look for case-insensitivity fixes: .upper(), .lower(), or searching for 'g'/'c'
            is_case_insensitive = bool(
                re.search(r'\.upper\(\)|\.lower\(\)', seq_utils_src) or
                re.search(r"['\"]g['\"]|['\"]c['\"]", seq_utils_src, re.IGNORECASE) and re.search(r"['\"]g['\"]", seq_utils_src)
            )
            if is_case_insensitive:
                score += 20
                feedback.append("[+] sequence_utils.py: GC content case sensitivity fixed (20/20)")
            else:
                feedback.append("[-] sequence_utils.py: GC content calculation still case-sensitive (0/20)")

        # ── Bug 4: Translation 'N' Handling (translator.py) ───────────
        translator_src = file_contents.get("src/translator.py", "")
        if translator_src is None:
            feedback.append("[-] translator.py: file missing")
        else:
            # The buggy code uses 'break'
            still_has_break = bool(re.search(r"if\s+['\"]N['\"]\s+in\s+codon[^:]*:\s*\n\s*break", translator_src))
            # The fix should append 'X'
            appends_x = bool(re.search(r"append\(\s*['\"]X['\"]\s*\)|=\s*['\"]X['\"]", translator_src))
            
            if appends_x and not still_has_break:
                score += 20
                feedback.append("[+] translator.py: unknown 'N' codon handling fixed (20/20)")
            elif appends_x and still_has_break:
                score += 10
                feedback.append("[~] translator.py: handles 'X' but retains break logic (10/20)")
            else:
                feedback.append("[-] translator.py: still halts translation on unknown codons (0/20)")

        # ── Bug 5: 3' Quality Trimming (trimmer.py) ───────────────────
        trimmer_src = file_contents.get("src/trimmer.py", "")
        if trimmer_src is None:
            feedback.append("[-] trimmer.py: file missing")
        else:
            # Buggy: return seq[i:], qualities[i:]
            # Correct: return seq[:i], qualities[:i]
            still_returns_tail = bool(re.search(r'return\s+seq\[i:\],\s*qualities\[i:\]', trimmer_src))
            returns_head = bool(re.search(r'return\s+seq\[:i\],\s*qualities\[:i\]', trimmer_src))
            
            if returns_head and not still_returns_tail:
                score += 20
                feedback.append("[+] trimmer.py: 3' quality slicing fixed (20/20)")
            else:
                feedback.append("[-] trimmer.py: still retains low-quality tail instead of trimming (0/20)")

        # Final score calculation
        key_criteria_met = output_created
        passed = (score >= 60) and key_criteria_met

        if not key_criteria_met:
            feedback.append("\nFAILED: You must successfully run the pipeline and generate output.json to pass.")

        return {
            "passed": passed,
            "score": score,
            "feedback": "\n".join(feedback)
        }

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)