#!/usr/bin/env python3
"""
Verifier for build_corporate_site_structure task.

Occupation: Web Developer / Graphic Designer (SOC 15-1254.00 / 27-1024.00)
Difficulty: Very Hard

Agent must create 6 pages with parent-child hierarchy, configure static
front page, and update site identity.

Programmatic checks (70 points):
  1. Page 'Services' exists and published (5 pts)
  2. 'Web Development' is child of 'Services' (10 pts)
  3. 'Mobile Apps' is child of 'Services' (10 pts)
  4. 'Cloud Solutions' is child of 'Services' (10 pts)
  5. Pages 'About' and 'Careers' exist (10 pts)
  6. Static front page set to 'Services' (15 pts)
  7. Site title and tagline updated (10 pts)

VLM checks (30 points):
  8. Trajectory shows page creation workflow (15 pts)
  9. Final state shows admin with pages (10 pts)
  10. Cross-validation (5 pts)

Pass threshold: score >= 70 AND Services page exists AND static front page set
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def _vlm_query(query_vlm, prompt, image=None, images=None):
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


TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots from an agent building a corporate website structure in WordPress.

The agent should:
1. Create multiple pages (Services, Web Development, Mobile Apps, Cloud Solutions, About, Careers)
2. Set parent-child relationships between pages
3. Configure reading settings for a static front page
4. Update site title and tagline

Assess:
1. WORKFLOW_COMPLETED: Did the agent create pages and configure settings?
2. PAGE_EDITOR_VISIBLE: Are WordPress page creation/editing forms visible?
3. SETTINGS_MODIFIED: Are Reading settings or General settings being changed?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "page_editor_visible": true/false,
    "settings_modified": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress corporate site structure task.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. SUCCESS_INDICATORS: Are pages listed, or success messages visible?
3. SITE_CONFIGURED: Does the admin show the new site title or configured pages?
4. ERROR_INDICATORS: Any errors visible?

Respond in JSON format:
{
    "admin_visible": true/false,
    "success_indicators": true/false,
    "site_configured": true/false,
    "error_indicators": true/false,
    "confidence": "low"/"medium"/"high",
    "observations": "describe what you see"
}
"""


def verify_build_corporate_site_structure(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    details = {}

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/build_corporate_site_structure_result.json", temp_result.name)
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

    pages = result.get('pages', {})
    site_id = result.get('site_identity', {})
    reading = result.get('reading_settings', {})

    # ================================================================
    # PROGRAMMATIC CHECKS (70 points)
    # ================================================================

    # Criterion 1: Services page exists (5 pts)
    services = pages.get('services', {})
    services_found = services.get('found', False)
    if services_found:
        score += 5
        feedback_parts.append("Page 'Services' exists")
    else:
        feedback_parts.append("FAIL: Page 'Services' not found")

    # Criterion 2: Web Development is child of Services (10 pts)
    web_dev = pages.get('web_development', {})
    if web_dev.get('found', False) and web_dev.get('parent_correct', False):
        score += 10
        feedback_parts.append("'Web Development' correctly parented under 'Services'")
    elif web_dev.get('found', False):
        score += 3
        feedback_parts.append("'Web Development' exists but wrong parent")
    else:
        feedback_parts.append("FAIL: 'Web Development' not found")

    # Criterion 3: Mobile Apps is child of Services (10 pts)
    mobile = pages.get('mobile_apps', {})
    if mobile.get('found', False) and mobile.get('parent_correct', False):
        score += 10
        feedback_parts.append("'Mobile Apps' correctly parented under 'Services'")
    elif mobile.get('found', False):
        score += 3
        feedback_parts.append("'Mobile Apps' exists but wrong parent")
    else:
        feedback_parts.append("FAIL: 'Mobile Apps' not found")

    # Criterion 4: Cloud Solutions is child of Services (10 pts)
    cloud = pages.get('cloud_solutions', {})
    if cloud.get('found', False) and cloud.get('parent_correct', False):
        score += 10
        feedback_parts.append("'Cloud Solutions' correctly parented under 'Services'")
    elif cloud.get('found', False):
        score += 3
        feedback_parts.append("'Cloud Solutions' exists but wrong parent")
    else:
        feedback_parts.append("FAIL: 'Cloud Solutions' not found")

    # Criterion 5: About and Careers exist (10 pts)
    about = pages.get('about', {})
    careers = pages.get('careers', {})
    about_found = about.get('found', False)
    careers_found = careers.get('found', False)
    if about_found and careers_found:
        score += 10
        feedback_parts.append("'About' and 'Careers' pages exist")
    elif about_found:
        score += 5
        feedback_parts.append("'About' exists but 'Careers' missing")
    elif careers_found:
        score += 5
        feedback_parts.append("'Careers' exists but 'About' missing")
    else:
        feedback_parts.append("FAIL: Both 'About' and 'Careers' missing")

    # Criterion 6: Static front page set to Services (15 pts)
    static_front = reading.get('static_front_page', False)
    front_is_services = reading.get('front_page_is_services', False)
    if static_front and front_is_services:
        score += 15
        feedback_parts.append("Static front page correctly set to 'Services'")
    elif static_front:
        score += 5
        feedback_parts.append("Static front page set but NOT to 'Services'")
    else:
        feedback_parts.append("FAIL: Front page still shows latest posts (not static)")

    # Criterion 7: Site title and tagline (10 pts)
    title_ok = site_id.get('title_correct', False)
    tagline_ok = site_id.get('tagline_correct', False)
    if title_ok and tagline_ok:
        score += 10
        feedback_parts.append("Site title and tagline updated correctly")
    elif title_ok:
        score += 5
        feedback_parts.append("Site title correct but tagline wrong")
    elif tagline_ok:
        score += 5
        feedback_parts.append("Tagline correct but site title wrong")
    else:
        feedback_parts.append(f"FAIL: Site title='{site_id.get('title', '')}', tagline='{site_id.get('tagline', '')}'")

    # ================================================================
    # VLM CHECKS (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    sample_frames = env_info.get('sample_trajectory_frames')
    get_final = env_info.get('get_final_screenshot')
    vlm_workflow_confirmed = False
    vlm_available = False
    vlm_query_failed = False

    sampled_frames = sample_frames(traj, num_samples=12) if sample_frames else []
    final_frame = get_final(traj) if get_final else None

    has_trajectory = len(sampled_frames) >= 2
    has_final = final_frame is not None

    details['vlm_trajectory_frames'] = len(sampled_frames)
    details['vlm_has_final_frame'] = has_final

    if query_vlm and (has_trajectory or has_final):
        vlm_available = True

        if has_trajectory:
            process_result = _vlm_query(
                query_vlm, TRAJECTORY_PROCESS_PROMPT, images=sampled_frames
            )
            details['vlm_process'] = process_result

            if process_result:
                workflow_ok = process_result.get('workflow_completed', False)
                progression_ok = process_result.get('meaningful_progression', False)
                editor_ok = process_result.get('page_editor_visible', False)

                if workflow_ok and progression_ok:
                    score += 15
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Site structure workflow confirmed")
                elif workflow_ok or editor_ok:
                    score += 10
                    vlm_workflow_confirmed = True
                    feedback_parts.append("VLM process: Partially confirmed")
                elif progression_ok:
                    score += 5
                    feedback_parts.append("VLM process: Some progression")
                else:
                    feedback_parts.append("VLM process: Workflow not confirmed")
            else:
                vlm_query_failed = True
                feedback_parts.append("VLM process check failed")
        else:
            feedback_parts.append("VLM process: Insufficient frames")

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
                    feedback_parts.append("VLM final: Site structure confirmed")
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

        if services_found and static_front and vlm_workflow_confirmed:
            score += 5
            feedback_parts.append("Cross-validated: pages + settings + VLM agree")
            details['cross_validation'] = 'pass'
        elif services_found and not vlm_workflow_confirmed:
            feedback_parts.append("Cross-validation mismatch")
            details['cross_validation'] = 'mismatch'
        elif vlm_workflow_confirmed and not services_found:
            score += 2
            feedback_parts.append("Cross-validation: VLM sees work but pages missing")
            details['cross_validation'] = 'partial'
        else:
            details['cross_validation'] = 'neither'
    else:
        feedback_parts.append("VLM checks skipped")

    # ================================================================
    # PASS CRITERIA
    # ================================================================
    vlm_required_for_pass = vlm_available and not vlm_query_failed

    if vlm_required_for_pass:
        passed = (score >= 70 and services_found and
                  static_front and front_is_services and vlm_workflow_confirmed)
    else:
        passed = score >= 70 and services_found and static_front and front_is_services

    details.update({
        "services_found": services_found,
        "web_dev_found": web_dev.get('found', False),
        "web_dev_parent_ok": web_dev.get('parent_correct', False),
        "mobile_found": mobile.get('found', False),
        "mobile_parent_ok": mobile.get('parent_correct', False),
        "cloud_found": cloud.get('found', False),
        "cloud_parent_ok": cloud.get('parent_correct', False),
        "about_found": about_found,
        "careers_found": careers_found,
        "static_front_page": static_front,
        "front_is_services": front_is_services,
        "title_correct": title_ok,
        "tagline_correct": tagline_ok,
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
