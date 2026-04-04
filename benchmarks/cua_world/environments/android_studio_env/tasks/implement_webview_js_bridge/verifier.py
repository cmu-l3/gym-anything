#!/usr/bin/env python3
"""
Verifier for implement_webview_js_bridge task.

Criteria:
1. `WebView` present in layout XML (15 pts)
2. `WebView` initialized and JS enabled in Kotlin (15 pts)
3. Correct Asset URL loaded (15 pts)
4. Javascript Interface added with name "AndroidHelp" (20 pts)
5. `@JavascriptInterface` annotation used (20 pts)
6. `submitTicket` method exists (15 pts)
7. Project compiles (Bonus/Confirmation)
"""

import json
import logging
import re
import tempfile
import os

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_webview_js_bridge(traj, env_info, task_info):
    """Verify that WebView is set up with a JS bridge."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    main_activity_content = result.get("main_activity_content", "")
    layout_content = result.get("layout_content", "")
    build_success = result.get("build_success", False)

    # 1. WebView in Layout (15 pts)
    # Look for <WebView or <android.webkit.WebView
    if re.search(r'<\s*(?:android\.webkit\.)?WebView', layout_content, re.IGNORECASE):
        score += 15
        feedback_parts.append("WebView found in layout")
    else:
        feedback_parts.append("WebView MISSING from layout")

    # 2. JS Enabled (15 pts)
    # settings.javaScriptEnabled = true OR setJavaScriptEnabled(true)
    if re.search(r'(?:settings\.)?javaScriptEnabled\s*=\s*true', main_activity_content) or \
       re.search(r'setJavaScriptEnabled\(\s*true\s*\)', main_activity_content):
        score += 15
        feedback_parts.append("JavaScript enabled")
    else:
        feedback_parts.append("JavaScript NOT enabled")

    # 3. Asset Loaded (15 pts)
    # loadUrl("file:///android_asset/help_center.html")
    if re.search(r'loadUrl\s*\(\s*["\']file:///android_asset/help_center\.html["\']', main_activity_content):
        score += 15
        feedback_parts.append("Correct asset URL loaded")
    else:
        feedback_parts.append("Incorrect or missing asset URL")

    # 4. Interface Injected (20 pts)
    # addJavascriptInterface(..., "AndroidHelp")
    if re.search(r'addJavascriptInterface\s*\(.*,\s*["\']AndroidHelp["\']\s*\)', main_activity_content):
        score += 20
        feedback_parts.append("JS Interface 'AndroidHelp' injected")
    else:
        feedback_parts.append("JS Interface injection missing or wrong name")

    # 5. Annotation Present (20 pts)
    # @JavascriptInterface or @android.webkit.JavascriptInterface
    if re.search(r'@(?:android\.webkit\.)?JavascriptInterface', main_activity_content):
        score += 20
        feedback_parts.append("@JavascriptInterface annotation found")
    else:
        feedback_parts.append("@JavascriptInterface annotation MISSING (Security Risk/Functional Fail)")

    # 6. Method Signature (15 pts)
    # fun submitTicket(id: String) or similar
    if re.search(r'fun\s+submitTicket\s*\(\s*\w+\s*:\s*String', main_activity_content):
        score += 15
        feedback_parts.append("submitTicket method found")
    else:
        feedback_parts.append("submitTicket method MISSING or incorrect signature")

    # Penalty if build failed but code looks okay? Or bonus?
    # Let's just note it in feedback.
    if not build_success:
        feedback_parts.append("WARNING: Project build failed")

    return {
        "passed": score >= 85,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }