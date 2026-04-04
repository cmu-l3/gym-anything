#!/usr/bin/env python3
"""Verifier for fix_build_errors task."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_build_errors(traj, env_info, task_info):
    """Verify that the build errors were fixed by adding the missing dependency.

    Criteria:
    1. pom.xml exists (10 pts)
    2. joda-time dependency was added to pom.xml (40 pts)
    3. Project builds successfully (50 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/gs-maven-broken')

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

    # --- Criterion 1: pom.xml exists (10 points) ---
    pom_content = copy_and_read(f"{project_dir}/pom.xml")
    if pom_content:
        score += 10
        feedback_parts.append("pom.xml exists")

        # --- Criterion 2: joda-time dependency added (40 points) ---
        try:
            root = ET.fromstring(pom_content)
            ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
            maven_ns = '{http://maven.apache.org/POM/4.0.0}'

            deps = root.findall('.//m:dependency', ns) or root.findall('.//dependency')
            has_jodatime = False
            jodatime_version = None

            for dep in deps:
                # Try with full namespace first, then without
                aid = dep.find(f'{maven_ns}artifactId')
                if aid is None:
                    aid = dep.find('artifactId')

                if aid is not None and aid.text and 'joda-time' in aid.text.lower():
                    has_jodatime = True
                    ver = dep.find(f'{maven_ns}version')
                    if ver is None:
                        ver = dep.find('version')
                    if ver is not None:
                        jodatime_version = ver.text
                    break

            if has_jodatime:
                score += 40
                if jodatime_version:
                    feedback_parts.append(f"joda-time dependency added (version {jodatime_version})")
                else:
                    feedback_parts.append("joda-time dependency added")
            else:
                feedback_parts.append("joda-time dependency NOT found in pom.xml")

        except ET.ParseError as e:
            feedback_parts.append(f"pom.xml parse error: {e}")
    else:
        feedback_parts.append("pom.xml not found")

    # --- Criterion 3: Build success (50 points) ---
    try:
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/classes/hello/HelloWorld.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)
        if magic == b'\xca\xfe\xba\xbe':
            score += 50
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
            task_description="Fix build errors in a Maven project by adding the missing joda-time dependency to pom.xml",
            checklist_items=[
                "Eclipse IDE is open and visible",
                "The project was imported or opened",
                "The pom.xml file was edited",
                "A dependency was added to the pom.xml",
                "Maven project was updated/refreshed",
                "No build errors visible after the fix",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 5, 100)
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    # Must have dependency added AND build success to pass
    build_successful = 'Build successful' in ' '.join(feedback_parts)
    dep_added = 'joda-time dependency added' in ' '.join(feedback_parts)

    passed = build_successful and dep_added

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }
