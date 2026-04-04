#!/usr/bin/env python3
"""
Verifier for Split-Editor Workflow task

Checks that three web files (HTML, CSS, JS) have been coordinated:
- HTML updated with new class/ID names
- CSS has matching selectors and styling
- JavaScript targets new IDs
- Cross-file consistency maintained
"""

import sys
import os
import logging
import tempfile
import shutil
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_split_editor_workflow(traj, env_info, task_info):
    """
    Verify that split-editor workflow task was completed successfully.
    
    Verification criteria (7 total):
    1. All three files exist and have substantial content
    2. HTML updated with new identifiers (contact-form, submitBtn)
    3. HTML no longer has old identifiers (old-form, oldSubmit)
    4. CSS has synchronized selectors (.contact-form, #submitBtn)
    5. CSS includes hover state (#submitBtn:hover)
    6. JavaScript targets new ID (submitBtn, not oldSubmit)
    7. Cross-file consistency maintained
    
    Pass threshold: 85% (6/7 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # File paths in container
    html_path = "/home/ga/workspace/contact_form/form.html"
    css_path = "/home/ga/workspace/contact_form/styles.css"
    js_path = "/home/ga/workspace/contact_form/script.js"
    
    temp_dir = tempfile.mkdtemp(prefix='split_editor_verify_')
    
    try:
        # Copy files from container
        local_html = os.path.join(temp_dir, "form.html")
        local_css = os.path.join(temp_dir, "styles.css")
        local_js = os.path.join(temp_dir, "script.js")
        
        files_copied = 0
        try:
            copy_from_env(html_path, local_html)
            if os.path.exists(local_html):
                files_copied += 1
        except Exception as e:
            logger.warning(f"Failed to copy HTML: {e}")
        
        try:
            copy_from_env(css_path, local_css)
            if os.path.exists(local_css):
                files_copied += 1
        except Exception as e:
            logger.warning(f"Failed to copy CSS: {e}")
        
        try:
            copy_from_env(js_path, local_js)
            if os.path.exists(local_js):
                files_copied += 1
        except Exception as e:
            logger.warning(f"Failed to copy JS: {e}")
        
        if files_copied < 3:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"❌ Only {files_copied}/3 files found"
            }
        
        # Read file contents
        with open(local_html, 'r', encoding='utf-8', errors='ignore') as f:
            html_content = f.read()
        
        with open(local_css, 'r', encoding='utf-8', errors='ignore') as f:
            css_content = f.read()
        
        with open(local_js, 'r', encoding='utf-8', errors='ignore') as f:
            js_content = f.read()
        
        criteria_passed = 0
        feedback_parts = []
        
        # Criterion 1: All files have substantial content
        html_substantial = len(html_content) > 100
        css_substantial = len(css_content) > 50
        js_substantial = len(js_content) > 50
        
        if html_substantial and css_substantial and js_substantial:
            criteria_passed += 1
            feedback_parts.append("✅ All files present with content")
        else:
            missing = []
            if not html_substantial:
                missing.append("HTML")
            if not css_substantial:
                missing.append("CSS")
            if not js_substantial:
                missing.append("JS")
            feedback_parts.append(f"❌ Insufficient content in: {', '.join(missing)}")
        
        # Criterion 2: HTML has new identifiers
        has_contact_form_class = re.search(r'class\s*=\s*["\'].*contact-form.*["\']', html_content) is not None
        has_submitBtn_id = re.search(r'id\s*=\s*["\']submitBtn["\']', html_content) is not None
        
        if has_contact_form_class and has_submitBtn_id:
            criteria_passed += 1
            feedback_parts.append("✅ HTML has new identifiers (contact-form, submitBtn)")
        else:
            missing = []
            if not has_contact_form_class:
                missing.append("contact-form class")
            if not has_submitBtn_id:
                missing.append("submitBtn id")
            feedback_parts.append(f"❌ HTML missing: {', '.join(missing)}")
        
        # Criterion 3: HTML no longer has old identifiers
        has_old_form = re.search(r'class\s*=\s*["\'].*old-form.*["\']', html_content) is not None
        has_old_submit = re.search(r'id\s*=\s*["\']oldSubmit["\']', html_content) is not None
        
        if not has_old_form and not has_old_submit:
            criteria_passed += 1
            feedback_parts.append("✅ Old identifiers removed from HTML")
        else:
            remaining = []
            if has_old_form:
                remaining.append("old-form")
            if has_old_submit:
                remaining.append("oldSubmit")
            feedback_parts.append(f"❌ Old identifiers still in HTML: {', '.join(remaining)}")
        
        # Criterion 4: CSS has synchronized selectors
        has_form_selector = re.search(r'\.contact-form\s*\{', css_content) is not None
        has_button_selector = re.search(r'#submitBtn\s*\{', css_content) is not None
        
        if has_form_selector and has_button_selector:
            criteria_passed += 1
            feedback_parts.append("✅ CSS has matching selectors (.contact-form, #submitBtn)")
        else:
            missing = []
            if not has_form_selector:
                missing.append(".contact-form")
            if not has_button_selector:
                missing.append("#submitBtn")
            feedback_parts.append(f"❌ CSS missing selectors: {', '.join(missing)}")
        
        # Criterion 5: CSS includes hover state
        has_hover_state = re.search(r'#submitBtn\s*:\s*hover\s*\{', css_content) is not None
        
        if has_hover_state:
            criteria_passed += 1
            feedback_parts.append("✅ CSS includes #submitBtn:hover state")
        else:
            feedback_parts.append("❌ CSS missing #submitBtn:hover selector")
        
        # Criterion 6: JavaScript targets new ID
        # Look for getElementById('submitBtn') or querySelector('#submitBtn' or 'submitBtn')
        js_targets_new = (
            re.search(r'getElementById\s*\(\s*["\']submitBtn["\']\s*\)', js_content) is not None or
            re.search(r'querySelector\s*\(\s*["\']#?submitBtn["\']\s*\)', js_content) is not None
        )
        js_has_old = 'oldSubmit' in js_content
        
        if js_targets_new and not js_has_old:
            criteria_passed += 1
            feedback_parts.append("✅ JavaScript targets new ID (submitBtn)")
        else:
            issues = []
            if not js_targets_new:
                issues.append("doesn't target submitBtn")
            if js_has_old:
                issues.append("still references oldSubmit")
            feedback_parts.append(f"❌ JavaScript: {', '.join(issues)}")
        
        # Criterion 7: Cross-file consistency (comprehensive check)
        consistency_issues = []
        
        # Check if HTML contact-form class has corresponding CSS
        if has_contact_form_class and not has_form_selector:
            consistency_issues.append("HTML has contact-form but CSS doesn't")
        
        # Check if HTML submitBtn ID has corresponding CSS and JS
        if has_submitBtn_id:
            if not has_button_selector:
                consistency_issues.append("HTML has submitBtn but CSS doesn't")
            if not js_targets_new:
                consistency_issues.append("HTML has submitBtn but JS doesn't target it")
        
        # Check for orphaned references
        if 'old-form' in css_content:
            consistency_issues.append("CSS still has old-form reference")
        if 'oldSubmit' in css_content:
            consistency_issues.append("CSS still has oldSubmit reference")
        
        if len(consistency_issues) == 0:
            criteria_passed += 1
            feedback_parts.append("✅ Cross-file consistency maintained")
        else:
            feedback_parts.append(f"❌ Consistency issues: {'; '.join(consistency_issues)}")
        
        # Calculate final score
        score = int((criteria_passed / 7) * 100)
        passed = score >= 85
        
        # Build detailed feedback
        feedback = " | ".join(feedback_parts)
        feedback += f" | Score: {criteria_passed}/7 criteria ({score}%)"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir, ignore_errors=True)
