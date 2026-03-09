#!/usr/bin/env python3
"""
Verifier for Fix Accessibility Violations task
Checks that all WCAG violations were properly addressed in the React component
"""

import sys
import os
import re
import logging
import tempfile
import shutil

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from vscode_verification_utils import read_file_content

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_accessibility_fixes(traj, env_info, task_info):
    """
    Verify that accessibility violations were fixed in DataTable.jsx
    
    Checks:
    1. Semantic button (replaced <div> with <button>)
    2. Button has descriptive aria-label
    3. Table has <thead> with <th scope="col"> headers
    4. Table has <caption> or aria-label
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task information (unused)
        
    Returns:
        Dict with passed, score, feedback
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "❌ Copy function not available"
        }
    
    container_path = "/home/ga/workspace/accessibility-fixes/src/components/DataTable.jsx"
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.jsx')
    
    try:
        # Copy the component file
        copy_from_env(container_path, temp_file.name)
        
        if not os.path.exists(temp_file.name):
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ DataTable.jsx not found"
            }
        
        if os.path.getsize(temp_file.name) == 0:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ DataTable.jsx is empty"
            }
        
        # Read file content
        content = read_file_content(temp_file.name)
        
        if not content:
            return {
                "passed": False,
                "score": 0,
                "feedback": "❌ Failed to read DataTable.jsx"
            }
        
        # Track fixes applied
        fixes_applied = []
        issues_found = []
        score = 0.0
        
        # CHECK 1: Semantic button (not div) - 25 points
        # Look for <button> with onClick={handleSort}
        button_pattern = r'<button[^>]*onClick\s*=\s*\{handleSort\}'
        div_button_pattern = r'<div[^>]*className\s*=\s*["\']sort-button["\'][^>]*onClick'
        
        has_button = bool(re.search(button_pattern, content))
        has_div_button = bool(re.search(div_button_pattern, content))
        
        if has_button and not has_div_button:
            fixes_applied.append("✅ [1/4] Replaced <div> with semantic <button> element")
            score += 0.25
        elif has_button and has_div_button:
            issues_found.append("⚠️ [1/4] Both <button> and <div> present - may not have removed <div>")
            score += 0.15
        elif has_div_button:
            issues_found.append("❌ [1/4] Sort control is still <div> instead of <button>")
        else:
            issues_found.append("❌ [1/4] No sort button found")
        
        # CHECK 2: ARIA label on button - 25 points
        # Must be on button element and be descriptive
        button_aria_pattern = r'<button[^>]*aria-label\s*=\s*["\']([^"\']+)["\']'
        aria_match = re.search(button_aria_pattern, content)
        
        if aria_match:
            label_text = aria_match.group(1)
            label_lower = label_text.lower()
            
            # Check that label mentions "sort" and is descriptive (>10 chars)
            if 'sort' in label_lower and len(label_text) >= 10:
                fixes_applied.append(f"✅ [2/4] Added descriptive aria-label: '{label_text}'")
                score += 0.25
            elif 'sort' in label_lower:
                issues_found.append(f"⚠️ [2/4] aria-label present but too short: '{label_text}' (needs 10+ chars)")
                score += 0.15
            else:
                issues_found.append(f"⚠️ [2/4] aria-label present but doesn't mention 'sort': '{label_text}'")
                score += 0.10
        else:
            # Check if aria-label exists anywhere near button
            if 'aria-label' in content:
                issues_found.append("⚠️ [2/4] aria-label found but not on button element")
                score += 0.05
            else:
                issues_found.append("❌ [2/4] Missing aria-label on sort button")
        
        # CHECK 3: Table has <thead> with <th scope="col"> - 25 points
        has_thead = '<thead>' in content
        th_scope_pattern = r'<th[^>]*scope\s*=\s*["\']col["\']'
        th_matches = re.findall(th_scope_pattern, content)
        th_count = len(th_matches)
        
        if has_thead and th_count >= 3:
            fixes_applied.append(f"✅ [3/4] Added <thead> with {th_count} <th scope=\"col\"> headers")
            score += 0.25
        elif has_thead and th_count > 0:
            issues_found.append(f"⚠️ [3/4] <thead> present but only {th_count} <th> headers (expected 3: Name, Email, Role)")
            score += 0.15
        elif has_thead:
            issues_found.append("⚠️ [3/4] <thead> added but <th> elements missing scope=\"col\" attribute")
            score += 0.10
        else:
            # Check if <th> exists without <thead>
            if '<th' in content:
                issues_found.append("❌ [3/4] <th> elements found but no <thead> wrapper")
                score += 0.05
            else:
                issues_found.append("❌ [3/4] Missing <thead> with semantic <th scope=\"col\"> headers")
        
        # CHECK 4: Table has <caption> or aria-label - 25 points
        caption_pattern = r'<caption>([^<]+)</caption>'
        caption_match = re.search(caption_pattern, content)
        
        table_aria_pattern = r'<table[^>]*aria-label\s*=\s*["\']([^"\']+)["\']'
        table_aria_match = re.search(table_aria_pattern, content)
        
        if caption_match:
            caption_text = caption_match.group(1).strip()
            if len(caption_text) >= 5:
                fixes_applied.append(f"✅ [4/4] Added table <caption>: '{caption_text}'")
                score += 0.25
            else:
                issues_found.append(f"⚠️ [4/4] Caption too short: '{caption_text}'")
                score += 0.15
        elif table_aria_match:
            aria_text = table_aria_match.group(1).strip()
            if len(aria_text) >= 5:
                fixes_applied.append(f"✅ [4/4] Added aria-label to table: '{aria_text}'")
                score += 0.25
            else:
                issues_found.append(f"⚠️ [4/4] Table aria-label too short: '{aria_text}'")
                score += 0.15
        else:
            issues_found.append("❌ [4/4] Missing <caption> or aria-label on table")
        
        # ADDITIONAL CHECKS: Verify structure wasn't broken
        if '<tbody>' not in content:
            issues_found.append("⚠️ Warning: <tbody> removed - may break table structure")
            score = max(0, score - 0.05)
        
        if 'handleSort' not in content:
            issues_found.append("⚠️ Warning: handleSort function reference missing")
        
        # Compile feedback
        feedback_parts = []
        
        # Add score summary
        score_percent = int(score * 100)
        feedback_parts.append(f"Score: {score_percent}/100")
        feedback_parts.append("")
        
        if fixes_applied:
            feedback_parts.append("✅ Fixes Applied:")
            for fix in fixes_applied:
                feedback_parts.append(f"  {fix}")
        
        if issues_found:
            feedback_parts.append("")
            feedback_parts.append("❌ Remaining Issues:")
            for issue in issues_found:
                feedback_parts.append(f"  {issue}")
        
        feedback = "\n".join(feedback_parts)
        
        # Success threshold: 90% (0.9) - all 4 fixes must be applied correctly
        passed = score >= 0.9
        
        if passed:
            feedback = "✅✅✅ All accessibility violations fixed! WCAG compliant! ✅✅✅\n\n" + feedback
        else:
            feedback = f"❌ Task incomplete - {len(issues_found)} issue(s) remaining\n\n" + feedback
        
        logger.info(f"Verification result: passed={passed}, score={score:.2f}")
        
        return {
            "passed": passed,
            "score": score_percent,
            "feedback": feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    
    finally:
        # Cleanup temp file
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
