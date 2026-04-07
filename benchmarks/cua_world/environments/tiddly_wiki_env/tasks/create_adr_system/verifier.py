#!/usr/bin/env python3
"""Verifier for create_adr_system task in TiddlyWiki."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_adr_system(traj, env_info, task_info):
    """
    Verify the ADR System creation.
    
    Checks:
    1. 5 ADRs exist with correct statuses, tags, and structure (Context, Decision, Consequences)
    2. Cross-references exist between ADR-003 and ADR-005
    3. Index tiddler exists using <$list> and adr-status filters
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/adr_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    tiddlers = result.get('tiddlers', {})
    
    # Extract expected data from metadata
    metadata = task_info.get('metadata', {})
    expected_adrs = metadata.get('expected_adrs', {
        "ADR-001": "Accepted",
        "ADR-002": "Accepted",
        "ADR-003": "Deprecated",
        "ADR-004": "Proposed",
        "ADR-005": "Accepted"
    })
    
    # Sub-scores tracking
    adrs_found = 0
    tags_correct = 0
    statuses_correct = 0
    sections_correct = 0
    
    adr003_body = ""
    adr005_body = ""
    
    # ================================================================
    # 1. Evaluate individual ADRs (Max 65 points)
    # ================================================================
    for adr_id, expected_status in expected_adrs.items():
        matched_title = None
        # Allow partial match to be robust to minor title typos
        for t_title in tiddlers.keys():
            if adr_id in t_title:
                matched_title = t_title
                break
                
        if matched_title:
            adrs_found += 1
            t_data = tiddlers[matched_title]
            
            # Save specific bodies to check cross-references later
            if adr_id == "ADR-003":
                adr003_body = t_data.get('body', '')
            elif adr_id == "ADR-005":
                adr005_body = t_data.get('body', '')
            
            # 1a. Check Tag (2 pts per ADR)
            tags = t_data.get('tags', '')
            if re.search(r'\bADR\b', tags):
                tags_correct += 1
                
            # 1b. Check Status Field (3 pts per ADR)
            status = t_data.get('adr_status', '')
            if expected_status.lower() in status.lower():
                statuses_correct += 1
                
            # 1c. Check Expected Content Headings (4 pts per ADR)
            body = t_data.get('body', '')
            has_context = re.search(r'!!\s*Context', body, re.IGNORECASE)
            has_decision = re.search(r'!!\s*Decision', body, re.IGNORECASE)
            has_consequences = re.search(r'!!\s*Consequences', body, re.IGNORECASE)
            
            if has_context and has_decision and has_consequences:
                sections_correct += 1

    # Accumulate ADR base points
    score += adrs_found * 4        # 5 * 4 = 20
    score += tags_correct * 2      # 5 * 2 = 10
    score += statuses_correct * 3  # 5 * 3 = 15
    score += sections_correct * 4  # 5 * 4 = 20
    
    feedback_parts.append(f"ADRs found: {adrs_found}/5")
    feedback_parts.append(f"Correct tags: {tags_correct}/5")
    feedback_parts.append(f"Correct statuses: {statuses_correct}/5")
    feedback_parts.append(f"Correct sections: {sections_correct}/5")
    
    # ================================================================
    # 2. Evaluate Cross-References (Max 10 points)
    # ================================================================
    links_found = 0
    if 'ADR-005' in adr003_body:
        links_found += 1
    if 'ADR-003' in adr005_body:
        links_found += 1
        
    score += links_found * 5
    feedback_parts.append(f"Cross-references: {links_found}/2")
    
    # ================================================================
    # 3. Evaluate ADR Index Tiddler (Max 25 points)
    # ================================================================
    index_tiddler = None
    for t_title, t_data in tiddlers.items():
        if 'Index' in t_title and ('ADR' in t_title or 'ADR' in t_data.get('tags', '')):
            index_tiddler = t_data
            break
            
    if index_tiddler:
        score += 10 # ADR Index exists (10 pts)
        feedback_parts.append("ADR Index found")
        
        index_body = index_tiddler.get('body', '')
        
        # Check for filter widgets (10 pts)
        has_list = '<$list' in index_body
        has_filter = 'filter=' in index_body
        has_adr_status = 'adr-status' in index_body
        
        if has_list and has_filter and has_adr_status:
            score += 10
            feedback_parts.append("Index uses dynamic adr-status filters")
        elif has_list:
            score += 5
            feedback_parts.append("Index uses lists but missing adr-status parameter")
        else:
            feedback_parts.append("Index lacks dynamic <$list> widgets")
            
        # Check semantic groupings (5 pts)
        groups_found = 0
        for status in ['Accepted', 'Proposed', 'Deprecated']:
            if status in index_body:
                groups_found += 1
        
        if groups_found == 3:
            score += 5
            feedback_parts.append("Index has all 3 status groupings")
        else:
            # Partial credit for groupings
            score += groups_found
            feedback_parts.append(f"Index groupings found: {groups_found}/3")
            
    else:
        feedback_parts.append("ADR Index NOT found")

    # Anti-gaming info checks
    gui_save = result.get('gui_save_detected', False)
    if gui_save:
        feedback_parts.append("GUI interaction verified via logs")
    else:
        feedback_parts.append("Warning: No GUI save events found")

    passed = score >= 60 and adrs_found >= 3 and index_tiddler is not None
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }