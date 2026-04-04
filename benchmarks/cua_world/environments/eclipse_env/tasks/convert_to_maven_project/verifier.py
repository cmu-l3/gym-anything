#!/usr/bin/env python3
"""Verifier for convert_to_maven_project task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_convert_to_maven_project(traj, env_info, task_info):
    """
    Verify the conversion of a legacy Java project to Maven.
    
    Criteria:
    1. Maven nature added to .project (20 pts)
    2. pom.xml exists and is valid (10 pts)
    3. pom.xml has correct GroupId/ArtifactId (10 pts)
    4. pom.xml has joda-time dependency (20 pts)
    5. .classpath has Maven container (10 pts)
    6. .classpath does NOT have manual JAR (10 pts)
    7. Project compiled successfully (target/classes exists) (20 pts)
    
    Total: 100 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_gid = metadata.get('expected_group_id', 'com.legacy.dateutils')
    expected_aid = metadata.get('expected_artifact_id', 'DateUtilsLegacy')
    
    score = 0
    feedback_parts = []
    
    # Read result file
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env("/tmp/task_result.json", tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}

    # Extract contents
    project_content = result.get('dot_project_content', '')
    pom_content = result.get('pom_content', '')
    classpath_content = result.get('classpath_content', '')
    pom_exists = result.get('pom_exists', False)
    
    # 1. Maven Nature (20 pts)
    if 'org.eclipse.m2e.core.maven2Nature' in project_content:
        score += 20
        feedback_parts.append("Maven nature found in .project")
    else:
        feedback_parts.append("Maven nature NOT found in .project")

    # 2. POM Exists (10 pts)
    if pom_exists and pom_content.strip():
        score += 10
        feedback_parts.append("pom.xml exists")
        
        # Parse POM
        try:
            # Strip namespace for easier parsing if needed, or handle namespaces
            # A simple way to handle default namespaces in ElementTree is just string searching for simple checks,
            # or using regex for robustness against namespace prefixes.
            # We'll use ElementTree with wildcard namespace handling or local-name() if we were using xpath,
            # but standard ET is limited. Let's use simple string checks/regex for robustness against XML nuances
            # unless we need strict structure.
            
            # 3. Correct Coordinates (10 pts)
            # Regex is often safer here against namespace variations in generated POMs
            gid_match = re.search(r'<groupId>([^<]+)</groupId>', pom_content)
            aid_match = re.search(r'<artifactId>([^<]+)</artifactId>', pom_content)
            
            # Note: The first groupId/artifactId usually belong to the project, dependencies are nested.
            # We need to be careful. Let's try to parse properly.
            root = ET.fromstring(pom_content)
            # Remove namespace for easier tag finding
            for elem in root.iter():
                if '}' in elem.tag:
                    elem.tag = elem.tag.split('}', 1)[1]
            
            proj_gid = root.find('groupId')
            proj_aid = root.find('artifactId')
            
            # If groupId is not direct child, it might be inherited from parent, but for this task we expect explicit.
            current_gid = proj_gid.text if proj_gid is not None else ""
            current_aid = proj_aid.text if proj_aid is not None else ""
            
            if current_gid == expected_gid and current_aid == expected_aid:
                score += 10
                feedback_parts.append("Project coordinates correct")
            else:
                feedback_parts.append(f"Coordinates mismatch (Expected {expected_gid}:{expected_aid}, Found {current_gid}:{current_aid})")

            # 4. Dependency Check (20 pts)
            deps = root.findall('.//dependency')
            found_joda = False
            for dep in deps:
                d_gid = dep.find('groupId')
                d_aid = dep.find('artifactId')
                if d_gid is not None and d_aid is not None:
                    if 'joda-time' in d_gid.text and 'joda-time' in d_aid.text:
                        found_joda = True
                        break
            
            if found_joda:
                score += 20
                feedback_parts.append("joda-time dependency found")
            else:
                feedback_parts.append("joda-time dependency NOT found in pom.xml")

        except ET.ParseError:
            feedback_parts.append("pom.xml is invalid XML")
    else:
        feedback_parts.append("pom.xml missing or empty")

    # 5. Classpath Maven Container (10 pts)
    if 'org.eclipse.m2e.MAVEN2_CLASSPATH_CONTAINER' in classpath_content:
        score += 10
        feedback_parts.append("Maven classpath container found")
    else:
        feedback_parts.append("Maven classpath container missing")

    # 6. Manual JAR Removed (10 pts)
    if 'lib/joda-time' not in classpath_content:
        score += 10
        feedback_parts.append("Manual JAR removed from classpath")
    else:
        feedback_parts.append("Manual JAR still present in classpath")

    # 7. Build Success (20 pts)
    # Check if target/classes has .class files (Maven build output)
    if result.get('class_files_exist', False):
        score += 20
        feedback_parts.append("Maven build artifacts found (target/classes)")
    elif result.get('bin_files_exist', False) and not result.get('class_files_exist', False):
        # Only bin/ exists - implies they didn't switch output folder to Maven standard
        feedback_parts.append("Build artifacts found in bin/ (Warning: Not standard Maven layout)")
        score += 10 # Partial credit
    else:
        feedback_parts.append("No compilation artifacts found")

    # VLM Verification (Trajectory Check)
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        vlm_res = vlm_verify_eclipse_task(
            traj, env_info, 
            "Convert Java project to Maven and add joda-time dependency",
            ["'Convert to Maven Project' dialog or menu used", "pom.xml file visible in editor", "Project has 'M' icon or Maven indicators"]
        )
        if vlm_res and vlm_res.get('vlm_passed'):
            feedback_parts.append("VLM: Workflow visually verified")
    except Exception:
        pass

    passed = score >= 80  # Require high compliance for this structural task
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }