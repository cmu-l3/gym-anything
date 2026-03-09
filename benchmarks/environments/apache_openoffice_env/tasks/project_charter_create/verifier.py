#!/usr/bin/env python3
"""
Verifier for project_charter_create task.
Verifies ODT document structure, styles, and content.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_project_charter(traj, env_info, task_info):
    """
    Verify the Project Charter document creation.
    
    Scoring Breakdown (100 pts):
    - File exists, valid ODT, timestamp valid (Gate)
    - Auto-generated Table of Contents: 15 pts
    - Structure (Headings): 30 pts
      - Heading 1 usage (>= 7): 15 pts
      - Heading 2 usage (>= 6): 15 pts
    - Tables (>= 4): 20 pts
    - Footer/Page Numbers: 10 pts
    - Content Check: 15 pts
      - Company name match: 5 pts
      - Project keywords: 5 pts
      - Budget figures: 5 pts
    - Document Volume (>= 30 paragraphs): 10 pts
    """
    
    # 1. Copy result from env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}
        
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result data: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. Extract metrics
    exists = data.get("file_exists", False)
    size = data.get("file_size", 0)
    timestamp_valid = data.get("timestamp_valid", False)
    structure = data.get("structure", {})
    content = data.get("content", {})
    
    # 3. Gate Checks
    if not exists:
        return {"passed": False, "score": 0, "feedback": "File /home/ga/Documents/Ridgeline_DC_Migration_Charter.odt was not created."}
    
    if size < 5000: # 5KB minimum for a non-empty ODT
        return {"passed": False, "score": 0, "feedback": "Document created but appears empty (file size too small)."}
        
    if not timestamp_valid:
        return {"passed": False, "score": 0, "feedback": "File modification time invalid (not modified during task)."}

    score = 0
    feedback = []
    
    # 4. Scoring Logic
    
    # TOC (15 pts)
    if structure.get("has_toc", False):
        score += 15
        feedback.append("TOC found (+15)")
    else:
        feedback.append("Table of Contents missing")
        
    # Headings (30 pts)
    h1_count = structure.get("h1_count", 0)
    if h1_count >= 7:
        score += 15
        feedback.append(f"Heading 1 usage good ({h1_count}) (+15)")
    elif h1_count >= 3:
        score += 5
        feedback.append(f"Heading 1 usage partial ({h1_count}) (+5)")
    else:
        feedback.append("Insufficient Heading 1 styles used")
        
    h2_count = structure.get("h2_count", 0)
    if h2_count >= 6:
        score += 15
        feedback.append(f"Heading 2 usage good ({h2_count}) (+15)")
    elif h2_count >= 2:
        score += 5
        feedback.append(f"Heading 2 usage partial ({h2_count}) (+5)")
    else:
        feedback.append("Insufficient Heading 2 styles used")
        
    # Tables (20 pts)
    table_count = structure.get("table_count", 0)
    if table_count >= 4:
        score += 20
        feedback.append(f"Tables count good ({table_count}) (+20)")
    elif table_count >= 2:
        score += 10
        feedback.append(f"Tables count partial ({table_count}) (+10)")
    else:
        feedback.append("Missing required tables")
        
    # Footer (10 pts)
    if structure.get("has_footer_page_nums", False):
        score += 10
        feedback.append("Page numbers/Footer found (+10)")
    else:
        feedback.append("Page numbers missing")
        
    # Content (15 pts)
    if content.get("has_company_name", False):
        score += 5
    else:
        feedback.append("Company name missing")
        
    if content.get("has_project_keywords", False):
        score += 5
    else:
        feedback.append("Project keywords missing")
        
    if content.get("has_budget_figure", False):
        score += 5
    else:
        feedback.append("Budget details missing")
        
    # Volume (10 pts)
    p_count = structure.get("paragraph_count", 0)
    if p_count >= 30:
        score += 10
    else:
        feedback.append(f"Document too short ({p_count} paras)")
        
    # Final Result
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }