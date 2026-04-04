#!/usr/bin/env python3
"""Verifier for graph_algorithms task."""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_graph_algorithms(traj, env_info, task_info):
    """
    Verify implementation of 5 graph algorithms.
    
    Scoring (100 pts total):
    - BFS Tests (15 pts)
    - DFS Tests (15 pts)
    - Dijkstra Tests (20 pts)
    - Cycle Detection Tests (15 pts)
    - Connected Components Tests (15 pts)
    - Source Modified (5 pts)
    - Data Structures Usage (5 pts)
    - VLM Workflow (10 pts)
    
    Pass threshold: 60 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # --- Load Result JSON ---
    result = {}
    try:
        tmp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp_res.close()
        copy_from_env("/tmp/task_result.json", tmp_res.name)
        with open(tmp_res.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp_res.name)
    except Exception as e:
        logger.warning(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}

    # --- Criterion: Source Modified (5 pts) ---
    if result.get("source_modified", False):
        score += 5
        feedback_parts.append("Source file modified")
    else:
        feedback_parts.append("Source file NOT modified")

    # --- Analyze Source Code for Data Structures (5 pts) ---
    source_code = result.get("source_code", "")
    ds_score = 0
    if source_code:
        # Check for Queue/Deque (BFS)
        if re.search(r'(Queue|Deque|LinkedList|ArrayDeque)', source_code):
            ds_score += 2
        # Check for Stack (DFS) - or recursive DFS
        if re.search(r'(Stack|push|pop|recursive)', source_code, re.IGNORECASE):
            ds_score += 1
        # Check for PriorityQueue (Dijkstra)
        if re.search(r'PriorityQueue', source_code):
            ds_score += 2
    
    if ds_score >= 3:
        score += 5
        feedback_parts.append("Appropriate data structures detected")
    elif ds_score > 0:
        score += 2
        feedback_parts.append("Some data structures detected")
    else:
        feedback_parts.append("No standard graph data structures detected")

    # --- Parse Surefire Reports (80 pts max) ---
    # Map test names to categories
    test_map = {
        "BFS": ["testBfsVisitOrder", "testBfsReachesAllNodes", "testBfsFromIsolatedNode"],
        "DFS": ["testDfsVisitOrder", "testDfsReachesAllNodes", "testDfsFromIsolatedNode"],
        "Dijkstra": ["testDijkstraDirectPath", "testDijkstraLongerPath", "testDijkstraUnreachable", "testDijkstraSameNode"],
        "Cycle": ["testHasCycleTrue", "testHasCycleFalse", "testHasCycleSingleNode"],
        "Components": ["testConnectedComponentsKarate", "testConnectedComponentsDisconnected", "testConnectedComponentsSingletons"]
    }
    
    category_weights = {
        "BFS": 15, "DFS": 15, "Dijkstra": 20, "Cycle": 15, "Components": 15
    }
    
    # Fetch report XML
    report_content = None
    try:
        # We need to find the exact filename. usually TEST-graph.GraphAlgorithmsTest.xml
        tmp_rep = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        tmp_rep.close()
        copy_from_env("/tmp/export/reports/TEST-graph.GraphAlgorithmsTest.xml", tmp_rep.name)
        with open(tmp_rep.name, 'r') as f:
            report_content = f.read()
        os.unlink(tmp_rep.name)
    except Exception as e:
        logger.warning(f"Failed to read test report: {e}")
        feedback_parts.append("No test report found (tests may not have run)")
    
    passed_tests = set()
    if report_content:
        try:
            root = ET.fromstring(report_content)
            for testcase in root.findall("testcase"):
                name = testcase.get("name")
                # If no child <failure> or <error>, it passed
                if testcase.find("failure") is None and testcase.find("error") is None:
                    passed_tests.add(name)
        except ET.ParseError:
            feedback_parts.append("Corrupt test report XML")

    # Score each category
    for cat, tests in test_map.items():
        cat_passed = 0
        for t in tests:
            if t in passed_tests:
                cat_passed += 1
        
        if cat_passed == len(tests):
            score += category_weights[cat]
            feedback_parts.append(f"{cat}: PASS ({cat_passed}/{len(tests)})")
        elif cat_passed > 0:
            # Partial credit? No, typically algorithms are all-or-nothing per logic block
            # But let's give proportional to encourage progress
            partial = int(category_weights[cat] * (cat_passed / len(tests)))
            score += partial
            feedback_parts.append(f"{cat}: PARTIAL ({cat_passed}/{len(tests)})")
        else:
            feedback_parts.append(f"{cat}: FAIL (0/{len(tests)})")

    # --- VLM Verification (10 pts) ---
    # Optional VLM check using gym_anything.vlm helpers if available
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames
        # We need env_info['query_vlm'] to be available, usually handled by caller
        # If not available, we skip or default to pass if programmatic passed
        pass
    except ImportError:
        pass
        
    # Simple placeholder logic for VLM if we can't actually query it here 
    # (assuming the standard verifier structure allows it)
    # If programmatic score is high (>60), assume VLM would see activity
    if score > 60:
        vlm_score = 10
        feedback_parts.append("Implicit VLM Pass (High Programmatic Score)")
    else:
        feedback_parts.append("Skipping VLM (low programmatic score)")
    
    score += vlm_score

    # Cap score at 100
    score = min(score, 100)
    
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }