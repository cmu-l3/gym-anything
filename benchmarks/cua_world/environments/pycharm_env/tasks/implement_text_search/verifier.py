#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_implement_text_search(traj, env_info, task_info):
    """
    Verify text search engine implementation.
    
    Scoring:
    - 20 pts per module (tokenizer, indexer, scorer, query, searcher)
    - Proportional score based on passing tests in each module
    - 0 points if test files were modified
    
    Modules & Test Counts:
    - Tokenizer: 5 tests
    - Indexer: 4 tests
    - Scorer: 3 tests
    - Query: 4 tests
    - Searcher: 3 tests
    (Counts based on setup_task.sh)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Retrieve result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 1. Anti-Gaming Checks
    if result.get("tests_modified", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Test files were modified. You must implement the engine, not change tests."
        }
        
    if not result.get("source_modified", False):
         return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: No source code modifications detected."
        }

    # 2. Calculate Module Scores
    # Weights per module (total 100)
    MODULE_WEIGHTS = 20
    
    # Expected test counts (from setup_task.sh generation)
    # tokenizer: 5, indexer: 4, scorer: 3, query: 4, searcher: 3
    # Total tests: 19 (Note: I simplified the setup script tests slightly from the design doc for brevity, 
    # matching the implementation in setup_task.sh)
    EXPECTED_COUNTS = {
        "tokenizer": 5,
        "indexer": 4,
        "scorer": 3,
        "query": 4,
        "searcher": 3
    }
    
    module_results = result.get("module_results", {})
    total_score = 0
    feedback_parts = []
    
    all_modules_pass = True
    
    for mod, expected in EXPECTED_COUNTS.items():
        passed = module_results.get(mod, 0)
        # Cap passed at expected (in case of extra tests running)
        passed = min(passed, expected)
        
        # Calculate proportional score
        if expected > 0:
            mod_score = (passed / expected) * MODULE_WEIGHTS
        else:
            mod_score = 0
            
        total_score += mod_score
        
        status = "PASS" if passed == expected else "FAIL"
        feedback_parts.append(f"{mod}: {passed}/{expected} ({status})")
        
        if passed < expected:
            all_modules_pass = False

    # Round score
    final_score = int(total_score)
    
    # 3. Determine Pass/Fail
    # Threshold 60 defined in task.json
    passed_task = final_score >= 60

    return {
        "passed": passed_task,
        "score": final_score,
        "feedback": f"Score: {final_score}/100. Details: " + ", ".join(feedback_parts)
    }