#!/usr/bin/env python3
"""
Verifier for Edit Page task in WordPress.

Verification Strategy (Hybrid: Programmatic + VLM on Trajectory):

Programmatic checks (70 points) — from export script JSON inside container:
  1. Page exists (10 pts) - REQUIRED
  2. Title was changed to expected value (15 pts) - REQUIRED
  3. Content was updated (5 pts)
  4. Has 'Our Values' as HEADING (15 pts) - REQUIRED
  5. Has 3 values in LIST structure (15 pts) - REQUIRED
  6. All 3 keywords present (10 pts)

VLM checks (30 points) — using TRAJECTORY frames:
  7. Process verification (15 pts): Frames show editing workflow
  8. Final state verification (10 pts): Final frame shows success
  9. Cross-validation (5 pts): DB agrees with VLM

Pass threshold: 70 points AND page found AND title changed AND structure valid
"""

import json
import tempfile
import os
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
    """Run VLM query with single or multiple images."""
    if not query_vlm:
        return None
    if not image and not images:
        return None
    try:
        result = query_vlm(prompt=prompt, image=image, images=images)
        if result.get("success"):
            return result.get("parsed", {})
        logger.warning(f"VLM query failed: {result.get('error', 'unknown')}")
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROCESS_PROMPT = """You are analyzing a sequence of screenshots from an agent editing a WordPress page.

For successful page editing, the agent should:
1. Navigate to Pages in WordPress admin
2. Find and click to edit the 'About Us' page
3. Modify the page title
4. Add new content to the page
5. Click Update to save changes

Assess:
1. WORKFLOW_COMPLETED: Did the agent navigate to page editor AND make edits?
2. PAGE_EDITOR_VISIBLE: Is the WordPress page editor visible with content being edited?
3. UPDATE_CONFIRMED: Is there evidence the page was updated (Update button clicked, success message)?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "page_editor_visible": true/false,
    "update_confirmed": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress page editing task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are there success indicators? (e.g., "Page updated" message)
3. PAGE_DATA_VISIBLE: Can you see page content that was edited?
4. ERROR_INDICATORS: Are there any error messages?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "page_data_visible": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def _validate_structure(content):
    """
    Validate that content has proper structure:
    - "Our Values" as a heading (h2, h3, h4, or wp:heading block)
    - Three values (Innovation, Integrity, Excellence) in list items

    Returns dict with validation results.
    """
    result = {
        'has_our_values_heading': False,
        'values_as_list_items': [],
        'has_list_structure': False,
        'all_values_present': False,
    }

    if not content:
        return result

    content_lower = content.lower()

    # Check for "Our Values" as heading
    # WordPress block: wp:heading or <!-- wp:heading -->
    # HTML: <h2>Our Values</h2>, <h3>Our Values</h3>, <h4>Our Values</h4>
    # Also handle nested tags like <h2 class="...">Our Values</h2>
    heading_patterns = [
        r'<h[2-4][^>]*>.*?our\s+values.*?</h[2-4]>',  # Allow any content inside h tags
        r'wp:heading.*?our\s*values',  # WordPress block comment format
        r'<!-- wp:heading[^>]*-->.*?our\s+values.*?<!-- /wp:heading -->',  # Full block with comments
    ]

    for pattern in heading_patterns:
        if re.search(pattern, content_lower, re.IGNORECASE | re.DOTALL):
            result['has_our_values_heading'] = True
            break

    # Check for values in list items
    # WordPress block: wp:list-item or <!-- wp:list-item -->
    # HTML: <li>Innovation</li> or <li><p>Innovation</p></li> (with nested tags)
    required_values = ['innovation', 'integrity', 'excellence']

    for value in required_values:
        list_item_patterns = [
            rf'<li[^>]*>.*?{value}.*?</li>',  # Allow any content inside li (including nested tags)
            rf'wp:list-item.*?{value}',  # WordPress block format
            rf'<!-- wp:list-item[^>]*-->.*?{value}.*?<!-- /wp:list-item -->',  # Full block with comments
        ]

        for pattern in list_item_patterns:
            if re.search(pattern, content_lower, re.IGNORECASE | re.DOTALL):
                result['values_as_list_items'].append(value)
                break

    result['has_list_structure'] = len(result['values_as_list_items']) >= 3
    result['all_values_present'] = all(v in content_lower for v in required_values)

    return result


def verify_edit_page(traj, env_info, task_info):
    """
    Verify that the About Us page was correctly edited.

    Scoring (100 points total):
    Programmatic (70 pts): page exists, title changed, content updated, structure valid
    VLM (30 pts): trajectory process (15), final state (10), cross-validation (5)

    Pass threshold: 70 points AND page found AND title changed AND structure valid
    Structure valid = "Our Values" as heading + all 3 values in list items
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get expected values from task metadata
    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', 'About Our Team')

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/edit_page_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found - export_result.sh may not have run"
        }
    except json.JSONDecodeError as e:
        return {
            "passed": False, "score": 0,
            "feedback": f"Invalid JSON in result file: {str(e)}"
        }
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    page_found = result.get('page_found', False)
    page = result.get('page', {})
    changes = result.get('changes', {})
    content = page.get('content', '')

    logger.info(f"Result: found={page_found}, page={page}, changes={changes}")

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points total)
    # ================================================================

    # Criterion 1: Page exists (10 points) - REQUIRED
    if page_found:
        score += 10
        feedback_parts.append("Page found")
    else:
        feedback_parts.append("Page NOT found")

    # Criterion 2: Title was changed (15 points) - REQUIRED
    title_changed = changes.get('title_changed', False)
    current_title = page.get('title', '')
    if title_changed:
        score += 15
        feedback_parts.append(f"Title changed to '{expected_title}'")
    elif current_title.lower().strip() == expected_title.lower().strip():
        score += 15
        title_changed = True  # Correct title found
        feedback_parts.append(f"Title is correct: '{current_title}'")
    elif current_title:
        feedback_parts.append(f"Title not changed: '{current_title}' (expected: '{expected_title}')")
    else:
        feedback_parts.append("Title not found")

    # Criterion 3: Content was updated (5 points)
    content_updated = changes.get('content_updated', False)
    if content_updated:
        score += 5
        feedback_parts.append("Content was modified")
    else:
        feedback_parts.append("Content not modified")

    # ================================================================
    # STRUCTURAL VALIDATION (30 points) - REQUIRED for pass
    # ================================================================

    # First try export script's structural checks, then validate with content if available
    has_heading_from_export = changes.get('has_our_values_heading', False)
    has_list_from_export = changes.get('has_list_structure', False)
    values_in_list_count = changes.get('values_in_list_count', 0)

    # Also validate from content if available (double-check)
    structure_result = _validate_structure(content)

    # Use export script result if available, otherwise use our validation
    has_our_values_heading = has_heading_from_export or structure_result['has_our_values_heading']
    has_list_structure = has_list_from_export or structure_result['has_list_structure']

    # Criterion 4: Has 'Our Values' as HEADING (15 points) - REQUIRED
    if has_our_values_heading:
        score += 15
        feedback_parts.append("'Our Values' correctly formatted as heading")
    else:
        # Check if "Our Values" exists at all (no partial credit, just better feedback)
        has_our_values_text = changes.get('has_our_values', False)
        if has_our_values_text:
            feedback_parts.append("'Our Values' found but NOT as proper heading (needs <h2>/<h3> or wp:heading)")
        else:
            feedback_parts.append("'Our Values' heading NOT found")

    # Criterion 5: Has 3 values in LIST structure (15 points) - REQUIRED
    if has_list_structure:
        score += 15
        feedback_parts.append("All 3 values correctly in list structure")
    else:
        # Check what we do have
        has_innovation = changes.get('has_innovation', False)
        has_integrity = changes.get('has_integrity', False)
        has_excellence = changes.get('has_excellence', False)

        if values_in_list_count > 0:
            feedback_parts.append(f"Only {values_in_list_count}/3 values in list items (needs ALL 3)")
        elif has_innovation or has_integrity or has_excellence:
            feedback_parts.append("Values found but NOT in list structure (needs <li> or wp:list-item)")
        else:
            feedback_parts.append("Values NOT found in list structure")

    # Criterion 6: All 3 keywords present anywhere (10 points)
    has_innovation = changes.get('has_innovation', False)
    has_integrity = changes.get('has_integrity', False)
    has_excellence = changes.get('has_excellence', False)
    all_keywords_present = has_innovation and has_integrity and has_excellence

    if all_keywords_present:
        score += 10
        feedback_parts.append("All 3 values (Innovation, Integrity, Excellence) present")
    else:
        missing = []
        if not has_innovation:
            missing.append("Innovation")
        if not has_integrity:
            missing.append("Integrity")
        if not has_excellence:
            missing.append("Excellence")
        feedback_parts.append(f"Missing values: {', '.join(missing)}")

    # Structure is valid only if heading AND list structure are correct
    structure_valid = has_our_values_heading and has_list_structure

    # ================================================================
    # VLM CHECKS (30 points total)
    # ================================================================

    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False
    vlm_query_failed = False  # Track if VLM queries failed (not just unavailable)

    sampled_frames = sample_frames(traj, num_samples=12) if sample_frames else []  # Increased from 6 to 12
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        # VLM Check A: Process Verification (15 points)
        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                editor_visible = process_result.get('page_editor_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Full workflow confirmed")
                elif workflow_ok or editor_visible:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Workflow partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                vlm_query_failed = True
                feedback_parts.append("VLM process check failed (query error)")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

        # VLM Check B: Final State (10 points)
        if has_final:
            final_result = _vlm_query(
                query_vlm, FINAL_STATE_PROMPT, image=final_frame
            )
            details['vlm_final_state'] = final_result

            if final_result:
                admin_ok = final_result.get('admin_visible', False)
                success_ok = final_result.get('success_indicators', False)
                error_found = final_result.get('error_indicators', False)

                if admin_ok and success_ok and not error_found:
                    score += 10
                    feedback_parts.append("VLM final: Success confirmed")
                elif admin_ok and success_ok:
                    score += 7
                    feedback_parts.append("VLM final: Success with warnings")
                elif admin_ok:
                    score += 4
                    feedback_parts.append("VLM final: Admin visible")
                else:
                    feedback_parts.append("VLM final: Admin not visible")
            else:
                feedback_parts.append("VLM final check failed")
        else:
            feedback_parts.append("VLM final: No frame")

        # VLM Check C: Cross-validation (5 points)
        if title_changed and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: DB + VLM agree")
            details['cross_validation'] = 'pass'
        elif title_changed and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation: DB shows change but VLM didn't confirm")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not title_changed:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees edit but DB unchanged")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'

    else:
        feedback_parts.append("VLM checks skipped (unavailable)")

    # ================================================================
    # PASS CRITERIA - STRICTER
    # ================================================================
    # Must have:
    # - Score >= 70
    # - Page found
    # - Title changed to expected value
    # - Structure valid (heading + list)
    # VLM confirmation is OPTIONAL - only required if VLM successfully processed
    # (If VLM query failed, don't penalize the agent for it)

    # VLM is only required for pass if:
    # 1. VLM is available AND
    # 2. VLM query did NOT fail (returned a result)
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = (score >= 70 and page_found and title_changed and
                  structure_valid and vlm_workflow_confirmed)
    else:
        passed = score >= 70 and page_found and title_changed and structure_valid

    details.update({
        "page_found": page_found,
        "title_changed": title_changed,
        "content_updated": content_updated,
        "has_our_values_heading": has_our_values_heading,
        "has_list_structure": has_list_structure,
        "structure_valid": structure_valid,
        "has_innovation": has_innovation,
        "has_integrity": has_integrity,
        "has_excellence": has_excellence,
        "all_keywords_present": all_keywords_present,
        "vlm_available": vlm_available,
        "vlm_query_failed": vlm_query_failed,
        "vlm_workflow_confirmed": vlm_workflow_confirmed,
    })

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": details,
    }
