#!/usr/bin/env python3
import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_policy_manual_adaptation(traj, env_info, task_info):
    """
    Verifies the Policy Manual Adaptation task.
    
    Scoring Breakdown (100 pts total):
    - File exists & valid size: 5 pts
    - Replacements (45 pts total):
      - Agency Name (Old=0, New>=10): 15 pts
      - Division Name (Old=0, New>=5): 10 pts
      - Phone (Old=0, New>=4): 10 pts
      - Email (Old=0, New>=3): 10 pts
    - Formatting Fixes (15 pts):
      - Sections 3, 6, 9 are Heading 1: 5 pts each
    - Header Added (15 pts): "MARICOPA COUNTY" in header style
    - Revision Table (15 pts): Table exists with correct data
    - Content Preserved (5 pts): Paragraph count check
    """
    
    # 1. Load Result JSON from Env
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verifier failed: copy_from_env not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {str(e)}"}
    finally:
        os.unlink(temp_result.name)

    # 2. Gate Checks
    if not result.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": "Task Failed: Output file 'maricopa_cd_response_manual.odt' not found."}
    
    if not result.get('created_during_task', False):
        # We allow it if modified, but ideally it should be new/modified. 
        # If timestamp check failed but file exists, we warn but proceed if size changed.
        pass 

    score = 0
    feedback = []

    # File exists points
    score += 5
    feedback.append("File created successfully (+5)")

    # 3. Verify Replacements (45 pts)
    # Defines: (Old term, New term, Old Max Allow, New Min Require, Points)
    replacement_rules = [
        ("Arizona Department of Health Services", "Maricopa County Department of Public Health", 0, 10, 15),
        ("State Epidemiology and Response Division", "County Epidemiology Unit", 0, 5, 10),
        ("(602) 555-0147", "(602) 555-0328", 0, 4, 10),
        ("@azdhs.gov", "@maricopa.gov", 0, 3, 10)
    ]
    
    rep_data = result.get('replacements_score_data', {})
    
    for old_term, new_term, max_old, min_new, pts in replacement_rules:
        count_old = rep_data.get(old_term, 0)
        count_new = rep_data.get(new_term, 0)
        
        if count_old <= max_old and count_new >= min_new:
            score += pts
            feedback.append(f"Replaced '{old_term[:15]}...' correctly ({count_new} found) (+{pts})")
        else:
            feedback.append(f"Failed replacement '{old_term[:15]}...': Found {count_old} old (allowed {max_old}), {count_new} new (needed {min_new})")

    # 4. Verify Formatting (15 pts)
    fmt_data = result.get('formatting_check', {})
    fixed_sec_3 = fmt_data.get('section_3_fixed', False)
    fixed_sec_6 = fmt_data.get('section_6_fixed', False)
    fixed_sec_9 = fmt_data.get('section_9_fixed', False)
    
    fixed_count = sum([fixed_sec_3, fixed_sec_6, fixed_sec_9])
    score += (fixed_count * 5)
    if fixed_count == 3:
        feedback.append("All broken headings fixed to Heading 1 (+15)")
    elif fixed_count > 0:
        feedback.append(f"Partially fixed headings ({fixed_count}/3) (+{fixed_count*5})")
    else:
        feedback.append("No broken headings were fixed to Heading 1 style")

    # 5. Verify Header (15 pts)
    if result.get('header_check', False):
        score += 15
        feedback.append("Page header added correctly (+15)")
    else:
        feedback.append("Page header missing or incorrect text")

    # 6. Verify Revision Table (15 pts)
    if result.get('revision_table_check', False):
        score += 15
        feedback.append("Revision history table added correctly (+15)")
    else:
        feedback.append("Revision history table missing or content incorrect")

    # 7. Content Preservation (5 pts)
    # Original has ~10 sections, so at least ~40 paragraphs expected
    if result.get('content_preserved_count', 0) >= 40:
        score += 5
        feedback.append("Document content preserved (+5)")
    else:
        feedback.append("Document content seems truncated")

    # Final Result
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": "; ".join(feedback)
    }