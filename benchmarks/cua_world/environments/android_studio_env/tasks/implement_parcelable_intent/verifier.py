#!/usr/bin/env python3
"""
Verifier for implement_parcelable_intent task.

Checks:
1. Build Success (50 pts): Does './gradlew assembleDebug' pass?
2. Plugin Applied (20 pts): Is 'kotlin-parcelize' or 'id("kotlin-parcelize")' in build.gradle.kts?
3. Annotation Present (15 pts): Is '@Parcelize' used in Item.kt?
4. Interface Implemented (15 pts): Does Item implement 'Parcelable'?
"""

import json
import logging
import os
import re
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def _read_json_from_env(copy_from_env, container_path: str) -> dict:
    """Copy a JSON file out of the container and return parsed dict."""
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env(container_path, tmp.name)
        with open(tmp.name, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception as exc:
        logger.debug("Could not read JSON %s: %s", container_path, exc)
        return {}
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)

def verify_implement_parcelable_intent(traj, env_info, task_info):
    """Verify that Item class was correctly parcelized and project builds."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result from export script
    result = _read_json_from_env(copy_from_env, "/tmp/task_result.json")
    
    build_success = result.get("build_success", False)
    item_content = result.get("item_content", "")
    build_gradle_content = result.get("build_gradle_content", "")
    
    score = 0
    feedback_parts = []
    
    # 1. Check Build Success (50 pts)
    # This implies that the compilation error in MainActivity (intent.putExtra) was resolved,
    # which implies Item implements Parcelable correctly.
    if build_success:
        score += 50
        feedback_parts.append("Project builds successfully (50/50)")
    else:
        feedback_parts.append("Project build failed (0/50)")
        
    # 2. Check Plugin in build.gradle.kts (20 pts)
    # Look for: id("kotlin-parcelize") OR id 'kotlin-parcelize'
    if re.search(r'id\s*\(\s*"kotlin-parcelize"\s*\)', build_gradle_content) or \
       re.search(r"id\s*'kotlin-parcelize'", build_gradle_content) or \
       re.search(r'plugins\s*{[^}]*kotlin-parcelize', build_gradle_content, re.DOTALL):
        score += 20
        feedback_parts.append("Parcelize plugin applied (20/20)")
    else:
        feedback_parts.append("Parcelize plugin missing in build.gradle.kts (0/20)")

    # 3. Check Annotation in Item.kt (15 pts)
    if "@Parcelize" in item_content:
        score += 15
        feedback_parts.append("@Parcelize annotation present (15/15)")
    elif "import kotlinx.parcelize.Parcelize" in item_content:
        # Maybe they imported it but didn't use it yet (unlikely if build passed, but possible edge case)
        score += 5
        feedback_parts.append("Parcelize import found but annotation check ambiguous")
    else:
        feedback_parts.append("@Parcelize annotation missing (0/15)")

    # 4. Check Interface in Item.kt (15 pts)
    if ": Parcelable" in item_content or ", Parcelable" in item_content:
        score += 15
        feedback_parts.append("Parcelable interface implemented (15/15)")
    else:
        feedback_parts.append("Parcelable interface missing (0/15)")

    # Anti-gaming check: File modification
    file_modified = result.get("file_modified_during_task", False)
    if not file_modified and score > 0:
        score = 0
        feedback_parts = ["FAILED: No changes detected to source files during task execution."]

    passed = (score >= 85) and build_success

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }