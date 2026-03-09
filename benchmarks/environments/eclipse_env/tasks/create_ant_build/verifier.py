#!/usr/bin/env python3
"""
Verifier for create_ant_build task.

Checks:
1. build.xml exists and is valid XML with required targets.
2. JAR file exists, was created during task, and has valid content.
3. Compiled classes exist.
4. VLM verification of the process (optional but good for debugging).
"""

import json
import tempfile
import os
import base64
import logging
import zipfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_ant_build(traj, env_info, task_info):
    """
    Verify Ant build creation and execution.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_jar_size = metadata.get('min_jar_size_kb', 30) * 1024
    
    # 1. Load result JSON
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

    score = 0
    feedback_parts = []
    
    # Criterion 1: build.xml exists and has correct targets (30 pts)
    build_xml_exists = result.get("build_xml_exists", False)
    if build_xml_exists:
        score += 10
        feedback_parts.append("build.xml created")
        
        # Analyze content
        try:
            content_b64 = result.get("build_xml_content_base64", "")
            if content_b64:
                content = base64.b64decode(content_b64).decode('utf-8')
                
                # Basic XML parsing
                try:
                    root = ET.fromstring(content)
                    targets = [t.get('name') for t in root.findall('target')]
                    
                    if 'clean' in targets: score += 5
                    if 'compile' in targets: score += 5
                    if 'jar' in targets: score += 5
                    
                    # Check for javac and jar tasks
                    if 'javac' in content: score += 2
                    if 'jar' in content: score += 3
                    
                    feedback_parts.append(f"Targets found: {', '.join(targets)}")
                except ET.ParseError:
                    feedback_parts.append("build.xml is not valid XML")
        except Exception as e:
            feedback_parts.append(f"Error parsing build.xml: {e}")
    else:
        feedback_parts.append("build.xml NOT found")

    # Criterion 2: JAR file validation (50 pts)
    jar_exists = result.get("jar_exists", False)
    jar_created_during = result.get("jar_created_during_task", False)
    jar_size = result.get("jar_size_bytes", 0)
    
    if jar_exists:
        if jar_created_during:
            score += 15
            feedback_parts.append("JAR file created during task")
            
            if jar_size > min_jar_size:
                score += 15
                feedback_parts.append(f"JAR size good ({jar_size} bytes)")
                
                # Try to inspect JAR content (requires copying JAR from env)
                try:
                    jar_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.jar')
                    jar_tmp.close()
                    copy_from_env("/home/ga/eclipse-workspace/commons-cli/build/commons-cli.jar", jar_tmp.name)
                    
                    with zipfile.ZipFile(jar_tmp.name, 'r') as zf:
                        file_list = zf.namelist()
                        # Check for specific classes we expect from Commons CLI
                        has_options = any('Options.class' in f for f in file_list)
                        has_parser = any('CommandLineParser.class' in f for f in file_list)
                        
                        if has_options and has_parser:
                            score += 20
                            feedback_parts.append("JAR contains correct compiled classes")
                        else:
                            feedback_parts.append("JAR exists but missing expected classes")
                            
                    os.unlink(jar_tmp.name)
                except Exception as e:
                    feedback_parts.append(f"Could not verify JAR content: {e}")
            else:
                feedback_parts.append(f"JAR file too small ({jar_size} bytes)")
        else:
            feedback_parts.append("JAR file exists but was NOT created during this task session")
    else:
        feedback_parts.append("commons-cli.jar NOT found in build directory")

    # Criterion 3: Class files verification (10 pts)
    class_count = result.get("class_files_count", 0)
    if class_count > 0:
        score += 10
        feedback_parts.append(f"{class_count} compiled class files found")
    
    # Criterion 4: VLM Verification (10 pts)
    # Only if we aren't already perfect, or to confirm UI usage
    if score < 100:
        try:
            from utils.eclipse_verification_utils import vlm_verify_eclipse_task
            vlm_res = vlm_verify_eclipse_task(
                traj, env_info,
                task_description="Create Ant build.xml and run the jar target",
                checklist_items=[
                    "Editor showing build.xml content",
                    "Ant view or Context Menu > Run As > Ant Build used",
                    "Console showing 'BUILD SUCCESSFUL'",
                    "Package Explorer showing 'build' directory"
                ]
            )
            if vlm_res and vlm_res.get('vlm_passed'):
                score += 10
                feedback_parts.append("VLM confirmed UI actions")
        except Exception:
            pass # VLM is optional bonus/fallback

    # Cap score
    score = min(score, 100)
    
    # Pass threshold: Must have JAR created and build.xml
    passed = (jar_exists and jar_created_during and build_xml_exists and score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }