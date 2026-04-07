#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_fix_genome_assembler(traj, env_info, task_info):
    """
    Verify the genome assembler bugs are fixed.
    
    Criteria:
    1. Bug 1 (IO): test_read_fasta_count passes (30 pts)
    2. Bug 2 (Seq): test_reverse_complement_simple passes (30 pts)
    3. Bug 3 (Overlap): test_merge_simple_overlap passes (30 pts)
    4. No Regressions: All tests pass (10 pts)
    
    Also verifies via functional output (assembling the phiX reads correctly).
    """
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    task_name = "fix_genome_assembler"
    result_path = f"/tmp/{task_name}_result.json"

    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=".json") as tmp:
            tmp_path = tmp.name
        try:
            copy_from_env(result_path, tmp_path)
            with open(tmp_path, "r") as f:
                result = json.load(f)
        finally:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback = []

    # Check functional success (strongest signal)
    functional = result.get("functional_success", False)
    all_tests = result.get("all_tests_pass", False)
    
    # We can infer specific fixes from the functional result + tests passed count,
    # but the export script doesn't export per-test results individually in JSON 
    # (only total counts and heuristcs).
    # Ideally, we'd use junitxml for precise per-test data, but total pass count is a decent proxy
    # if we assume standard failure modes.
    
    # Bug 1: IO Fix
    # If the parser drops the last read, `reads` count in main.py is 2 instead of 3.
    # The consensus would be shorter or missing the last chunk.
    # Test count: test_read_fasta_count would fail.
    # Since we don't have per-test names in JSON, we rely on "all_tests_pass" 
    # and the heuristics.
    
    # Let's trust "all_tests_pass" heavily, as 15/15 means all bugs fixed.
    
    if all_tests:
        score = 100
        feedback.append("All tests passed. Assembler is fully functional.")
    else:
        # Partial credit based on heuristics and output
        
        # Bug 1 Heuristic (code check + functional)
        if result.get("io_bug_fixed_heuristic", False):
            score += 30
            feedback.append("IO Bug fixed (code heuristic).")
        else:
            feedback.append("IO Bug likely not fixed.")
            
        # Bug 2 Heuristic
        if result.get("seq_bug_fixed_heuristic", False):
            score += 30
            feedback.append("Reverse Complement Bug fixed (code heuristic).")
        else:
            feedback.append("Reverse Complement Bug likely not fixed.")
            
        # Bug 3 Heuristic
        if result.get("overlap_bug_fixed_heuristic", False):
            score += 30
            feedback.append("Overlap Merge Bug fixed (code heuristic).")
        else:
            feedback.append("Overlap Merge Bug likely not fixed.")

        # If functional success is true but tests fail (weird state), give credit
        if functional and score < 90:
            score = 90
            feedback.append("Assembler output is correct despite some test failures.")

    # Validation of functional output
    actual = result.get("actual_consensus", "")
    expected = result.get("expected_consensus", "")
    
    if len(actual) != len(expected):
        feedback.append(f"Consensus length mismatch: {len(actual)} vs {len(expected)}")
    
    passed = score >= 90
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }