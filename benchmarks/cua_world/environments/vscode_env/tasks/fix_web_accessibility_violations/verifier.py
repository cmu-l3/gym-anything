#!/usr/bin/env python3
"""
Verifier for the fix_web_accessibility_violations task.

Evaluates 7 WCAG 2.1 Level AA accessibility criteria fixes across HTML, CSS, and JS files.
Uses regex and basic mathematical contrast ratio computation.

Criteria:
1. `lang="en"` added to <html> in all 3 HTML files (10 pts)
2. `alt` attribute added to <img> tags in index.html (15 pts)
3. Form `<input>` elements have `<label>` or `aria-label` in login.html (15 pts)
4. CSS color contrast meets 4.5:1 for 3 specific classes (15 pts)
5. Semantic interactive element (button or role="button"+tabindex) used for export-btn (15 pts)
6. Skip navigation link (`href="#main-content"`) added to all 3 HTML files (15 pts)
7. Table `<th>` headers have `scope="col"` and/or `scope="row"` in reports.html (15 pts)
"""

import sys
import os
import json
import re
import logging
import tempfile
from html.parser import HTMLParser

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# ─── COLOR CONTRAST UTILS ────────────────────────────────────────────────

def hex_to_rgb(hex_color):
    """Convert hex string (e.g., '#ffffff' or '#fff') to (r, g, b) tuple."""
    hex_color = hex_color.lstrip('#')
    if len(hex_color) == 3:
        hex_color = ''.join([c*2 for c in hex_color])
    if len(hex_color) != 6:
        return (0, 0, 0) # Fallback
    return tuple(int(hex_color[i:i+2], 16) for i in (0, 2, 4))

def relative_luminance(r, g, b):
    """Calculate relative luminance for sRGB."""
    def channel_luminance(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * channel_luminance(r) + 0.7152 * channel_luminance(g) + 0.0722 * channel_luminance(b)

def contrast_ratio(hex1, hex2):
    """Calculate contrast ratio between two hex colors."""
    l1 = relative_luminance(*hex_to_rgb(hex1))
    l2 = relative_luminance(*hex_to_rgb(hex2))
    light = max(l1, l2)
    dark = min(l1, l2)
    return (light + 0.05) / (dark + 0.05)

def get_css_color(css_content, selector):
    """Extract the hex color value for a specific CSS class/selector."""
    # Find the block for the selector
    pattern = re.compile(re.escape(selector) + r'\s*\{([^}]+)\}')
    match = pattern.search(css_content)
    if not match:
        return None
    block = match.group(1)
    # Extract color property
    color_match = re.search(r'color\s*:\s*(#[0-9a-fA-F]{3,6})', block)
    if color_match:
        return color_match.group(1)
    return None


# ─── VERIFICATION ENGINE ────────────────────────────────────────────────

def verify_accessibility_fixes(traj, env_info, task_info):
    """Main verification function."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='a11y_verify_')

    try:
        result_src = "/tmp/a11y_result.json"
        local_result = os.path.join(temp_dir, "a11y_result.json")

        try:
            copy_from_env(result_src, local_result)
        except Exception as e:
            logger.error(f"Failed to copy result file: {e}")
            return {"passed": False, "score": 0, "feedback": f"Could not access result file: {e}"}

        if not os.path.exists(local_result) or os.path.getsize(local_result) == 0:
            return {"passed": False, "score": 0, "feedback": "Result file not found or empty"}

        with open(local_result, 'r') as f:
            data = json.load(f)

        score = 0
        feedback = []

        # File contents
        html_files = ['index.html', 'login.html', 'reports.html']
        index_html = data.get('index.html', {}).get('content', '')
        login_html = data.get('login.html', {}).get('content', '')
        reports_html = data.get('reports.html', {}).get('content', '')
        styles_css = data.get('css/styles.css', {}).get('content', '')
        start_time = data.get('task_start_time', 0)

        # Anti-gaming: Content preservation check
        for fname in html_files:
            content = data.get(fname, {}).get('content', '')
            if '<!-- AGENCY_DASHBOARD_V2 -->' not in content or len(content) < 500:
                return {
                    "passed": False,
                    "score": 0,
                    "feedback": f"❌ Anti-gaming check failed: {fname} has been severely truncated or completely replaced."
                }
            # Check modification time to ensure agent did *something*
            mtime = data.get(fname, {}).get('mtime', 0)
            if mtime < start_time:
                feedback.append(f"⚠️ {fname} was not modified during task session.")

        # ─── Check 1: HTML lang attribute (10 pts) ──────────────────────
        lang_passed_count = 0
        for fname, content in [('index.html', index_html), ('login.html', login_html), ('reports.html', reports_html)]:
            if re.search(r'<html[^>]*\blang\s*=\s*["\'][a-zA-Z\-]+["\']', content, re.IGNORECASE):
                lang_passed_count += 1

        if lang_passed_count == 3:
            score += 10
            feedback.append("✅ [10/10] `lang` attribute added to all HTML files.")
        elif lang_passed_count > 0:
            score += 5
            feedback.append(f"⚠️ [5/10] `lang` attribute added to {lang_passed_count}/3 HTML files.")
        else:
            feedback.append("❌ [0/10] Missing `lang` attribute on <html> tags.")


        # ─── Check 2: Image alt text in index.html (15 pts) ─────────────
        img_tags = re.findall(r'<img[^>]+>', index_html, re.IGNORECASE)
        alt_valid_count = 0
        for img in img_tags:
            alt_match = re.search(r'alt\s*=\s*(["\'])(.*?)\1', img, re.IGNORECASE)
            if alt_match and alt_match.group(2).strip() != "":
                alt_valid_count += 1

        if len(img_tags) > 0 and alt_valid_count == len(img_tags):
            score += 15
            feedback.append("✅ [15/15] Descriptive `alt` attributes added to all images in index.html.")
        elif alt_valid_count > 0:
            score += 7
            feedback.append(f"⚠️ [7/15] `alt` text added to {alt_valid_count}/{len(img_tags)} images.")
        else:
            feedback.append("❌ [0/15] Images still lack descriptive `alt` attributes.")


        # ─── Check 3: Form Input Labels in login.html (15 pts) ──────────
        input_ids = re.findall(r'<input[^>]*id\s*=\s*["\']([^"\']+)["\']', login_html, re.IGNORECASE)
        labeled_count = 0
        for input_id in input_ids:
            # Check for <label for="id">
            has_for_label = bool(re.search(r'<label[^>]*for\s*=\s*["\']' + re.escape(input_id) + r'["\']', login_html, re.IGNORECASE))
            # Check for aria-label on the input itself
            input_tag_match = re.search(r'<input[^>]*id\s*=\s*["\']' + re.escape(input_id) + r'["\'][^>]*>', login_html, re.IGNORECASE)
            has_aria_label = False
            if input_tag_match:
                has_aria_label = bool(re.search(r'aria-label\s*=', input_tag_match.group(0), re.IGNORECASE))

            if has_for_label or has_aria_label:
                labeled_count += 1

        if len(input_ids) > 0 and labeled_count == len(input_ids):
            score += 15
            feedback.append("✅ [15/15] All form inputs have associated labels or aria-labels.")
        elif labeled_count > 0:
            score += 7
            feedback.append(f"⚠️ [7/15] {labeled_count}/{len(input_ids)} form inputs have labels.")
        else:
            feedback.append("❌ [0/15] Form inputs are missing programmatic labels.")


        # ─── Check 4: CSS Color Contrast (15 pts) ───────────────────────
        bg_color = "#ffffff"
        classes_to_check = ['.sidebar-link', '.stat-label', '.muted-text']
        contrast_passed = 0

        for cls in classes_to_check:
            color = get_css_color(styles_css, cls)
            if color:
                cr = contrast_ratio(color, bg_color)
                if cr >= 4.45: # Allowing tiny rounding margin for 4.5
                    contrast_passed += 1
                else:
                    feedback.append(f"❌ Contrast for {cls} ({color}) is {cr:.2f}:1 (Needs 4.5:1)")

        if contrast_passed == len(classes_to_check):
            score += 15
            feedback.append("✅ [15/15] All identified CSS classes meet the 4.5:1 contrast ratio.")
        elif contrast_passed > 0:
            score += 7
            feedback.append(f"⚠️ [7/15] {contrast_passed}/{len(classes_to_check)} CSS classes meet contrast requirements.")
        else:
            feedback.append("❌ [0/15] Color contrast fixes were not correctly applied to CSS.")


        # ─── Check 5: Semantic Interactive Element (15 pts) ─────────────
        # Can be <button id="export-btn"> OR <div id="export-btn" role="button" tabindex="0">
        is_semantic = False
        button_tag_match = re.search(r'<button[^>]*id\s*=\s*["\']export-btn["\']', reports_html, re.IGNORECASE)
        div_tag_match = re.search(r'<div[^>]*id\s*=\s*["\']export-btn["\'][^>]*>', reports_html, re.IGNORECASE)

        if button_tag_match:
            is_semantic = True
        elif div_tag_match:
            div_tag = div_tag_match.group(0)
            has_role = bool(re.search(r'role\s*=\s*["\']button["\']', div_tag, re.IGNORECASE))
            has_tabindex = bool(re.search(r'tabindex\s*=\s*["\']\d+["\']', div_tag, re.IGNORECASE))
            if has_role and has_tabindex:
                is_semantic = True

        if is_semantic:
            score += 15
            feedback.append("✅ [15/15] Interactive 'Export' element made semantic and keyboard accessible.")
        else:
            feedback.append("❌ [0/15] 'Export' element is still a non-semantic, non-focusable div.")


        # ─── Check 6: Skip Navigation Link (15 pts) ─────────────────────
        skip_nav_count = 0
        for content in [index_html, login_html, reports_html]:
            if re.search(r'<a[^>]*href\s*=\s*["\']#main-content["\']', content, re.IGNORECASE):
                skip_nav_count += 1

        if skip_nav_count == 3:
            score += 15
            feedback.append("✅ [15/15] Skip navigation link added to all HTML files.")
        elif skip_nav_count > 0:
            score += 7
            feedback.append(f"⚠️ [7/15] Skip navigation link found in {skip_nav_count}/3 HTML files.")
        else:
            feedback.append("❌ [0/15] Skip navigation links are missing.")


        # ─── Check 7: Table Headers Scope (15 pts) ──────────────────────
        th_tags = re.findall(r'<th[^>]*>', reports_html, re.IGNORECASE)
        scope_col_count = sum(1 for tag in th_tags if re.search(r'scope\s*=\s*["\']col["\']', tag, re.IGNORECASE))
        scope_row_count = sum(1 for tag in th_tags if re.search(r'scope\s*=\s*["\']row["\']', tag, re.IGNORECASE))
        has_scopes = scope_col_count > 0 or scope_row_count > 0

        if has_scopes:
            score += 15
            feedback.append("✅ [15/15] Scope attributes added to table headers.")
        else:
            feedback.append("❌ [0/15] Data table headers lack `scope` attributes.")


        # ─── VLM Verification (Visual Check on Final Screenshot) ────────
        # Only evaluate VLM if available, purely to ensure UI isn't utterly broken
        query_vlm = env_info.get('query_vlm')
        from gym_anything.vlm import get_final_screenshot
        final_screen = get_final_screenshot(traj)

        vlm_feedback = ""
        if query_vlm and final_screen:
            prompt = """Look at this screenshot of a web application.
            Does the interface look like a functioning dashboard (with a sidebar, header, and content area)?
            Answer strictly in JSON: {"dashboard_visible": true/false}"""
            vlm_res = query_vlm(prompt=prompt, image=final_screen)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if not parsed.get("dashboard_visible", True):
                    # Penalize heavily if the agent destroyed the layout
                    score = int(score * 0.5)
                    vlm_feedback = "\n⚠️ Visual structure appears broken (Score halved)."
                else:
                    vlm_feedback = "\n✅ Visual dashboard structure maintained."

        passed = score >= 60
        full_feedback = "\n".join(feedback) + vlm_feedback

        return {
            "passed": passed,
            "score": score,
            "feedback": full_feedback
        }

    except Exception as e:
        logger.error(f"Error in verifier: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verifier exception: {e}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)