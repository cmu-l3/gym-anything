#!/usr/bin/env python3
"""Verifier for convert_to_multi_module task."""

import json
import re
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

EXPECTED_MODULES = ['math', 'strings', 'collections']


def verify_convert_to_multi_module(traj, env_info, task_info):
    """
    Verify the single-module project was converted to a proper Maven multi-module build.

    Scoring (100 points):
    - Root pom.xml has packaging=pom: 10 pts
    - Root pom.xml declares all 3 modules (math, strings, collections): 20 pts
    - Each of the 3 module directories has a pom.xml: 20 pts (6-7 pts each)
    - Each module pom.xml references the parent: 15 pts (5 pts each)
    - mvn clean install from root succeeds (all tests pass): 35 pts

    Pass threshold: >= 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/java-library')
    expected_modules = metadata.get('expected_modules', EXPECTED_MODULES)

    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r', errors='replace') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception as e:
            logger.debug(f"Failed to read {remote_path}: {e}")
            return None

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

    root_pom_content = result.get('root_pom_content', '') or copy_and_read(
        f"{project_dir}/pom.xml"
    ) or ''
    build_success = result.get('build_success', False)
    total_tests = result.get('total_tests', 0)
    total_failures = result.get('total_failures', 0)

    if not root_pom_content:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Root pom.xml could not be read"
        }

    def parse_pom(pom_text):
        try:
            clean = re.sub(r'<!--.*?-->', '', pom_text, flags=re.DOTALL)
            return ET.fromstring(clean)
        except ET.ParseError as e:
            logger.debug(f"POM parse error: {e}")
            return None

    root_tree = parse_pom(root_pom_content)

    # --- Criterion 1: Root pom has packaging=pom (10 pts) ---
    root_has_pom_packaging = False
    if root_tree is not None:
        ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
        pkg = (
            root_tree.find('m:packaging', ns) or
            root_tree.find('packaging')
        )
        if pkg is not None and pkg.text and pkg.text.strip() == 'pom':
            root_has_pom_packaging = True
    else:
        # Fallback: text search
        root_has_pom_packaging = bool(re.search(r'<packaging>\s*pom\s*</packaging>', root_pom_content))

    if root_has_pom_packaging:
        score += 10
        feedback_parts.append("Root pom.xml has packaging=pom")
    else:
        feedback_parts.append("Root pom.xml does NOT have packaging=pom (multi-module builds require this)")

    # --- Criterion 2: Root pom declares all 3 modules (20 pts) ---
    declared_modules = []
    if root_tree is not None:
        ns = {'m': 'http://maven.apache.org/POM/4.0.0'}
        modules_el = root_tree.find('m:modules', ns) or root_tree.find('modules')
        if modules_el is not None:
            for mod in modules_el:
                text = mod.text.strip() if mod.text else ''
                declared_modules.append(text)
    else:
        # Fallback regex
        declared_modules = re.findall(r'<module>\s*(\w+)\s*</module>', root_pom_content)

    modules_found = [m for m in expected_modules if m in declared_modules]
    if len(modules_found) == len(expected_modules):
        score += 20
        feedback_parts.append(f"Root pom.xml declares all 3 modules: {declared_modules}")
    elif len(modules_found) > 0:
        partial = int(20 * len(modules_found) / len(expected_modules))
        score += partial
        feedback_parts.append(
            f"Root pom.xml declares {len(modules_found)}/{len(expected_modules)} modules: {modules_found}"
        )
    else:
        feedback_parts.append(
            f"Root pom.xml has no <modules> section or none of the expected modules"
        )

    # --- Criterion 3: Each module directory has a pom.xml (20 pts) ---
    module_pom_keys = {
        'math': 'math_pom_exists',
        'strings': 'strings_pom_exists',
        'collections': 'collections_pom_exists',
    }
    module_pom_contents = {
        'math': result.get('math_pom_content', '') or copy_and_read(f"{project_dir}/math/pom.xml"),
        'strings': result.get('strings_pom_content', '') or copy_and_read(f"{project_dir}/strings/pom.xml"),
        'collections': result.get('collections_pom_content', '') or copy_and_read(f"{project_dir}/collections/pom.xml"),
    }

    module_poms_exist = {
        mod: bool(module_pom_contents[mod])
        for mod in expected_modules
    }
    modules_with_pom = sum(1 for v in module_poms_exist.values() if v)

    per_module_pts = 7 if modules_with_pom == 3 else 6
    score += modules_with_pom * per_module_pts
    if modules_with_pom == len(expected_modules):
        feedback_parts.append("All 3 module directories have pom.xml files")
    else:
        missing = [m for m, v in module_poms_exist.items() if not v]
        feedback_parts.append(
            f"{modules_with_pom}/3 module pom.xml files found (missing: {missing})"
        )

    # --- Criterion 4: Each module pom.xml references parent (15 pts) ---
    parent_refs = 0
    for mod in expected_modules:
        pom = module_pom_contents.get(mod, '')
        if pom and ('<parent>' in pom or re.search(r'<parent\s', pom)):
            parent_refs += 1

    if parent_refs == len(expected_modules):
        score += 15
        feedback_parts.append("All 3 module pom.xml files reference the parent")
    elif parent_refs > 0:
        score += int(15 * parent_refs / len(expected_modules))
        feedback_parts.append(f"{parent_refs}/3 module pom.xml files reference the parent")
    else:
        feedback_parts.append("No module pom.xml files reference the parent")

    # --- Criterion 5: Build succeeds (35 pts) ---
    if build_success and total_failures == 0:
        score += 35
        feedback_parts.append(
            f"mvn clean install succeeds, {total_tests} tests pass across all modules"
        )
    elif build_success:
        score += 20
        feedback_parts.append(f"Build succeeds but {total_failures} test(s) failed")
    else:
        # Partial credit if structure is correct
        if modules_with_pom == 3 and root_has_pom_packaging:
            score += 10
            feedback_parts.append("Build failed but module structure appears correct")
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
                "Convert the single-module java-library Maven project to a multi-module build "
                "with three submodules: math, strings, collections. "
                "Modify root pom.xml (packaging=pom, add <modules>), "
                "create module subdirectories each with their own pom.xml referencing the parent, "
                "move source files, and run mvn clean install from the root."
            ),
            checklist_items=[
                "IntelliJ IDEA is open with the java-library project",
                "pom.xml is being edited (packaging or modules section visible)",
                "Multiple module directories or pom.xml files visible in project tree",
                "Maven tool window shows the multi-module structure",
                "A Maven build (mvn install or similar) was executed",
                "Build output shows BUILD SUCCESS",
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
            "root_has_pom_packaging": root_has_pom_packaging,
            "declared_modules": declared_modules,
            "module_poms_exist": module_poms_exist,
            "parent_refs": parent_refs,
            "build_success": build_success,
            "total_tests": total_tests,
        }
    }
