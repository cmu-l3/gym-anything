#!/usr/bin/env python3
"""
Verifier for add_web_reference task.

Checks:
1. API: Verifies that a reference with the correct URL and Title exists on the case.
2. API: Verifies the reference was created AFTER the task started (anti-gaming).
3. VLM: Verifies the visual state (screenshot) shows the reference in the UI.
"""

import json
import tempfile
import os
import logging
import sys

# Add gym_anything path for VLM utilities
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames
except ImportError:
    # Mock for local testing without framework
    def get_final_screenshot(traj): return traj.get('final_screenshot')
    def query_vlm(**kwargs): return {'success': False, 'error': 'VLM not available'}
    def sample_trajectory_frames(traj, n): return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_web_reference(traj, env_info, task_info):
    """
    Verify the add_web_reference task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_url_fragment = "justice.gov/foia"
    expected_title_fragment = "Official DOJ FOIA Guidelines"

    # 1. Load API Result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            api_result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to load task result JSON: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Score Calculation
    score = 0
    feedback_parts = []
    
    task_start = api_result.get('task_start_ts', 0)
    references = api_result.get('references', [])
    
    # API Verification
    api_match = False
    correct_metadata = False
    created_during_task = False
    
    for ref in references:
        url = ref.get('url', '')
        title = ref.get('title', '')
        created = ref.get('created_ts', 0)
        
        # Check URL match
        if expected_url_fragment in url:
            api_match = True
            
            # Check Title match
            if expected_title_fragment.lower() in title.lower():
                correct_metadata = True
            
            # Check Timestamp (Anti-gaming)
            # Allow 5 second buffer for clock skew
            if created >= (task_start - 5):
                created_during_task = True
            
            break # Stop after finding the first matching URL
    
    if api_match:
        score += 30
        feedback_parts.append("API: Reference URL found.")
        
        if correct_metadata:
            score += 20
            feedback_parts.append("API: Title/Description correct.")
        else:
            feedback_parts.append("API: Title mismatch.")
            
        if created_during_task:
            score += 20
            feedback_parts.append("API: Created during task session.")
        else:
            feedback_parts.append("API: Reference existed before task start (Anti-gaming penalty).")
    else:
        feedback_parts.append("API: No reference with expected URL found on case.")

    # 3. VLM Verification
    # We check if the agent actually navigated to the references section and the link is visible
    final_screenshot = get_final_screenshot(traj)
    
    vlm_score = 0
    if final_screenshot:
        prompt = f"""
        Analyze this screenshot of the ArkCase interface.
        I am looking for a web reference or link added to a case.
        
        1. Is the 'References', 'Links', or 'External Links' section visible?
        2. Can you see a link/reference with the title "{expected_title_fragment}"?
        3. Can you see the URL "{expected_url_fragment}"?
        
        Return JSON:
        {{
            "references_section_visible": true/false,
            "target_link_visible": true/false,
            "confidence": "low/medium/high"
        }}
        """
        
        vlm_resp = query_vlm(images=[final_screenshot], prompt=prompt)
        
        if vlm_resp.get('success'):
            parsed = vlm_resp.get('parsed', {})
            if parsed.get('references_section_visible'):
                vlm_score += 10
            if parsed.get('target_link_visible'):
                vlm_score += 20
            
            feedback_parts.append(f"VLM: Section visible={parsed.get('references_section_visible')}, Link visible={parsed.get('target_link_visible')}")
        else:
            feedback_parts.append("VLM: Analysis failed.")
            # Fallback points if API was perfect, assume UI is likely correct
            if api_match and correct_metadata: 
                vlm_score += 15
                feedback_parts.append("VLM: Fallback points awarded based on API success.")
    
    score += vlm_score

    # Final Pass Determination
    # Must have API match AND (VLM confirmation OR correct metadata)
    passed = (score >= 70) and api_match

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }