#!/usr/bin/env python3
"""
Verifier for Add Deep Link Activity task.

Verification Logic:
1. File Existence & Structure (Programmatic):
   - DeepLinkActivity.kt exists, extends AppCompatActivity, handles intent.
   - activity_deep_link.xml exists with valid root and TextView.
   - AndroidManifest.xml contains the new activity with proper intent filter.
2. Compilation (Programmatic):
   - Project must build successfully.
3. VLM Verification (Visual):
   - Uses trajectory frames to verify the agent actually performed the work in the IDE.

Scores:
- DeepLinkActivity.kt structure: 25 pts
- Layout XML validity: 15 pts
- AndroidManifest.xml configuration: 25 pts
- Build Success: 20 pts
- VLM Verification: 15 pts
"""

import json
import logging
import os
import re
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_deep_link_activity(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    # 1. Read Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # --- Check 1: DeepLinkActivity.kt (25 pts) ---
    activity_content = result.get("activity_content", "")
    if result.get("activity_exists"):
        subscore = 0
        if "AppCompatActivity" in activity_content:
            subscore += 5
        else:
            feedback_parts.append("DeepLinkActivity does not extend AppCompatActivity")
            
        if "setContentView(R.layout.activity_deep_link)" in activity_content or "setContentView" in activity_content:
            subscore += 5
        else:
            feedback_parts.append("setContentView missing or incorrect")
            
        if "intent" in activity_content and ("data" in activity_content or "getData" in activity_content):
            subscore += 10
        else:
            feedback_parts.append("Intent data extraction missing")
            
        if "lastPathSegment" in activity_content or "pathSegments" in activity_content:
            subscore += 5
        else:
            feedback_parts.append("Path segment extraction missing")
            
        score += subscore
        feedback_parts.append(f"Activity Logic: {subscore}/25")
    else:
        feedback_parts.append("DeepLinkActivity.kt not created (0/25)")

    # --- Check 2: Layout XML (15 pts) ---
    layout_content = result.get("layout_content", "")
    if result.get("layout_exists"):
        subscore = 0
        try:
            # Basic XML validation
            root = ET.fromstring(layout_content)
            subscore += 5 # Valid XML
            
            # Check for TextView
            has_textview = False
            for elem in root.iter():
                if "TextView" in elem.tag:
                    has_textview = True
                    break
            
            if has_textview:
                subscore += 10
            else:
                feedback_parts.append("Layout missing TextView")
        except ET.ParseError:
            feedback_parts.append("Layout file is invalid XML")
            
        score += subscore
        feedback_parts.append(f"Layout XML: {subscore}/15")
    else:
        feedback_parts.append("Layout file not created (0/15)")

    # --- Check 3: AndroidManifest.xml (25 pts) ---
    manifest_content = result.get("manifest_content", "")
    if result.get("manifest_exists"):
        subscore = 0
        # Check for activity registration
        if 'android:name=".DeepLinkActivity"' in manifest_content or 'android:name="com.example.shopeasy.DeepLinkActivity"' in manifest_content:
            subscore += 5
        else:
            feedback_parts.append("DeepLinkActivity not registered in manifest")

        # Check for intent filter components using regex for flexibility
        if re.search(r'android:name="android\.intent\.action\.VIEW"', manifest_content):
            subscore += 5
        else:
            feedback_parts.append("Missing ACTION_VIEW")
            
        if re.search(r'android:name="android\.intent\.category\.BROWSABLE"', manifest_content):
            subscore += 5
        else:
            feedback_parts.append("Missing BROWSABLE category")
            
        if re.search(r'android:scheme="https"', manifest_content) and \
           re.search(r'android:host="shopeasy\.example\.com"', manifest_content) and \
           re.search(r'android:pathPrefix="/product"', manifest_content):
            subscore += 10
        else:
            feedback_parts.append("Data element (scheme/host/path) incorrect")
            
        score += subscore
        feedback_parts.append(f"Manifest: {subscore}/25")
    else:
        feedback_parts.append("Manifest not found (0/25)")

    # --- Check 4: Build Success (20 pts) ---
    if result.get("build_success"):
        score += 20
        feedback_parts.append("Project Build: Success (20/20)")
    else:
        feedback_parts.append("Project Build: Failed (0/20)")

    # --- Check 5: Anti-Gaming & VLM (15 pts) ---
    # We verify if files were modified during the task. If not, score is capped.
    if not result.get("files_modified_during_task") and score > 10:
        feedback_parts.append("Files were not modified during task duration. Possible gaming.")
        score = 0
    else:
        # Perform VLM Verification
        query_vlm = env_info.get('query_vlm')
        vlm_score = 0
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames
                frames = sample_trajectory_frames(traj, num_samples=4)
                
                prompt = """
                You are verifying an Android Studio task.
                The user was supposed to add a 'DeepLinkActivity' and edit the AndroidManifest.xml.
                
                Look at the screenshots. Do you see:
                1. The user editing Kotlin code (DeepLinkActivity.kt)?
                2. The user editing an XML layout?
                3. The user editing AndroidManifest.xml?
                4. A successful build or project view showing these files?
                
                Respond in JSON: {"passed": true/false, "confidence": 0-10, "reason": "..."}
                """
                
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res and vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('passed'):
                        vlm_score = 15
                        feedback_parts.append(f"VLM Verification: Passed ({parsed.get('reason')})")
                    else:
                        feedback_parts.append(f"VLM Verification: Failed ({parsed.get('reason')})")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
                # Fallback: if programmatic checks are perfect, give partial VLM points
                if score >= 85: 
                    vlm_score = 15
                    feedback_parts.append("VLM skipped, awarded full points based on code quality")

        score += vlm_score

    # Final tally
    passed = score >= 60 and result.get("build_success")
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }