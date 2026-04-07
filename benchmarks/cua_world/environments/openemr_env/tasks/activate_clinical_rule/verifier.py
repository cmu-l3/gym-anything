#!/usr/bin/env python3
"""
Verifier for Activate Clinical Decision Rule task in OpenEMR

Verifies that the 'Adult Weight Screening and Follow-up' clinical decision
support rule was activated by the agent.

Scoring:
- Rule activated (active=1): 40 points
- State changed during task: 20 points  
- Browser was running: 15 points
- Navigation evidence (on admin/rules page): 15 points
- VLM trajectory verification: 10 points

Pass threshold: 60 points with rule_activated=true required
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_activate_clinical_rule(traj, env_info, task_info):
    """
    Verify that the clinical decision rule was activated.
    
    Args:
        traj: Trajectory data with frames, steps, episode_dir
        env_info: Environment info with copy_from_env function
        task_info: Task info with metadata
        
    Returns:
        dict with 'passed' (bool), 'score' (int 0-100), 'feedback' (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Get expected values from metadata
    metadata = task_info.get('metadata', {})
    expected_rule_id = metadata.get('rule_id', 'rule_adult_wt_screen_fu')
    expected_active = metadata.get('expected_active_value', 1)
    
    try:
        # Copy result JSON from container
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/clinical_rule_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_result.name):
                os.unlink(temp_result.name)
        
        score = 0
        feedback_parts = []
        subscores = {
            "rule_activated": False,
            "state_changed": False,
            "browser_running": False,
            "navigation_evidence": False,
            "vlm_verification": False
        }
        
        # Extract data from result
        rule_id = result.get('rule_id', '')
        current_state = result.get('current_state', {})
        current_active = current_state.get('active', 0)
        initial_active = result.get('initial_active_state', 0)
        rule_activated = result.get('rule_activated', False)
        state_changed = result.get('state_changed', False)
        firefox_running = result.get('firefox_running', False)
        on_rules_page = result.get('on_rules_page', False)
        window_title = result.get('window_title', '')
        
        logger.info(f"Result data: rule_id={rule_id}, active={current_active}, initial={initial_active}")
        logger.info(f"Flags: activated={rule_activated}, changed={state_changed}")
        
        # Verify correct rule
        if rule_id != expected_rule_id:
            feedback_parts.append(f"WARNING: Rule ID mismatch (expected {expected_rule_id}, got {rule_id})")
        
        # CRITERION 1: Rule activated (40 points) - CRITICAL
        if rule_activated and current_active == expected_active:
            score += 40
            subscores["rule_activated"] = True
            feedback_parts.append(f"✅ Rule '{expected_rule_id}' successfully activated (active={current_active})")
        else:
            feedback_parts.append(f"❌ Rule not activated (active={current_active}, expected={expected_active})")
        
        # CRITERION 2: State changed during task (20 points) - Anti-gaming
        if state_changed:
            score += 20
            subscores["state_changed"] = True
            feedback_parts.append(f"✅ State changed during task ({initial_active} -> {current_active})")
        else:
            if rule_activated:
                # Rule is active but state didn't change - might have been pre-enabled
                feedback_parts.append("⚠️ Rule active but no state change detected (may have been pre-enabled)")
            else:
                feedback_parts.append("❌ No state change detected")
        
        # CRITERION 3: Browser was running (15 points)
        if firefox_running:
            score += 15
            subscores["browser_running"] = True
            feedback_parts.append("✅ Browser was running during task")
        else:
            feedback_parts.append("⚠️ Browser not detected at end of task")
        
        # CRITERION 4: Navigation evidence (15 points)
        # Check if window title suggests navigation to admin/rules area
        nav_keywords = ['admin', 'rules', 'clinical', 'decision', 'cdr', 'configuration']
        window_lower = window_title.lower()
        nav_found = any(kw in window_lower for kw in nav_keywords)
        
        if on_rules_page or nav_found:
            score += 15
            subscores["navigation_evidence"] = True
            feedback_parts.append(f"✅ Navigation to rules configuration detected")
        else:
            feedback_parts.append(f"⚠️ Could not confirm navigation to rules page (window: {window_title[:50]})")
        
        # CRITERION 5: VLM trajectory verification (10 points)
        vlm_score = verify_via_vlm(traj, env_info)
        if vlm_score > 0:
            score += vlm_score
            subscores["vlm_verification"] = True
            feedback_parts.append(f"✅ VLM verification passed (+{vlm_score} points)")
        else:
            feedback_parts.append("⚠️ VLM verification inconclusive")
        
        # Determine pass/fail
        # Must have rule_activated AND reasonable score
        passed = subscores["rule_activated"] and score >= 60
        
        # Additional validation: check timestamps
        task_start = result.get('task_start_timestamp', 0)
        task_end = result.get('task_end_timestamp', 0)
        
        if task_end > 0 and task_start > 0:
            duration = task_end - task_start
            if duration < 5:
                feedback_parts.append(f"⚠️ Suspiciously fast completion ({duration}s)")
            elif duration > 300:
                feedback_parts.append(f"ℹ️ Task took {duration}s")
        
        return {
            "passed": passed,
            "score": min(100, score),  # Cap at 100
            "feedback": " | ".join(feedback_parts),
            "subscores": subscores,
            "details": {
                "rule_id": rule_id,
                "current_active": current_active,
                "initial_active": initial_active,
                "state_changed": state_changed
            }
        }
        
    except FileNotFoundError:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Result file not found - export may have failed"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to parse result JSON: {e}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def verify_via_vlm(traj, env_info):
    """
    Use VLM to verify agent navigated through correct workflow.
    
    Checks trajectory frames (not just final screenshot) to verify:
    1. Agent logged into OpenEMR
    2. Agent navigated to Administration area
    3. Agent accessed Rules configuration
    4. Agent interacted with rule settings
    
    Returns:
        int: Points earned (0-10)
    """
    query_vlm = env_info.get('query_vlm')
    if not query_vlm:
        logger.warning("VLM query function not available")
        return 0
    
    try:
        # Import VLM utilities
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # Sample frames across the trajectory
        frames = sample_trajectory_frames(traj, n=5)
        final_screenshot = get_final_screenshot(traj)
        
        if not frames and not final_screenshot:
            logger.warning("No trajectory frames available for VLM verification")
            return 0
        
        # Use trajectory frames plus final screenshot
        all_frames = frames + ([final_screenshot] if final_screenshot else [])
        
        if not all_frames:
            return 0
        
        # VLM prompt for trajectory verification
        vlm_prompt = """You are verifying if a computer agent completed a task in OpenEMR (Electronic Health Records system).

TASK: Activate a clinical decision support rule in the Administration > Rules section.

Examine these screenshots from the agent's workflow and determine:
1. Did the agent log into OpenEMR? (Look for login page -> dashboard transition)
2. Did the agent navigate to Administration menu? (Look for admin menu or settings area)
3. Did the agent access Rules or Clinical Decision Rules? (Look for rules list/configuration page)
4. Did the agent interact with checkboxes or enable controls? (Look for form interactions)

Respond in JSON format:
{
    "logged_in": true/false,
    "accessed_admin": true/false,
    "accessed_rules": true/false,
    "interacted_with_controls": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief description of what you observed in the workflow"
}
"""
        
        # Query VLM with trajectory frames
        vlm_result = query_vlm(
            prompt=vlm_prompt,
            images=all_frames
        )
        
        if not vlm_result.get("success"):
            logger.warning(f"VLM query failed: {vlm_result.get('error')}")
            return 0
        
        parsed = vlm_result.get("parsed", {})
        
        # Score based on workflow verification
        vlm_score = 0
        
        if parsed.get("logged_in"):
            vlm_score += 2
        if parsed.get("accessed_admin"):
            vlm_score += 3
        if parsed.get("accessed_rules"):
            vlm_score += 3
        if parsed.get("interacted_with_controls"):
            vlm_score += 2
        
        # Adjust for confidence
        confidence = parsed.get("confidence", "low")
        if confidence == "low":
            vlm_score = int(vlm_score * 0.5)
        elif confidence == "medium":
            vlm_score = int(vlm_score * 0.8)
        
        logger.info(f"VLM verification result: {parsed}")
        logger.info(f"VLM score: {vlm_score}/10")
        
        return min(10, vlm_score)
        
    except ImportError as e:
        logger.warning(f"Could not import VLM utilities: {e}")
        return 0
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")
        return 0


# For testing
if __name__ == "__main__":
    # Mock test
    test_result = {
        "rule_id": "rule_adult_wt_screen_fu",
        "task_start_timestamp": 1700000000,
        "task_end_timestamp": 1700000120,
        "initial_active_state": 0,
        "current_state": {
            "active": 1,
            "passive_alert": 0,
            "patient_reminder": 0
        },
        "rule_activated": True,
        "state_changed": True,
        "firefox_running": True,
        "window_title": "OpenEMR - Clinical Decision Rules",
        "on_rules_page": True
    }
    
    print("Test result structure:")
    print(json.dumps(test_result, indent=2))