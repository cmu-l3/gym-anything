#!/usr/bin/env python3
"""
Verifier for child_welfare_case_plan task.
Verifies ODT document structure, formatting, and content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_child_welfare_case_plan(traj, env_info, task_info):
    """
    Verify the Family Case Plan document.
    
    Criteria:
    1. File exists and is valid ODT (> 8KB)
    2. Proper Heading 1 usage (>= 7 sections)
    3. Proper Heading 2 usage (>= 5 subsections)
    4. Tables present (>= 3)
    5. Table of Contents present
    6. Page numbers present
    7. Content accuracy (keywords)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    min_size = metadata.get('min_file_size_kb', 8) * 1024

    # Copy result from container
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
    
    # 1. File Existence & Size (Gate)
    if not result.get("file_exists", False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAILED: Output file 'Martinez_Family_Case_Plan.odt' not found."
        }
    
    file_size = result.get("file_size_bytes", 0)
    if file_size < min_size:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"FAILED: File size too small ({file_size} bytes). Expected > {min_size} bytes. Document likely empty or incomplete."
        }
    
    score += 5 # Basic file existence points
    feedback_parts.append("File exists and has content")

    # 2. Heading Structure (30 pts)
    # Expecting: Family ID, Case Info, Reason, Assessment, Goals, Services, Visitation, Review, Signatures (9 possible)
    h1_count = result.get("heading1_count", 0)
    if h1_count >= 7:
        score += 20
        feedback_parts.append(f"Heading 1 structure good ({h1_count} sections)")
    elif h1_count >= 3:
        score += 10
        feedback_parts.append(f"Heading 1 structure partial ({h1_count} sections)")
    else:
        feedback_parts.append(f"Missing Heading 1 styles (found {h1_count})")

    h2_count = result.get("heading2_count", 0)
    if h2_count >= 5:
        score += 10
        feedback_parts.append(f"Heading 2 structure good ({h2_count} subsections)")
    elif h2_count >= 2:
        score += 5
        feedback_parts.append(f"Heading 2 structure partial ({h2_count})")
    else:
        feedback_parts.append(f"Missing Heading 2 styles (found {h2_count})")

    # 3. Tables (20 pts)
    # Expecting: Goals, Services, Visitation (3 tables)
    table_count = result.get("table_count", 0)
    if table_count >= 3:
        score += 20
        feedback_parts.append(f"Tables present ({table_count})")
    elif table_count >= 1:
        score += 10
        feedback_parts.append(f"Tables partial ({table_count})")
    else:
        feedback_parts.append("No tables found")

    # 4. Navigation Elements (25 pts)
    if result.get("has_toc", False):
        score += 15
        feedback_parts.append("Table of Contents present")
    else:
        feedback_parts.append("Missing Table of Contents")

    if result.get("has_page_numbers", False):
        score += 10
        feedback_parts.append("Page numbers present")
    else:
        feedback_parts.append("Missing page numbers")

    # 5. Content Verification (20 pts)
    keywords = result.get("keywords_found", [])
    required_kws = ["Martinez", "JC-2024"] # Crucial ID info
    goal_kws = ["housing", "parenting", "substance", "attendance"]
    
    # Check ID info (5 pts)
    if all(k in keywords for k in ["Martinez", "JC-2024"]): # Partial match logic handled in export script
        score += 5
        feedback_parts.append("Case ID info correct")
    elif "Martinez" in keywords:
        score += 2
        feedback_parts.append("Family name found, but case number missing")
    
    # Check Goals/Topics (10 pts)
    found_goals = sum(1 for k in goal_kws if k in keywords)
    if found_goals >= 2:
        score += 10
        feedback_parts.append("Case goals included")
    elif found_goals == 1:
        score += 5
        feedback_parts.append("Some case goals missing")
    else:
        feedback_parts.append("Case goals missing")
        
    # Check Providers (5 pts)
    providers = ["Centerstone", "Volunteers of America"]
    if any(p in keywords for p in providers):
        score += 5
        feedback_parts.append("Service providers included")
    else:
        feedback_parts.append("Service providers missing")

    # 6. Anti-gaming check (File modified during task)
    if not result.get("file_created_during_task", False):
        feedback_parts.append("WARNING: File not modified during task duration")
        score = 0 # Fail if file is old

    # Final Score Calculation
    # Pass threshold: 70
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": result
    }