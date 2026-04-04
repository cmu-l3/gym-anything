#!/usr/bin/env python3
"""
Verifier for annotate_extra_field task.
"""

import json
import tempfile
import os
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

def parse_extra_field(content):
    """
    Parses the Extra field content into a dictionary.
    Expected format:
    Citation Count: <number>
    Area: <text>
    """
    if not content:
        return {}
    
    data = {}
    lines = content.split('\n')
    for line in lines:
        if ':' in line:
            key, val = line.split(':', 1)
            data[key.strip()] = val.strip()
    return data

def verify_annotate_extra_field(traj, env_info, task_info):
    """
    Verifies that the agent correctly annotated the Extra field for 5 specific papers.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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

    if result.get('db_error'):
        return {"passed": False, "score": 0, "feedback": f"Database error during verification: {result['db_error']}"}

    metadata = task_info.get('metadata', {})
    targets = metadata.get('targets', [])
    papers_data = result.get('papers', {})
    
    score = 0
    feedback_parts = []
    
    # Track which IDs were targets to check for pollution later
    target_ids_found = set()
    
    # 1. Verify Targets
    for target in targets:
        target_title_sub = target['title_substring']
        expected_citation = target['citation']
        expected_area = target['area']
        
        # Find paper in result by title substring
        found_paper = None
        found_id = None
        
        for pid, pdata in papers_data.items():
            if target_title_sub in pdata['title']:
                found_paper = pdata
                found_id = pid
                break
        
        if not found_paper:
            feedback_parts.append(f"Paper not found: '{target_title_sub}'")
            continue
            
        target_ids_found.add(found_id)
        
        extra_content = found_paper.get('extra_content', '')
        parsed_extra = parse_extra_field(extra_content)
        
        paper_score = 0
        paper_feedback = []
        
        # Check Citation Count (5 pts)
        # Strict key matching: "Citation Count"
        actual_citation = parsed_extra.get('Citation Count')
        if actual_citation == expected_citation:
            paper_score += 5
        elif actual_citation:
            paper_feedback.append(f"Wrong citation '{actual_citation}'")
        else:
            paper_feedback.append("Missing 'Citation Count'")
            
        # Check Area (5 pts)
        actual_area = parsed_extra.get('Area')
        if actual_area == expected_area:
            paper_score += 5
        elif actual_area:
            paper_feedback.append(f"Wrong area '{actual_area}'")
        else:
            paper_feedback.append("Missing 'Area'")

        score += paper_score
        
        if paper_score == 10:
            feedback_parts.append(f"✓ '{target_title_sub}'")
        else:
            feedback_parts.append(f"✗ '{target_title_sub}': {', '.join(paper_feedback)}")

    # 2. Bonus: Completion breadths
    # Count fully correct papers (score 10)
    # Re-calculate temporarily for bonus logic
    fully_correct_count = 0
    for target in targets:
        # (Re-using logic implicitly or just trusting the score addition above)
        # Let's count explicitly based on the logs we just made? 
        # Easier: iterate targets again or store status.
        # Let's just use the score accumulation so far.
        pass

    # Actually, let's just calculate bonus based on score so far
    # Max score from items so far is 5 * 10 = 50.
    # We need to reach 100.
    # Bonuses:
    # 20 pts: At least 3 papers fully annotated (checked below)
    # 15 pts: All 5 papers fully annotated (checked below)
    # 10 pts: No incorrect Extra content on other papers
    
    fully_correct_count = 0
    for target in targets:
        # Re-find to check correctness for bonus
        target_title_sub = target['title_substring']
        for pid, pdata in papers_data.items():
            if target_title_sub in pdata['title']:
                extra_content = pdata.get('extra_content', '')
                parsed = parse_extra_field(extra_content)
                if (parsed.get('Citation Count') == target['citation'] and 
                    parsed.get('Area') == target['area']):
                    fully_correct_count += 1
                break

    if fully_correct_count >= 3:
        score += 20
        feedback_parts.append("Bonus: ≥3 papers complete (+20)")
    
    if fully_correct_count == 5:
        score += 15
        feedback_parts.append("Bonus: All 5 papers complete (+15)")

    # 3. Check for Pollution (15 pts)
    # "No incorrect Extra content on other papers"
    pollution_found = False
    for pid, pdata in papers_data.items():
        if pid not in target_ids_found:
            if pdata.get('extra_content'):
                pollution_found = True
                feedback_parts.append(f"Pollution: Extra field modified on '{pdata['title']}'")
                break
    
    if not pollution_found:
        score += 15
        feedback_parts.append("Clean library (+15)")
    else:
        # No points for pollution
        pass

    # 4. Anti-gaming check (Date Modified)
    # Verify that modified papers were actually modified after task start
    # Task start is in result['task_start'] (Unix timestamp)
    # Zotero dates are typically ISO strings 'YYYY-MM-DD HH:MM:SS' in UTC
    # We'll do a loose check: if content is correct but date is ancient, it's suspicious.
    # However, since we clean DB in setup, pre-existing data isn't possible.
    # We mainly rely on the content verification here.
    
    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }