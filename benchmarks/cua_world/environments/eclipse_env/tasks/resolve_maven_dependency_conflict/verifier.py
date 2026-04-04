#!/usr/bin/env python3
"""
Verifier for resolve_maven_dependency_conflict task.

Criteria:
1. pom.xml is valid and modified (10 pts)
2. pom.xml still contains httpclient (20 pts)
3. pom.xml contains an exclusion for commons-logging (40 pts)
4. Effective dependency tree does NOT contain commons-logging (30 pts)
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_resolve_maven_dependency_conflict(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Read result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 1. POM Existence and Modification (10 pts)
    if result.get('pom_exists'):
        if result.get('pom_modified'):
            score += 10
            feedback_parts.append("POM modified")
        else:
            feedback_parts.append("POM not modified (timestamps match start)")
    else:
        return {"passed": False, "score": 0, "feedback": "pom.xml deleted"}

    # Parse POM content
    pom_content = result.get('pom_content', '')
    try:
        # Strip namespace for easier parsing if needed, but ET handles it
        # Just simple string checks first for robustness against invalid XML
        if "httpclient" in pom_content:
            score += 20
            feedback_parts.append("httpclient dependency preserved")
        else:
            feedback_parts.append("httpclient dependency removed (FAIL)")
            
        # 2. Check for exclusion tag (40 pts)
        # We look for <exclusion>...commons-logging...</exclusion>
        # XML parsing is better
        root = ET.fromstring(pom_content)
        # Namespaces in Maven POMs can be annoying, verify with ignoring namespaces
        has_exclusion = False
        
        # Helper to strip namespace from tag
        def strip_ns(tag):
            return tag.split('}')[-1] if '}' in tag else tag

        for dep in root.findall(".//{*}dependency"):
            art_id = dep.find("{*}artifactId")
            if art_id is not None and strip_ns(art_id.tag) == "artifactId" and art_id.text == "httpclient":
                exclusions = dep.find("{*}exclusions")
                if exclusions is not None:
                    for exc in exclusions.findall("{*}exclusion"):
                        exc_art = exc.find("{*}artifactId")
                        if exc_art is not None and exc_art.text == "commons-logging":
                            has_exclusion = True
                            break
        
        if has_exclusion:
            score += 40
            feedback_parts.append("Exclusion tag found in POM")
        else:
            feedback_parts.append("Exclusion tag NOT found in httpclient dependency")

    except ET.ParseError:
        feedback_parts.append("POM is invalid XML")

    # 3. Check Effective Dependency Tree (30 pts)
    # This proves the build actually respects the exclusion
    if not result.get('commons_logging_present_in_tree'):
        score += 30
        feedback_parts.append("commons-logging successfully excluded from build")
    else:
        feedback_parts.append("commons-logging still present in dependency tree")

    # VLM Verification (Bonus/Confirmation)
    # If score is borderline, we could check VLM, but dependency tree is ground truth.
    # We'll use VLM just to verify UI usage if we wanted, but logic is strong enough.

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }