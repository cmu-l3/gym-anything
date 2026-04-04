#!/usr/bin/env python3
"""Verifier for configure_build_path task in Eclipse."""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_build_path(traj, env_info, task_info):
    """
    Verify that the Eclipse build path was configured correctly.

    Criteria:
    1. .classpath file contains entries for the 3 JARs (45 pts)
    2. .classpath file contains src/main/java source entry (10 pts)
    3. Java source files compiled successfully (.class files exist) (35 pts)
    4. VLM verification of UI state (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_jars = metadata.get('expected_jars', [])

    score = 0
    feedback_parts = []
    
    # Read result JSON
    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
        os.unlink(temp_result.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

    # --- Criterion 1 & 2: Analyze .classpath content (55 points) ---
    classpath_content = result.get('classpath_content', '')
    classpath_modified = result.get('classpath_modified', False)
    
    if not classpath_modified:
        feedback_parts.append("FAIL: .classpath file was not modified")
    elif not classpath_content:
        feedback_parts.append("FAIL: .classpath file is empty")
    else:
        try:
            root = ET.fromstring(classpath_content)
            entries = root.findall("classpathentry")
            
            # Check for JARs (15 pts each)
            jars_found = 0
            for jar in expected_jars:
                # Look for entry with path containing the jar name
                # Path might be relative (lib/foo.jar) or absolute
                found = False
                for entry in entries:
                    path = entry.get('path', '')
                    if jar in path and entry.get('kind') == 'lib':
                        found = True
                        break
                
                if found:
                    score += 15
                    jars_found += 1
                else:
                    feedback_parts.append(f"Missing build path entry for {jar}")
            
            if jars_found == len(expected_jars):
                feedback_parts.append("All JARs added to build path")
            
            # Check for Source Folder (10 pts)
            # Expecting kind="src" path="src/main/java"
            src_found = False
            for entry in entries:
                if entry.get('kind') == 'src' and 'src/main/java' in entry.get('path', ''):
                    src_found = True
                    break
            
            if src_found:
                score += 10
                feedback_parts.append("Source folder configured correctly")
            else:
                feedback_parts.append("FAIL: src/main/java not configured as source folder")
                
        except ET.ParseError:
            feedback_parts.append("FAIL: .classpath file is not valid XML")

    # --- Criterion 3: Compilation Success (35 points) ---
    # We check if specific class files were generated
    app_exists = result.get('app_class_exists', False)
    transformer_exists = result.get('transformer_class_exists', False)
    analyzer_exists = result.get('analyzer_class_exists', False)
    
    # 35 points distributed among classes
    # If 0 classes compiled, 0 points.
    # If partial, proportional points.
    
    compiled_count = sum([app_exists, transformer_exists, analyzer_exists])
    
    if compiled_count == 3:
        score += 35
        feedback_parts.append("All classes compiled successfully")
    elif compiled_count > 0:
        partial_score = int((compiled_count / 3) * 35)
        score += partial_score
        feedback_parts.append(f"Partial compilation: {compiled_count}/3 classes found")
    else:
        feedback_parts.append("FAIL: No compiled class files found")

    # --- Criterion 4: VLM Verification (10 points) ---
    # Use VLM to verify the agent actually interacted with the UI and didn't just magic the files
    try:
        from eclipse_verification_utils import vlm_verify_eclipse_task
        
        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Configure Build Path in Eclipse to fix compilation errors by adding JARs and source folder",
            checklist_items=[
                "The Java Build Path dialog was opened",
                "The Libraries tab was accessed/visible",
                "User selected JARs to add to the build path",
                "The final state shows no red error markers on the project in Package Explorer",
                "The project structure in Package Explorer looks correct (src/main/java visible as source package)"
            ]
        )
        
        if vlm_result and vlm_result.get('vlm_passed'):
            score = min(score + 10, 100) # Cap at 100
            feedback_parts.append(vlm_result.get('vlm_feedback', ''))
        elif vlm_result:
             # Partial VLM credit
            vlm_score = vlm_result.get('vlm_score', 0)
            score = min(score + int(vlm_score * 0.1), 100)
    except Exception as e:
        logger.warning(f"VLM verification failed: {e}")

    # Final logic
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }