#!/usr/bin/env python3
"""
Verifier for Create Audience Segments task in Matomo.

Verification Strategy:
1. Check if segments exist with correct names.
2. Check if segments were created during the task (anti-gaming).
3. Verify segment definitions (conditions and logic).
4. Verify visibility settings.

Scoring (100 points):
- Segment count increased: 10 pts
- Segment 1 (Desktop) exists: 10 pts
- Segment 1 definition correct (Desktop + >3 actions): 30 pts
- Segment 2 (Mobile) exists: 10 pts
- Segment 2 definition correct (Smartphone + =1 action): 30 pts
- Visibility correct (both set to All Users): 10 pts
"""

import sys
import os
import json
import logging
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_audience_segments(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/segments_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    score = 0
    feedback_parts = []
    
    initial_count = result.get('initial_count', 0)
    current_count = result.get('current_count', 0)
    
    # 1. Check if count increased (Basic activity check)
    if current_count >= initial_count + 2:
        score += 10
        feedback_parts.append("Segment count increased by at least 2 (+10)")
    elif current_count > initial_count:
        score += 5
        feedback_parts.append("Segment count increased, but less than 2 (+5)")
    else:
        feedback_parts.append("No new segments created")

    # Helper to verify a segment
    def verify_segment(seg_data, expected_name, keywords_must_have):
        seg_score = 0
        seg_feedback = []
        
        if not seg_data.get('found'):
            return 0, [f"Segment '{expected_name}' not found"]
            
        # Name check (already done by query, but confirming existence)
        seg_score += 10
        seg_feedback.append(f"Segment '{expected_name}' exists (+10)")
        
        # New check
        if not seg_data.get('is_new'):
            seg_feedback.append(f"WARNING: Segment '{expected_name}' existed before task start")
            # We don't necessarily zero the score, but it's suspicious
        
        # Definition check
        definition = seg_data.get('definition', '')
        # Matomo definitions look like: deviceType==Desktop;visitTotalActions>3
        # We check for substring presence to be robust
        
        conditions_met = True
        missing_conditions = []
        
        for kw in keywords_must_have:
            if kw.lower() not in definition.lower():
                conditions_met = False
                missing_conditions.append(kw)
        
        if conditions_met:
            seg_score += 30
            seg_feedback.append(f"Definition for '{expected_name}' is correct (+30)")
        else:
            seg_feedback.append(f"Definition for '{expected_name}' incorrect. Missing: {', '.join(missing_conditions)} (Got: {definition})")
            
        return seg_score, seg_feedback

    # Verify Segment 1: High-Value Desktop Users
    # Expected: deviceType==Desktop AND visitTotalActions>3 (or actions>3)
    s1_score, s1_fb = verify_segment(
        result.get('segment_1', {}), 
        "High-Value Desktop Users", 
        ["deviceType", "Desktop", ">", "3"] # Basic keywords
    )
    score += s1_score
    feedback_parts.extend(s1_fb)
    
    # Extra check for specific keywords if basic passed
    if s1_score >= 40: # If exists and keywords match
        def1 = result['segment_1']['definition']
        if "actions" not in def1.lower() and "visit" not in def1.lower():
            score -= 15
            feedback_parts.append("Segment 1 missing action count condition (-15)")

    # Verify Segment 2: Bounced Mobile Visitors
    # Expected: deviceType==smartphone AND visitTotalActions==1
    s2_score, s2_fb = verify_segment(
        result.get('segment_2', {}), 
        "Bounced Mobile Visitors", 
        ["deviceType", "smartphone", "==", "1"]
    )
    score += s2_score
    feedback_parts.extend(s2_fb)
    
    if s2_score >= 40:
        def2 = result['segment_2']['definition']
        if "actions" not in def2.lower() and "visit" not in def2.lower():
            score -= 15
            feedback_parts.append("Segment 2 missing action count condition (-15)")

    # Verify Visibility
    # enable_all_users should be 1
    vis1 = str(result.get('segment_1', {}).get('visibility', '0'))
    vis2 = str(result.get('segment_2', {}).get('visibility', '0'))
    
    if vis1 == '1' and vis2 == '1':
        score += 10
        feedback_parts.append("Visibility set to All Users for both (+10)")
    elif vis1 == '1' or vis2 == '1':
        score += 5
        feedback_parts.append("Visibility set to All Users for one segment (+5)")
    else:
        feedback_parts.append("Visibility not set to All Users")

    # Final logic
    passed = score >= 60 and result.get('segment_1', {}).get('found') and result.get('segment_2', {}).get('found')

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }