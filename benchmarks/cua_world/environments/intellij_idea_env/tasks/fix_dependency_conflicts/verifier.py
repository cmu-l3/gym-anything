#!/usr/bin/env python3
"""Verifier for fix_dependency_conflicts task."""

import json
import tempfile
import os
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_fix_dependency_conflicts(traj, env_info, task_info):
    """
    Verify that Maven dependency conflicts were resolved correctly.

    Criteria:
    1. Maven compilation succeeds (30 pts)
    2. Maven tests pass (20 pts)
    3. Source code was NOT modified (anti-gaming) (10 pts)
    4. POM Analysis:
       - jackson-core 2.9.0 removed or updated to >=2.15 (15 pts)
       - commons-lang3 updated to >=3.5 (15 pts)
    5. VLM verification of workflow (10 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Data extraction
    compile_code = result.get('compile_exit_code', 1)
    test_code = result.get('test_exit_code', 1)
    sources_modified = result.get('sources_modified', False)
    pom_content = result.get('pom_content', "")
    compile_log = result.get('compile_log', "")

    # --- Criterion 1: Compilation Success (30 pts) ---
    if compile_code == 0:
        score += 30
        feedback_parts.append("Compilation successful")
    else:
        feedback_parts.append("Compilation FAILED")
        # Check logs for hints
        if "StreamWriteConstraints" in compile_log:
            feedback_parts.append("(Hint: Still seeing Jackson StreamWriteConstraints error)")
        if "StringUtils.truncate" in compile_log:
            feedback_parts.append("(Hint: Still seeing StringUtils.truncate error)")

    # --- Criterion 2: Test Success (20 pts) ---
    if test_code == 0:
        score += 20
        feedback_parts.append("Tests passed")
    else:
        feedback_parts.append("Tests FAILED")

    # --- Criterion 3: Source Code Integrity (10 pts) ---
    if not sources_modified:
        score += 10
        feedback_parts.append("Source code unmodified (Good)")
    else:
        feedback_parts.append("FAIL: Java source files were modified. You must fix the POM, not the code.")
        # Heavy penalty for modifying source code in a dependency fixing task
        score = 0 
        return {"passed": False, "score": 0, "feedback": "Task failed: Java source files were modified. The goal is to fix dependencies in pom.xml."}

    # --- Criterion 4: POM Analysis (30 pts) ---
    pom_score = 0
    
    # Check Jackson Core
    # We want to see NO strict dependency on 2.9.0
    # OR explicit dependency on >= 2.15
    jackson_core_match = re.search(r'<artifactId>jackson-core</artifactId>\s*<version>([^<]+)</version>', pom_content)
    
    jackson_ok = False
    if jackson_core_match:
        version = jackson_core_match.group(1)
        # Check version >= 2.15
        try:
            v_parts = [int(x) for x in version.split('.')[:2]]
            if v_parts[0] > 2 or (v_parts[0] == 2 and v_parts[1] >= 15):
                jackson_ok = True
                feedback_parts.append(f"jackson-core updated to {version}")
            else:
                feedback_parts.append(f"jackson-core version {version} is too old")
        except:
            feedback_parts.append(f"Could not parse jackson-core version: {version}")
    else:
        # If jackson-core is NOT explicitly defined, it usually falls back to the transitive dependency
        # from jackson-databind (which is 2.15.2 in our setup). This is a valid fix (removing the conflict).
        if "jackson-databind" in pom_content:
            jackson_ok = True
            feedback_parts.append("jackson-core explicit dependency removed (using transitive)")
    
    if jackson_ok:
        pom_score += 15
    
    # Check Commons Lang3
    # We want version >= 3.5
    lang3_match = re.search(r'<artifactId>commons-lang3</artifactId>\s*<version>([^<]+)</version>', pom_content)
    lang3_ok = False
    if lang3_match:
        version = lang3_match.group(1)
        try:
            v_parts = [int(x) for x in version.split('.')[:2]]
            if v_parts[0] > 3 or (v_parts[0] == 3 and v_parts[1] >= 5):
                lang3_ok = True
                feedback_parts.append(f"commons-lang3 updated to {version}")
            else:
                feedback_parts.append(f"commons-lang3 version {version} is too old (need 3.5+)")
        except:
            pass
    
    if lang3_ok:
        pom_score += 15
    
    score += pom_score

    # --- Criterion 5: VLM Verification (10 pts) ---
    # Simple check: did they actually open/edit the POM file?
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames
        query_vlm = env_info.get('query_vlm')
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, num_samples=5)
            prompt = """
            Review these screenshots of an agent working in IntelliJ IDEA.
            Does the agent edit the 'pom.xml' file?
            Do you see the Maven dependency tool window or 'mvn' commands in the terminal?
            
            Return JSON: {"pom_edited": bool, "maven_tools_used": bool}
            """
            result = query_vlm(images=frames, prompt=prompt)
            if result and result.get('success'):
                parsed = result.get('parsed', {})
                if parsed.get('pom_edited') or parsed.get('maven_tools_used'):
                    vlm_score = 10
                    feedback_parts.append("VLM: Workflow verified")
    except ImportError:
        # Fallback if VLM lib not present, give points if everything else passed
        if score >= 90:
            vlm_score = 10
            
    score += vlm_score

    # Final check
    # Must compile and pass tests to pass
    passed = (compile_code == 0) and (test_code == 0) and (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }