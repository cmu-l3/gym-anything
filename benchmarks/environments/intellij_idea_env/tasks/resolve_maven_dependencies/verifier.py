#!/usr/bin/env python3
"""Verifier for resolve_maven_dependencies task."""

import json
import re
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_resolve_maven_dependencies(traj, env_info, task_info):
    """
    Verify that all three Maven dependency issues were fixed in pom.xml.

    Scoring (100 points):
    - junit has scope=test (not compile): 30 pts
    - joda-time has exactly one entry (duplicate removed): 25 pts
    - commons-codec removed entirely: 20 pts
    - Build succeeds and all tests pass: 25 pts

    Pass threshold: >= 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/data-processor')

    # Get result JSON
    result = {}
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        tmp.close()
        copy_from_env('/tmp/task_result.json', tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        logger.debug(f"Could not read task_result.json: {e}")

    score = 0
    feedback_parts = []

    pom_content = result.get('pom_content', '')
    pom_modified = result.get('pom_modified', False)
    build_success = result.get('build_success', False)
    tests_run = result.get('tests_run', 0)
    tests_failed = result.get('tests_failed', 0)

    # Read pom.xml directly if not in result
    if not pom_content:
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
            tmp.close()
            copy_from_env(f"{project_dir}/pom.xml", tmp.name)
            with open(tmp.name, 'r') as f:
                pom_content = f.read()
            os.unlink(tmp.name)
        except Exception as e:
            logger.debug(f"Failed to read pom.xml: {e}")

    if not pom_content:
        return {
            "passed": False,
            "score": 0,
            "feedback": "pom.xml could not be read — no changes made?"
        }

    # Guard: pom must have been modified
    if not pom_modified:
        feedback_parts.append("pom.xml was not modified from the initial state")
    else:
        feedback_parts.append("pom.xml was modified")

    # Parse the POM XML for precise dependency analysis
    def get_dependencies(pom_text):
        """Return list of (groupId, artifactId, version, scope) tuples."""
        deps = []
        try:
            # Strip comments to avoid them confusing the parser
            pom_clean = re.sub(r'<!--.*?-->', '', pom_text, flags=re.DOTALL)
            # Wrap in root if needed (pom.xml already has <project> root)
            root = ET.fromstring(pom_clean)
            ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
            # Try with namespace first
            dep_list = root.findall('.//m:dependencies/m:dependency', ns)
            if not dep_list:
                # Try without namespace
                dep_list = root.findall('.//dependencies/dependency')
            for dep in dep_list:
                gid = (dep.find('m:groupId', ns) or dep.find('groupId'))
                aid = (dep.find('m:artifactId', ns) or dep.find('artifactId'))
                ver = (dep.find('m:version', ns) or dep.find('version'))
                scp = (dep.find('m:scope', ns) or dep.find('scope'))
                deps.append({
                    'groupId': gid.text.strip() if gid is not None else '',
                    'artifactId': aid.text.strip() if aid is not None else '',
                    'version': ver.text.strip() if ver is not None else '',
                    'scope': scp.text.strip() if scp is not None else 'compile',
                })
        except ET.ParseError as e:
            logger.debug(f"POM XML parse error: {e}")
        return deps

    deps = get_dependencies(pom_content)
    logger.info(f"Parsed {len(deps)} dependencies from pom.xml")

    # --- Criterion 1: junit has scope=test (30 pts) ---
    junit_deps = [d for d in deps if d['artifactId'] == 'junit']
    if junit_deps:
        junit_scope = junit_deps[0]['scope']
        if junit_scope == 'test':
            score += 30
            feedback_parts.append("junit scope=test (correct)")
        else:
            feedback_parts.append(f"junit scope='{junit_scope}' (should be 'test')")
    else:
        # junit may have been removed entirely — partial credit if build still works
        if build_success:
            score += 15
            feedback_parts.append("junit entry not found but build succeeds")
        else:
            feedback_parts.append("junit dependency not found in pom.xml")

    # --- Criterion 2: joda-time appears exactly once (25 pts) ---
    joda_deps = [d for d in deps if d['artifactId'] == 'joda-time']
    if len(joda_deps) == 1:
        score += 25
        feedback_parts.append(f"joda-time declared once (version {joda_deps[0]['version']})")
    elif len(joda_deps) == 0:
        feedback_parts.append("joda-time not found in pom.xml")
    else:
        feedback_parts.append(
            f"joda-time still declared {len(joda_deps)} times (duplicate not removed)"
        )

    # --- Criterion 3: commons-codec not present (20 pts) ---
    codec_deps = [d for d in deps if d['artifactId'] == 'commons-codec']
    if len(codec_deps) == 0:
        score += 20
        feedback_parts.append("commons-codec removed (unused dependency eliminated)")
    else:
        feedback_parts.append("commons-codec still present (should be removed)")

    # --- Criterion 4: Build succeeds and tests pass (25 pts) ---
    if build_success and tests_run > 0 and tests_failed == 0:
        score += 25
        feedback_parts.append(f"Build succeeds, {tests_run} tests pass")
    elif build_success:
        score += 15
        feedback_parts.append(f"Build succeeds but {tests_failed} test(s) failed")
    else:
        feedback_parts.append("Build failed")

    # --- VLM Verification ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from intellij_verification_utils import vlm_verify_intellij_task
        vlm_result = vlm_verify_intellij_task(
            traj, env_info,
            task_description=(
                "Fix 3 Maven dependency issues in data-processor pom.xml using IntelliJ: "
                "(1) change junit scope from compile to test, "
                "(2) remove duplicate joda-time entry (keep 2.10.13), "
                "(3) remove unused commons-codec dependency. "
                "Reload Maven and verify the project builds and tests pass."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the data-processor project loaded",
                "pom.xml is open in the editor",
                "The Maven tool window was used (dependency tree visible)",
                "Changes were made to the dependencies section of pom.xml",
                "Maven reload or reimport was triggered",
                "Build or test run was executed and shows success",
            ]
        )
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 10, 100)
        if vlm_result:
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
    except Exception as e:
        logger.debug(f"VLM verification skipped: {e}")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "junit_deps": junit_deps,
            "joda_count": len(joda_deps),
            "codec_count": len(codec_deps),
            "build_success": build_success,
            "tests_run": tests_run,
        }
    }
