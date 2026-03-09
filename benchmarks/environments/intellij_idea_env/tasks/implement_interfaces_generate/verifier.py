#!/usr/bin/env python3
"""Verifier for implement_interfaces_generate task."""

import json
import tempfile
import os
import re
import glob
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_implement_interfaces(traj, env_info, task_info):
    """Verify implementation of interfaces and boilerplate generation.

    Criteria:
    1. Project compiles (mvn test ran) (15 pts)
    2. All 6 tests pass (10 pts per class = 60 pts)
    3. Boilerplate generation (15 pts total):
       - Constructors present (5 pts)
       - equals/hashCode present (5 pts)
       - toString present (5 pts)
    4. Anti-gaming: Files actually modified (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/IdeaProjects/music-catalog')
    impl_classes = metadata.get('required_classes', ["Track", "Album", "Artist", "Playlist", "Podcast", "Genre"])

    score = 0
    feedback_parts = []
    
    # Helper to copy and read file
    def copy_and_read(remote_path):
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            with open(tmp.name, 'r') as f:
                content = f.read()
            os.unlink(tmp.name)
            return content
        except Exception:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    # Load task result
    task_result = {}
    try:
        content = copy_and_read("/tmp/task_result.json")
        if content:
            task_result = json.loads(content)
    except Exception:
        pass

    # --- Criterion 4: Anti-gaming (10 pts) ---
    modified_count = task_result.get('files_modified_count', 0)
    if modified_count >= 1:
        score += 10
        feedback_parts.append(f"{modified_count} files modified")
    else:
        feedback_parts.append("No files modified during task")
        # Fail immediately if nothing was touched
        return {"passed": False, "score": 0, "feedback": "No files modified"}

    # --- Criterion 1: Compilation (15 pts) ---
    # We check if surefire reports were generated, which implies compilation succeeded
    compilation_success = False
    
    # Try to verify compilation via class files
    compiled_classes = 0
    for cls in impl_classes:
        class_content = copy_and_read(f"{project_dir}/target/classes/com/musiccatalog/impl/{cls}.class")
        if class_content:
            compiled_classes += 1
            
    if compiled_classes == len(impl_classes):
        score += 15
        compilation_success = True
        feedback_parts.append("Compilation successful")
    else:
        feedback_parts.append(f"Compilation incomplete ({compiled_classes}/{len(impl_classes)} classes found)")

    # --- Criterion 2: Test Results (60 pts) ---
    tests_passed_count = 0
    tests_total_count = 0
    
    for cls in impl_classes:
        report_path = f"{project_dir}/target/surefire-reports/TEST-com.musiccatalog.{cls}Test.xml"
        report_content = copy_and_read(report_path)
        
        cls_passed = False
        if report_content:
            try:
                root = ET.fromstring(report_content)
                tests = int(root.attrib.get('tests', 0))
                failures = int(root.attrib.get('failures', 0))
                errors = int(root.attrib.get('errors', 0))
                
                tests_total_count += tests
                passed = tests - failures - errors
                tests_passed_count += passed
                
                if passed == tests and tests > 0:
                    score += 10
                    cls_passed = True
                elif passed > 0:
                    score += int(10 * (passed / tests))
            except ET.ParseError:
                pass
        
        if not cls_passed:
            feedback_parts.append(f"{cls}Test failed")

    if tests_total_count > 0:
        feedback_parts.append(f"Tests passed: {tests_passed_count}/{tests_total_count}")

    # --- Criterion 3: Boilerplate Generation (15 pts) ---
    constructors_ok = 0
    tostring_ok = 0
    equalshash_ok = 0

    for cls in impl_classes:
        src = copy_and_read(f"{project_dir}/src/main/java/com/musiccatalog/impl/{cls}.java")
        if not src:
            continue
            
        # Check constructor
        if re.search(rf'public\s+{cls}\s*\(', src):
            constructors_ok += 1
            
        # Check toString
        if 'public String toString()' in src:
            tostring_ok += 1
            
        # Check equals/hashCode
        if 'public boolean equals(Object' in src and 'public int hashCode()' in src:
            equalshash_ok += 1

    # Scoring boilerplate
    if constructors_ok == len(impl_classes):
        score += 5
    else:
        score += int(5 * (constructors_ok / len(impl_classes)))
        
    if tostring_ok == len(impl_classes):
        score += 5
    else:
        score += int(5 * (tostring_ok / len(impl_classes)))

    if equalshash_ok == len(impl_classes):
        score += 5
    else:
        score += int(5 * (equalshash_ok / len(impl_classes)))

    feedback_parts.append(f"Boilerplate: Ctr:{constructors_ok}, Str:{tostring_ok}, Eq:{equalshash_ok}")

    passed = (score >= 60) and compilation_success

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }