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
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/gs-maven')

    score = 0
    feedback_parts = []

    # --- Anti-cheating check: Verify sample data was removed ---
    # If the original sample files still exist in /workspace/data/, this indicates
    # the setup script didn't complete properly (potential race condition)
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
        tmp.close()
        copy_from_env('/workspace/data/gs-maven/pom.xml', tmp.name)
        # If we got here, sample data still exists - setup may not have completed
        os.unlink(tmp.name)
        logger.warning("Sample data still exists - possible setup race condition")
        # We don't fail, but log this for debugging
    except Exception:
        pass  # Expected - sample data should be deleted

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
            maven_ns_prefix = '{http://maven.apache.org/POM/4.0.0}'

            # Check groupId (use full namespace)
            group_id_elem = root.find(f'{maven_ns_prefix}groupId')
            if group_id_elem is None:
                group_id_elem = root.find('groupId')
            if group_id_elem is not None and group_id_elem.text:
                group_id = group_id_elem.text.strip()
                expected_gid = metadata.get('expected_groupId', 'org.springframework')
                if group_id == expected_gid:
                    pom_score += 8
                    feedback_parts.append(f"groupId correct: {group_id}")
                else:
                    feedback_parts.append(f"groupId mismatch: got '{group_id}', expected '{expected_gid}'")
            else:
                feedback_parts.append("groupId not found in pom.xml")

            # Check artifactId (use full namespace)
            artifact_id_elem = root.find(f'{maven_ns_prefix}artifactId')
            if artifact_id_elem is None:
                artifact_id_elem = root.find('artifactId')
            if artifact_id_elem is not None and artifact_id_elem.text:
                artifact_id = artifact_id_elem.text.strip()
                expected_aid = metadata.get('expected_artifactId', 'gs-maven')
                if artifact_id == expected_aid:
                    pom_score += 7
                    feedback_parts.append(f"artifactId correct: {artifact_id}")
                else:
                    feedback_parts.append(f"artifactId mismatch: got '{artifact_id}', expected '{expected_aid}'")
            else:
                feedback_parts.append("artifactId not found in pom.xml")

            # Check joda-time dependency (use full namespace for child elements)
            maven_ns = '{http://maven.apache.org/POM/4.0.0}'
            deps = root.findall('.//m:dependency', ns) or root.findall('.//dependency')
            has_jodatime = False
            for dep in deps:
                aid = dep.find(f'{maven_ns}artifactId')
                if aid is None:
                    aid = dep.find('artifactId')
                if aid is not None and aid.text and 'joda-time' in aid.text:
                    has_jodatime = True
                    ver = dep.find(f'{maven_ns}version')
                    if ver is None:
                        ver = dep.find('version')
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
        from eclipse_verification_utils import vlm_verify_eclipse_task

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Create a Maven project (gs-maven) in Eclipse IDE with pom.xml, "
                           "HelloWorld.java, and Greeter.java. Build the project successfully.",
            checklist_items=[
                "Eclipse IDE is open and visible",
                "A project creation dialog or new project wizard was used",
                "The project structure shows Java source files in a package",
                "A pom.xml file is visible in the project structure",
                "The project was built (Project menu used or Maven executed)",
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
