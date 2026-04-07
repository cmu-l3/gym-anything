#!/usr/bin/env python3
"""
Verifier for Set Up Digital Archives Section task in WordPress.

Verification Strategy (100 Points):
Programmatic Checks (70 Points):
  1. "Digital Archives" top-level page exists & published (10 pts)
  2. "Public Collections" child page exists & published (10 pts)
  3. "Restricted Manuscripts" child + correct password (10 pts)
  4. "Oral History Recordings" child + correct password (10 pts)
  5. "Photographic Archives" child + correct password (10 pts)
  6. "Research Access Policy" top-level exists & published (10 pts)
  7. All 6 created pages have > 100 characters of content (10 pts)

VLM Trajectory Checks (30 Points):
  8. Trajectory shows page creation, hierarchy setting, and password usage (15 pts)
  9. Final frame shows Pages list with hierarchical indentation (10 pts)
  10. Cross-validation: Agent didn't just write a python script, used UI (5 pts)

Anti-Gaming: Pages must be newly created (timestamp check).
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
    except Exception as e:
        logger.warning(f"VLM query exception: {e}")
    return None


TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an agent creating multiple pages in WordPress.

The agent should:
1. Use the "Add New Page" editor multiple times.
2. Set "Parent" pages in the Page Attributes panel.
3. Set "Password Protection" in the Status & visibility panel.
4. Type descriptive content into the body of the pages.

Assess:
1. WORKFLOW_COMPLETED: Did the agent create multiple pages?
2. HIERARCHY_USED: Did the agent explicitly use the "Parent Page" dropdown?
3. PASSWORD_USED: Did the agent explicitly use the "Password protected" visibility option?
4. CONTENT_ADDED: Did the agent type meaningful text into the page editor body?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "hierarchy_used": true/false,
    "password_used": true/false,
    "content_added": true/false,
    "confidence": "low"/"medium"/"high"
}
"""

FINAL_STATE_PROMPT = """You are analyzing the final state of a WordPress site.

Assess:
1. ADMIN_VISIBLE: Is the WordPress admin interface visible?
2. PAGES_LIST_VISIBLE: Is the "Pages" list visible?
3. HIERARCHY_VISIBLE: Are there child pages visible? (Usually indicated by an em-dash "— " before the page title in the list).
4. SUCCESS_INDICATORS: Does it look like multiple pages like "Digital Archives" and its children were successfully created?

Respond in JSON format:
{
    "admin_visible": true/false,
    "pages_list_visible": true/false,
    "hierarchy_visible": true/false,
    "success_indicators": true/false,
    "confidence": "low"/"medium"/"high"
}
"""


def verify_setup_digital_archives(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected values
    metadata = task_info.get('metadata', {})
    expected_passwords = metadata.get('passwords', {})
    min_length = metadata.get('min_content_length', 100)

    # Copy and parse JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/setup_digital_archives_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load result JSON"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    pages = result.get('pages', [])
    
    # Helper to find a page by title (case-insensitive)
    def find_page(title):
        for p in pages:
            if p.get('post_title', '').strip().lower() == title.lower():
                return p
        return None

    score = 0
    feedback_parts = []
    
    # Track which core pages were successfully verified
    successful_pages = 0

    # 1. Digital Archives (Parent)
    digital_archives = find_page('Digital Archives')
    parent_id = None
    if digital_archives and digital_archives.get('post_status') == 'publish':
        if str(digital_archives.get('post_parent')) == '0':
            score += 10
            parent_id = digital_archives.get('ID')
            successful_pages += 1
            feedback_parts.append("'Digital Archives' correct")
        else:
            feedback_parts.append("'Digital Archives' exists but is not top-level")
    else:
        feedback_parts.append("Missing/Unpublished 'Digital Archives'")

    # 2. Public Collections (Child)
    pub_col = find_page('Public Collections')
    if pub_col and pub_col.get('post_status') == 'publish':
        if parent_id and str(pub_col.get('post_parent')) == str(parent_id):
            if not pub_col.get('post_password'):
                score += 10
                successful_pages += 1
                feedback_parts.append("'Public Collections' correct")
            else:
                feedback_parts.append("'Public Collections' should not have password")
        else:
            feedback_parts.append("'Public Collections' missing parent relation")

    # 3. Restricted Manuscripts (Child + Password)
    rest_man = find_page('Restricted Manuscripts')
    if rest_man and rest_man.get('post_status') == 'publish':
        if parent_id and str(rest_man.get('post_parent')) == str(parent_id):
            if rest_man.get('post_password') == expected_passwords.get('Restricted Manuscripts'):
                score += 10
                successful_pages += 1
                feedback_parts.append("'Restricted Manuscripts' correct")
            else:
                feedback_parts.append("'Restricted Manuscripts' wrong/missing password")
        else:
            feedback_parts.append("'Restricted Manuscripts' missing parent relation")

    # 4. Oral History Recordings (Child + Password)
    oral_hist = find_page('Oral History Recordings')
    if oral_hist and oral_hist.get('post_status') == 'publish':
        if parent_id and str(oral_hist.get('post_parent')) == str(parent_id):
            if oral_hist.get('post_password') == expected_passwords.get('Oral History Recordings'):
                score += 10
                successful_pages += 1
                feedback_parts.append("'Oral History Recordings' correct")
            else:
                feedback_parts.append("'Oral History Recordings' wrong/missing password")
        else:
            feedback_parts.append("'Oral History Recordings' missing parent relation")

    # 5. Photographic Archives (Child + Password)
    photo_arch = find_page('Photographic Archives')
    if photo_arch and photo_arch.get('post_status') == 'publish':
        if parent_id and str(photo_arch.get('post_parent')) == str(parent_id):
            if photo_arch.get('post_password') == expected_passwords.get('Photographic Archives'):
                score += 10
                successful_pages += 1
                feedback_parts.append("'Photographic Archives' correct")
            else:
                feedback_parts.append("'Photographic Archives' wrong/missing password")
        else:
            feedback_parts.append("'Photographic Archives' missing parent relation")

    # 6. Research Access Policy (Top-level)
    research_pol = find_page('Research Access Policy')
    if research_pol and research_pol.get('post_status') == 'publish':
        if str(research_pol.get('post_parent')) == '0':
            if not research_pol.get('post_password'):
                score += 10
                successful_pages += 1
                feedback_parts.append("'Research Access Policy' correct")
            else:
                feedback_parts.append("'Research Access Policy' should not have password")
        else:
            feedback_parts.append("'Research Access Policy' should be top-level")
    else:
        feedback_parts.append("Missing/Unpublished 'Research Access Policy'")

    # 7. Content Length Check
    # Verify that all found targeted pages meet the min_length
    found_targets = [p for p in [digital_archives, pub_col, rest_man, oral_hist, photo_arch, research_pol] if p is not None]
    
    if len(found_targets) > 0:
        valid_content_count = sum(1 for p in found_targets if p.get('content_length', 0) >= min_length)
        # Proportionate score based on how many found pages have good content
        content_score = int(10 * (valid_content_count / 6))
        score += content_score
        if valid_content_count == 6:
            feedback_parts.append("All pages have sufficient content")
        else:
            feedback_parts.append(f"{valid_content_count}/6 pages have sufficient content")

    # Anti-gaming: Ensure these pages were actually created during the task
    created_during_task = all([p.get('created_during_task', False) for p in found_targets])
    if len(found_targets) > 0 and not created_during_task:
        feedback_parts.append("WARNING: Some pages existed before task started")
        score -= 20  # Heavy penalty for pre-existing pages

    # ================================================================
    # VLM VERIFICATION (30 points)
    # ================================================================
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        
        # 8. Trajectory process check
        frames = sample_trajectory_frames(traj, n=5)
        traj_res = _vlm_query(query_vlm, TRAJECTORY_PROMPT, images=frames)
        
        vlm_workflow_ok = False
        if traj_res:
            if traj_res.get("hierarchy_used") and traj_res.get("password_used"):
                score += 15
                vlm_workflow_ok = True
                feedback_parts.append("VLM confirmed hierarchy & password workflow")
            elif traj_res.get("workflow_completed"):
                score += 8
                feedback_parts.append("VLM confirmed basic workflow")
        
        # 9. Final state check
        final_img = get_final_screenshot(traj)
        final_res = _vlm_query(query_vlm, FINAL_STATE_PROMPT, image=final_img)
        
        if final_res:
            if final_res.get("hierarchy_visible") and final_res.get("success_indicators"):
                score += 10
                feedback_parts.append("VLM confirmed hierarchy in final state")
            elif final_res.get("success_indicators"):
                score += 5
                
        # 10. Cross-validation
        if successful_pages >= 4 and vlm_workflow_ok:
            score += 5
            feedback_parts.append("VLM cross-validation passed")
    else:
        # If VLM is not available, scale programmatic score to 100
        # Programmatic max is 70.
        score = int(score * (100.0 / 70.0))
        feedback_parts.append("VLM disabled (score scaled)")

    # Ensure score bounds
    score = min(100, max(0, score))
    
    # Pass condition: Must score at least 60 AND successfully create at least 5 of the 6 core pages
    passed = score >= 60 and successful_pages >= 5

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "successful_pages": successful_pages,
            "digital_archives_id": parent_id
        }
    }