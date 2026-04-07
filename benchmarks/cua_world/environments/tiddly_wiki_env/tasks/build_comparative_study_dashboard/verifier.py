#!/usr/bin/env python3
"""
Verifier for build_comparative_study_dashboard task.
Uses multi-criteria evaluation including programmatic wikitext parsing 
and VLM trajectory analysis to verify completion.
"""

import json
import tempfile
import os
import logging
import sys
from pathlib import Path

# Add parent directory to path for gym_anything utilities
sys.path.insert(0, str(Path(__file__).parent.parent))

try:
    from vlm_utils import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logging.warning("VLM utilities not available. VLM checks will be skipped.")

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent's completion of a comparative dashboard task in TiddlyWiki.

Look at the provided trajectory frames and the final screenshot. 
The agent was asked to build an "Energy Comparison Dashboard" using two `<$select>` dropdowns to view different renewable energy sources side-by-side.

Assess the following:
1. DID_EDIT_WIKITEXT: Did the agent edit a tiddler and write WikiText containing `<$select>` widgets?
2. DASHBOARD_RENDERED: In the final state, is the comparative dashboard rendered and visible?
3. HAS_TWO_DROPDOWNS: Are there two distinct dropdown select boxes visible on the dashboard?
4. SIDE_BY_SIDE_COMPARISON: Does the final view allow comparing two different text entries (like Solar Power and Wind Power) at the same time?

Respond in JSON format:
{
    "did_edit_wikitext": true/false,
    "dashboard_rendered": true/false,
    "has_two_dropdowns": true/false,
    "side_by_side_comparison": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is seen in the images"
}
"""

def verify_comparative_dashboard(traj, env_info, task_info):
    """Verify that the dashboard tiddler was created with correct functionality."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

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
    
    # ---------------------------------------------------------
    # Programmatic Verification (60 points total)
    # ---------------------------------------------------------
    
    # Criterion 1: Tiddler created during task (Anti-gaming) (10 pts)
    if not result.get('created_during_task'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: Dashboard tiddler not created or modified during task session."
        }
    score += 10
    feedback_parts.append("Tiddler created successfully")

    # Criterion 2: Tiddler exists and has the right tag (10 pts)
    if result.get('dashboard_found'):
        if result.get('has_dashboard_tag'):
            score += 10
            feedback_parts.append("Dashboard tagged correctly")
        else:
            score += 5
            feedback_parts.append("Dashboard found but missing 'Dashboard' tag")
    else:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "FAIL: 'Energy Comparison Dashboard' tiddler not found."
        }

    # Criterion 3: Uses <$select> widgets correctly (15 pts)
    select_count = result.get('select_count', 0)
    if select_count >= 2:
        score += 15
        feedback_parts.append(f"Contains {select_count} select widgets")
    elif select_count == 1:
        score += 5
        feedback_parts.append("Contains only 1 select widget (needs 2 for comparison)")
    else:
        feedback_parts.append("FAIL: Missing <$select> widgets in WikiText")

    # Criterion 4: Uses State variables and Transclusion (15 pts)
    state_and_trans = 0
    if result.get('has_state_var'):
        state_and_trans += 7.5
        feedback_parts.append("Uses state tiddlers ($:/state/...)")
    else:
        feedback_parts.append("Missing state variables")
        
    if result.get('has_transclude'):
        state_and_trans += 7.5
        feedback_parts.append("Uses transclusion")
    else:
        feedback_parts.append("Missing transclusion logic")
        
    score += state_and_trans

    # Criterion 5: Filters by EnergySource tag (10 pts)
    if result.get('has_source_filter'):
        score += 10
        feedback_parts.append("Filters options by 'EnergySource' tag")
    else:
        feedback_parts.append("Missing 'tag[EnergySource]' filter logic")

    # Criterion 6: GUI interaction check (Anti-gaming)
    if not result.get('gui_save_detected'):
        feedback_parts.append("WARNING: No GUI save detected; may have bypassed UI")

    # ---------------------------------------------------------
    # VLM Verification (40 points total)
    # ---------------------------------------------------------
    if VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            
            # Combine trajectory frames and final image
            vlm_images = frames
            if final_img:
                vlm_images.append(final_img)
                
            vlm_result = query_vlm(images=vlm_images, prompt=VLM_PROMPT)
            
            if vlm_result and vlm_result.get("success"):
                parsed = vlm_result.get("parsed", {})
                
                vlm_score = 0
                if parsed.get("did_edit_wikitext"): vlm_score += 10
                if parsed.get("dashboard_rendered"): vlm_score += 10
                if parsed.get("has_two_dropdowns"): vlm_score += 10
                if parsed.get("side_by_side_comparison"): vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM Score: {vlm_score}/40")
                feedback_parts.append(f"VLM Reason: {parsed.get('reasoning', '')}")
            else:
                feedback_parts.append("VLM Verification failed or timed out")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM Verification encountered an error")
    else:
        # If VLM is not available, scale programmatic score to 100
        score = (score / 60.0) * 100
        feedback_parts.append("VLM skipped; scaled programmatic score")

    # Check pass threshold
    passed = score >= 70 and result.get('dashboard_found') and result.get('has_select_widgets')

    return {
        "passed": passed,
        "score": min(int(score), 100),
        "feedback": " | ".join(feedback_parts)
    }