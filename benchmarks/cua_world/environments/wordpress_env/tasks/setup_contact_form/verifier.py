#!/usr/bin/env python3
"""
Verifier for setup_contact_form task in WordPress.

Verification Strategy (Programmatic + VLM):
Programmatic checks (100 points total):
  1. CF7 plugin active (10 pts)
  2. Form exists with correct title (10 pts)
  3. Form fields validation:
     - Name field (required) (8 pts)
     - Email field (required) (8 pts)
     - Inquiry Type dropdown (4 options) (14 pts)
     - Organization field (optional) (5 pts)
     - Message field (required) (8 pts)
  4. Mail recipient configured correctly (10 pts)
  5. "Contact Us" page published (12 pts)
  6. Shortcode embedded in page (15 pts)

Pass Threshold: Score >= 70 AND plugin active AND page published with form shortcode
"""

import json
import tempfile
import os
import logging
import base64
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

TRAJECTORY_PROCESS_PROMPT = """You are analyzing screenshots of an agent creating a Contact Form 7 form and page in WordPress.

For success, the agent should:
1. Navigate to Plugins and activate Contact Form 7
2. Navigate to Contact -> Add New
3. Build the form template with specific required/optional fields and dropdowns
4. Configure the Mail tab for email routing
5. Create a new Page and embed the form shortcode
6. Publish the page

Assess:
1. WORKFLOW_COMPLETED: Did the agent build the form and embed it in a page?
2. FORM_BUILDER_VISIBLE: Is the CF7 form editor interface visible at some point?
3. PAGE_EDITOR_VISIBLE: Is the WordPress page editor visible with a shortcode/block being added?
4. MEANINGFUL_PROGRESSION: Do the frames show real state changes?

Respond in JSON format:
{
    "workflow_completed": true/false,
    "form_builder_visible": true/false,
    "page_editor_visible": true/false,
    "meaningful_progression": true/false,
    "stages_observed": ["list stages"],
    "confidence": "low"/"medium"/"high"
}
"""

def verify_setup_contact_form(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback_parts = []
    score = 0
    max_score = 100

    metadata = task_info.get('metadata', {})
    expected_mail_to = metadata.get('expected_mail_to', 'communications@greenvalley.org')
    expected_options = metadata.get('expected_dropdown_options', [
        "Media Inquiry", "Volunteer Application", "General Question", "Partnership Opportunity"
    ])

    # Load result file
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/setup_contact_form_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export_result.sh may not have run"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {str(e)}"}
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    cf7_active = result.get('cf7_active', False)
    form_found = result.get('form_found', False)
    page_found = result.get('page_found', False)
    form_id = result.get('form_id', '')
    
    # Decode base64 contents
    form_content = ""
    if result.get('form_content_b64'):
        form_content = base64.b64decode(result.get('form_content_b64')).decode('utf-8', errors='ignore')
        
    mail_meta = ""
    if result.get('mail_meta_b64'):
        mail_meta = base64.b64decode(result.get('mail_meta_b64')).decode('utf-8', errors='ignore')
        
    page_content = ""
    if result.get('page_content_b64'):
        page_content = base64.b64decode(result.get('page_content_b64')).decode('utf-8', errors='ignore')

    # 1. CF7 Plugin Active (10 pts)
    if cf7_active:
        score += 10
        feedback_parts.append("Plugin active")
    else:
        feedback_parts.append("Plugin NOT active")

    # 2. Form Exists (10 pts)
    if form_found:
        score += 10
        feedback_parts.append("Form exists")
    else:
        feedback_parts.append("Form 'General Inquiry Form' NOT found")

    # 3. Form Fields Check
    has_req_name = False
    has_req_email = False
    has_req_msg = False
    has_opt_org = False
    dropdown_score = 0
    shortcode_embedded = False

    if form_found and form_content:
        # Check required text field (Name)
        # Match [text* tagname]
        if re.search(r'\[text\*\s+[^\]]+\]', form_content):
            has_req_name = True
            score += 8
            feedback_parts.append("Req Name OK")

        # Check required email field
        if re.search(r'\[email\*\s+[^\]]+\]', form_content):
            has_req_email = True
            score += 8
            feedback_parts.append("Req Email OK")

        # Check optional text field (Organization)
        # Match [text tagname] but NOT [text* tagname]
        # We do this by finding a match of [text without a following *
        if re.search(r'\[text\s+[^\]]+\]', form_content):
            has_opt_org = True
            score += 5
            feedback_parts.append("Opt Org OK")

        # Check required textarea field (Message)
        if re.search(r'\[textarea\*\s+[^\]]+\]', form_content):
            has_req_msg = True
            score += 8
            feedback_parts.append("Req Msg OK")

        # Check dropdown options
        # We find any [select ...] or [select* ...] and verify it contains our required strings
        select_match = re.search(r'\[select\*?\s+([^\]]+)\]', form_content)
        if select_match:
            select_content = select_match.group(1)
            options_found = 0
            for opt in expected_options:
                # Agent might have quotes around it or not
                if opt in select_content or opt.replace(" ", "-") in select_content:
                    options_found += 1
            
            if options_found == 4:
                dropdown_score = 14
                score += 14
                feedback_parts.append("Dropdown OK")
            elif options_found > 0:
                dropdown_score = int((options_found / 4) * 14)
                score += dropdown_score
                feedback_parts.append(f"Dropdown partial ({options_found}/4)")
        else:
            feedback_parts.append("Dropdown missing")

    # 4. Mail Recipient (10 pts)
    mail_ok = False
    if form_found and mail_meta:
        # Simple substring search inside the serialized array is robust enough
        if expected_mail_to in mail_meta:
            mail_ok = True
            score += 10
            feedback_parts.append("Mail routing OK")
        else:
            feedback_parts.append("Mail routing WRONG")

    # 5. Page Published (12 pts)
    if page_found:
        score += 12
        feedback_parts.append("Page published")
    else:
        feedback_parts.append("Page 'Contact Us' NOT found")

    # 6. Shortcode Embedded (15 pts)
    if page_found and page_content:
        # Check if [contact-form-7 ...] is in the page, OR Gutenberg block <!-- wp:contact-form-7...
        if 'contact-form-7' in page_content or 'wpcf7' in page_content:
            shortcode_embedded = True
            score += 15
            feedback_parts.append("Form embedded")
            
            # Bonus check: Does it reference the correct form?
            if form_id and str(form_id) in page_content:
                feedback_parts.append("Exact form ID matched")
        else:
            feedback_parts.append("Form NOT embedded in page")

    # Check Key Criteria for Pass
    key_criteria_met = cf7_active and page_found and shortcode_embedded and form_found
    passed = score >= 70 and key_criteria_met

    # VLM Trajectory (Optional execution)
    if 'gym_anything.vlm' in sys.modules and hasattr(traj, 'frames'):
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                query_vlm = env_info.get('query_vlm')
                vlm_res = _vlm_query(query_vlm, TRAJECTORY_PROCESS_PROMPT, images=frames)
                if vlm_res and not vlm_res.get('workflow_completed', False):
                    # Flag suspicious behavior if VLM strongly disagrees with programmatic
                    logger.warning("VLM process verification failed but programmatic passed.")
        except Exception as e:
            logger.warning(f"VLM verification skipped: {e}")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "cf7_active": cf7_active,
            "form_found": form_found,
            "page_found": page_found,
            "shortcode_embedded": shortcode_embedded,
            "mail_ok": mail_ok
        }
    }