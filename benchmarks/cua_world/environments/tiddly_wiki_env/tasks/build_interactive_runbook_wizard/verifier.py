#!/usr/bin/env python3
"""Verifier for build_interactive_runbook_wizard task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try importing VLM tools (fail gracefully if not available)
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    logger.warning("VLM tools not available. Skipping visual verification.")

VLM_PROMPT = """You are evaluating a TiddlyWiki desktop interface.
The user's goal was to create an interactive "Production Database Upgrade Wizard" using TiddlyWiki widgets.
Look at the sequence of frames and the final screenshot. 

Assess the following:
1. Is there a tiddler visible titled "Production Database Upgrade Wizard"?
2. Does the content area of this tiddler display a wizard-like interface (e.g., buttons saying "Next", "Previous", or "Finish")?
3. Is only a single step of the runbook content visible at a time (rather than all 4 steps printed out at once)?

Respond in JSON format:
{
    "wizard_title_visible": true/false,
    "navigation_buttons_visible": true/false,
    "single_step_visible": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "brief explanation"
}
"""

def verify_runbook_wizard(traj, env_info, task_info):
    """Verify that the interactive runbook wizard was built correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/wizard_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Tiddler Exists (10 pts)
    if result.get('tiddler_exists'):
        score += 10
        feedback_parts.append("Wizard tiddler exists")
    else:
        feedback_parts.append("FAIL: Wizard tiddler not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # Criterion 2: Transclusion used instead of copy-pasting (20 pts)
    refs_found = sum([
        result.get('has_t1_reference', False),
        result.get('has_t2_reference', False),
        result.get('has_t3_reference', False),
        result.get('has_t4_reference', False)
    ])
    
    if result.get('has_hardcoded_content'):
        feedback_parts.append("FAIL: Content was copy-pasted instead of transcluded")
    elif refs_found == 4:
        score += 20
        feedback_parts.append("All 4 runbook steps properly transcluded")
    elif refs_found > 0:
        score += refs_found * 5
        feedback_parts.append(f"Partial transclusion ({refs_found}/4 steps)")
    else:
        feedback_parts.append("FAIL: No transclusion references found")

    # Criterion 3: Reveal Widgets Used (15 pts)
    if result.get('has_reveal_widget'):
        score += 15
        feedback_parts.append("Reveal widgets used")
    else:
        feedback_parts.append("FAIL: Missing <$reveal> widgets")

    # Criterion 4: Mutually Exclusive State Logic (10 pts)
    if result.get('has_match_type'):
        score += 10
        feedback_parts.append("Match/nomatch type used for state exclusivity")
    else:
        feedback_parts.append("FAIL: Missing type='match' logic in reveals")

    # Criterion 5: Button State Mutation (15 pts)
    if result.get('has_button_widget') and result.get('has_state_mutation'):
        score += 15
        feedback_parts.append("Buttons configured for state mutation")
    elif result.get('has_button_widget'):
        score += 5
        feedback_parts.append("Buttons present but missing state mutation (set/setTo)")
    else:
        feedback_parts.append("FAIL: Missing navigation buttons")

    # Criterion 6: VLM Visual Verification (30 pts)
    vlm_score = 0
    if VLM_AVAILABLE and traj:
        try:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
            
            vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
            
            if vlm_res and vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('wizard_title_visible'):
                    vlm_score += 10
                if parsed.get('navigation_buttons_visible'):
                    vlm_score += 10
                if parsed.get('single_step_visible'):
                    vlm_score += 10
                
                score += vlm_score
                feedback_parts.append(f"VLM verified UI ({vlm_score}/30 pts)")
            else:
                feedback_parts.append("VLM visual verification failed to parse")
        except Exception as e:
            logger.warning(f"VLM verification error: {e}")
            feedback_parts.append("VLM visual verification skipped (error)")
    else:
        # Fallback if VLM isn't available: grant points if text looks extremely complete
        if refs_found == 4 and result.get('has_reveal_widget') and result.get('has_state_mutation'):
            score += 30
            feedback_parts.append("VLM unavailable - full points granted based on strong programmatic signatures")

    # Final logic
    passed = score >= 70 and refs_found >= 2 and result.get('has_reveal_widget') and result.get('has_button_widget')
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }