#!/usr/bin/env python3
"""
Verifier for dot_compliance_manual task.

Scoring (100 points):
- File existence & size (Gate): 0 pts (Fail if missing/<5KB)
- Structure:
    - Heading 1 count (>=7): 15 pts
    - Heading 2 count (>=12): 15 pts
    - Tables (>=3): 15 pts
    - Table of Contents: 15 pts
    - Footer/Page Numbers: 10 pts
- Content:
    - Company Identifiers (Name+DOT+MC): 5 pts
    - Regulatory References (>=3 CFR parts): 5 pts
    - Regulatory Terms (>=4): 5 pts
    - Volume (>=30 paragraphs): 10 pts
    - Bonus (Comprehensive terms): 5 pts

Pass Threshold: 70 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_dot_compliance_manual(traj, env_info, task_info):
    """Verify the DOT compliance manual creation task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_path = temp_file.name
    temp_file.close()

    try:
        copy_from_env("/tmp/task_result.json", temp_path)
        with open(temp_path, 'r', encoding='utf-8-sig') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error parsing result: {e}"}
    finally:
        if os.path.exists(temp_path):
            try: os.unlink(temp_path)
            except: pass

    # Gate: Check file existence and size
    if not result.get('file_exists') or result.get('file_size', 0) < 5000:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Manual file not found or empty (must be >= 5KB). Did you save it to the correct path?"
        }
    
    # Anti-gaming: Check creation time
    if not result.get('file_created_during_task', True):
        return {
            "passed": False,
            "score": 0,
            "feedback": "File timestamp indicates it was not created during the task session."
        }

    score = 0
    feedback = []
    
    # 1. Structure Scoring
    # Heading 1 (Target: 7)
    h1 = result.get('heading1_count', 0)
    if h1 >= 7:
        score += 15
        feedback.append(f"Structure: {h1} Heading 1 sections (Good)")
    elif h1 >= 4:
        score += 7
        feedback.append(f"Structure: {h1}/7 Heading 1 sections (Partial)")
    else:
        feedback.append(f"Structure: Only {h1}/7 Heading 1 sections found (Fail)")

    # Heading 2 (Target: 12)
    h2 = result.get('heading2_count', 0)
    if h2 >= 12:
        score += 15
        feedback.append(f"Structure: {h2} Heading 2 subsections (Good)")
    elif h2 >= 6:
        score += 7
        feedback.append(f"Structure: {h2}/12 Heading 2 subsections (Partial)")
    else:
        feedback.append(f"Structure: Only {h2}/12 Heading 2 subsections found (Fail)")

    # Tables (Target: 3)
    tables = result.get('table_count', 0)
    if tables >= 3:
        score += 15
        feedback.append(f"Structure: {tables} Tables found (Good)")
    elif tables >= 1:
        score += 7
        feedback.append(f"Structure: {tables}/3 Tables found (Partial)")
    else:
        feedback.append("Structure: No tables found (Fail)")

    # TOC
    if result.get('has_toc'):
        score += 15
        feedback.append("Structure: Table of Contents found (Good)")
    else:
        feedback.append("Structure: Table of Contents missing (Fail)")

    # Page Numbers
    if result.get('has_page_numbers'):
        score += 10
        feedback.append("Structure: Page numbers found (Good)")
    else:
        feedback.append("Structure: Page numbers missing (Fail)")

    # 2. Content Scoring
    content_check = result.get('content_check', {})
    
    # Identifiers
    ids_present = (content_check.get('company_name') and 
                   content_check.get('usdot') and 
                   content_check.get('mc_number'))
    if ids_present:
        score += 5
        feedback.append("Content: Company identifiers correct")
    else:
        feedback.append("Content: Missing company name, USDOT, or MC number")

    # Volume (Paragraphs)
    paras = result.get('paragraph_count', 0)
    if paras >= 30:
        score += 10
        feedback.append(f"Content: Document volume sufficient ({paras} paragraphs)")
    else:
        feedback.append(f"Content: Document too short ({paras}/30 paragraphs)")

    # Regulatory content
    cfr_count = content_check.get('cfr_references', 0)
    term_count = content_check.get('regulatory_terms', 0)
    
    if cfr_count >= 3:
        score += 5
        feedback.append(f"Content: {cfr_count} CFR references found")
    
    if term_count >= 4:
        score += 5
        feedback.append(f"Content: {term_count} regulatory topics covered")
        
    # Bonus
    if term_count >= 5:
        score += 5
        feedback.append("Bonus: Comprehensive regulatory coverage")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }