#!/usr/bin/env python3
"""Verifier for create_maven_project task."""

import json
import tempfile
import os
import re
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_create_maven_project(traj, env_info, task_info):
    """Verify that a Maven project was created with correct structure.

    Criteria:
    1. pom.xml exists with correct groupId, artifactId, and joda-time dependency (30 pts)
    2. HelloWorld.java exists with correct content (20 pts)
    3. Greeter.java exists with correct content (20 pts)
    4. Project builds successfully (class files generated) (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/gs-maven')

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
        """Copy a file from the environment and read its contents."""
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # --- Criterion 1: pom.xml (30 points) ---
    pom_content = copy_and_read(f"{project_dir}/pom.xml")
    if pom_content:
        pom_score = 0
        try:
            # Parse XML
            root = ET.fromstring(pom_content)
            ns = {'m': 'http://maven.apache.org/POM/4.0.0'}

            # Check groupId
            group_id_elem = root.find('m:groupId', ns) or root.find('groupId')
            if group_id_elem is not None:
                group_id = group_id_elem.text.strip()
                expected_gid = metadata.get('expected_groupId', 'org.springframework')
                if group_id == expected_gid:
                    pom_score += 8
                    feedback_parts.append(f"groupId correct: {group_id}")
                else:
                    feedback_parts.append(f"groupId mismatch: got '{group_id}', expected '{expected_gid}'")
            else:
                feedback_parts.append("groupId not found in pom.xml")

            # Check artifactId
            artifact_id_elem = root.find('m:artifactId', ns) or root.find('artifactId')
            if artifact_id_elem is not None:
                artifact_id = artifact_id_elem.text.strip()
                expected_aid = metadata.get('expected_artifactId', 'gs-maven')
                if artifact_id == expected_aid:
                    pom_score += 7
                    feedback_parts.append(f"artifactId correct: {artifact_id}")
                else:
                    feedback_parts.append(f"artifactId mismatch: got '{artifact_id}', expected '{expected_aid}'")
            else:
                feedback_parts.append("artifactId not found in pom.xml")

            # Check joda-time dependency
            deps = root.findall('.//m:dependency', ns) or root.findall('.//dependency')
            has_jodatime = False
            for dep in deps:
                aid = dep.find('m:artifactId', ns) or dep.find('artifactId')
                if aid is not None and 'joda-time' in aid.text:
                    has_jodatime = True
                    ver = dep.find('m:version', ns) or dep.find('version')
                    if ver is not None:
                        feedback_parts.append(f"joda-time dependency found (version {ver.text})")
                    break

            if has_jodatime:
                pom_score += 15
            else:
                feedback_parts.append("joda-time dependency not found in pom.xml")

        except ET.ParseError as e:
            feedback_parts.append(f"pom.xml XML parse error: {e}")

        score += pom_score
    else:
        feedback_parts.append("pom.xml not found")

    # --- Criterion 2: HelloWorld.java (20 points) ---
    hw_content = copy_and_read(f"{project_dir}/src/main/java/hello/HelloWorld.java")
    if hw_content:
        hw_score = 0
        if 'package hello' in hw_content:
            hw_score += 5
        if 'org.joda.time' in hw_content:
            hw_score += 5
        if re.search(r'public\s+static\s+void\s+main', hw_content):
            hw_score += 5
        if 'Greeter' in hw_content:
            hw_score += 5
        score += hw_score
        feedback_parts.append(f"HelloWorld.java: {hw_score}/20 pts")
    else:
        feedback_parts.append("HelloWorld.java not found")

    # --- Criterion 3: Greeter.java (20 points) ---
    gr_content = copy_and_read(f"{project_dir}/src/main/java/hello/Greeter.java")
    if gr_content:
        gr_score = 0
        if 'package hello' in gr_content:
            gr_score += 5
        if 'sayHello' in gr_content:
            gr_score += 10
        if re.search(r'return\s+.*["\'].*[Hh]ello', gr_content):
            gr_score += 5
        score += gr_score
        feedback_parts.append(f"Greeter.java: {gr_score}/20 pts")
    else:
        feedback_parts.append("Greeter.java not found")

    # --- Criterion 4: Build success (30 points) ---
    try:
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/classes/hello/HelloWorld.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)
        if magic == b'\xca\xfe\xba\xbe':
            score += 30
            feedback_parts.append("Build successful (HelloWorld.class verified)")
        else:
            feedback_parts.append("HelloWorld.class found but invalid")
    except Exception:
        feedback_parts.append("Build not completed (no .class files)")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task

        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description="Create a Maven project (gs-maven) in IntelliJ IDEA with pom.xml, "
                           "HelloWorld.java, and Greeter.java. Build the project successfully.",
            checklist_items=[
                "IntelliJ IDEA is open and visible",
                "A project creation dialog or new project wizard was used",
                "The project structure shows Java source files in a package",
                "A pom.xml file is visible in the project structure",
                "The project was built (Build menu used or Maven executed)",
                "No build errors are visible in the IDE",
            ]
        )
        if vlm_result:
            vlm_score = vlm_result.get('vlm_score', 0)
            # VLM contributes up to 10 bonus points (not counted in total 100)
            if vlm_result.get('vlm_passed'):
                score = min(score + 10, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Build success is mandatory - must have .class files generated
    build_successful = 'Build successful' in ' '.join(feedback_parts)

    # Must have build success AND good score to pass
    passed = score >= 70 and build_successful

    if not build_successful and score >= 50:
        feedback_parts.append("NOTE: Task incomplete without successful build")

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
