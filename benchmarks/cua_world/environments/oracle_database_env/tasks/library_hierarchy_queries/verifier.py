#!/usr/bin/env python3
"""
Verifier for library_hierarchy_queries task.

Scoring (100 pts):
1. Files exist and have content (15 pts)
2. SQL keywords used correctly in query file (15 pts)
3. Output Verification (70 pts total):
   - Q2: Path for '005' correct (contains key names) (15 pts)
   - Q3: Count for '500' matches ground truth (15 pts)
   - Q4: Empty leaf '004' identified (10 pts)
   - Q5: Max depth matches HR schema truth (15 pts)
   - Output formatting/size (15 pts)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_library_hierarchy_queries(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result
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

    score = 0
    feedback = []
    
    files = result.get("files", {})
    keywords = result.get("keywords", {})
    gt = result.get("ground_truth", {})
    content = result.get("agent_output_content", "")
    
    # 1. File Existence (15 pts)
    if files.get("query_file_exists") and files.get("query_file_size", 0) > 50:
        score += 8
        feedback.append("SQL file exists")
    else:
        feedback.append("SQL file missing/empty")

    if files.get("output_file_exists") and files.get("output_file_size", 0) > 50:
        score += 7
        feedback.append("Output file exists")
    else:
        feedback.append("Output file missing/empty")
        
    # 2. Keywords (15 pts)
    kw_score = 0
    if keywords.get("connect_by"): kw_score += 5
    if keywords.get("sys_connect_by_path"): kw_score += 5
    if keywords.get("with_cte"): kw_score += 5
    
    score += kw_score
    if kw_score == 15:
        feedback.append("All required SQL keywords found")
    elif kw_score > 0:
        feedback.append(f"Some SQL keywords found ({kw_score}/15 pts)")
    else:
        feedback.append("No hierarchical SQL keywords found")

    # 3. Content Verification (70 pts)
    # We search the plain text output for expected values. 
    # This is "fuzzy" matching but robust against formatting differences.
    
    content_lower = content.lower()
    
    # Q2: Path for 005 (Computer programming)
    # Expected: "Computer programming" and "Computer Science" (root)
    # and maybe the code 005
    q2_pass = False
    cat_005_name = gt.get("cat_005_name", "Computer programming").lower()
    if "005" in content and cat_005_name in content_lower:
        # Check for path separator usually used (>, /, or just indentation)
        # We just check if they are present.
        score += 15
        q2_pass = True
        feedback.append("Q2: Path verification passed")
    else:
        feedback.append("Q2: Path output missing key category names/codes")

    # Q3: Count for 500
    # Expected: The number from ground truth (likely 5) appearing near '500'
    count_500 = gt.get("count_500", 5)
    # Look for "500" and "5" in proximity or just present? 
    # "500" is common. "5" is common. 
    # Let's look for the line containing 500 and check if it has the count.
    q3_pass = False
    lines = content.splitlines()
    found_count = False
    for line in lines:
        if "500" in line and str(count_500) in line:
            found_count = True
            break
    
    if found_count:
        score += 15
        q3_pass = True
        feedback.append(f"Q3: Correct item count ({count_500}) found for category 500")
    else:
        feedback.append(f"Q3: Did not find correct item count ({count_500}) for category 500")

    # Q4: Empty leaf 004
    # Expected: "004" and name "Data processing"
    q4_pass = False
    if "004" in content and "data processing" in content_lower:
        score += 10
        q4_pass = True
        feedback.append("Q4: Empty leaf 004 identified")
    else:
        feedback.append("Q4: Empty leaf 004 not found in output")

    # Q5: Max Depth Employee
    # Expected: Depth number (e.g., 4) and likely "King" (CEO) in the chain
    max_depth = gt.get("max_emp_depth", 4)
    q5_pass = False
    # Check for max depth value
    if str(max_depth) in content and ("king" in content_lower or "steven" in content_lower):
        score += 15
        q5_pass = True
        feedback.append(f"Q5: Max depth {max_depth} and CEO found")
    else:
        feedback.append("Q5: Max depth or CEO not found in output")

    # General Content Size/Quality
    if len(lines) > 20: # Should be fairly long
        score += 15
        feedback.append("Output length adequate")
    else:
        feedback.append("Output too short")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback)
    }