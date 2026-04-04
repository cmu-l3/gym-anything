#!/usr/bin/env python3
"""Verifier for run_and_debug task."""

import json
import tempfile
import os
import glob as globlib
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_run_and_debug(traj, env_info, task_info):
    """Verify that the program was run and debugged in Eclipse.

    File-based evidence (70 pts):
    1. Launch configuration files exist (25 pts)
    2. Breakpoint marker files exist (25 pts)
    3. Project compiled (class files exist) (10 pts)
    4. Debug history/perspective evidence (10 pts)

    VLM verification (30 pts):
    5. Visual confirmation of debug actions
    """
    copy_from_env = env_info.get('copy_from_env')
    list_remote_dir = env_info.get('list_remote_dir')  # if available
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_dir = metadata.get('project_dir', '/home/ga/eclipse-workspace/gs-maven')
    workspace_dir = '/home/ga/eclipse-workspace'

    score = 0
    feedback_parts = []

    def copy_and_read(remote_path):
        """Copy a file from the environment and read its contents."""
        tmp = None
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
            if tmp and os.path.exists(tmp.name):
                os.unlink(tmp.name)
            return None

    def file_exists_remote(remote_path):
        """Check if a file exists on the remote system."""
        try:
            tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.tmp')
            tmp.close()
            copy_from_env(remote_path, tmp.name)
            exists = os.path.getsize(tmp.name) > 0
            os.unlink(tmp.name)
            return exists
        except Exception:
            return False

    # --- Criterion 1: Launch configuration files (20 points) ---
    # Eclipse stores .launch files in workspace/.metadata/.plugins/org.eclipse.debug.core/.launches/
    launch_dir = f"{workspace_dir}/.metadata/.plugins/org.eclipse.debug.core/.launches"
    launch_found = False

    # Check for any .launch file related to HelloWorld or Java application
    for launch_name in ['HelloWorld.launch', 'hello.HelloWorld.launch', 'gs-maven.launch', 'Java Application.launch']:
        if file_exists_remote(f"{launch_dir}/{launch_name}"):
            launch_content = copy_and_read(f"{launch_dir}/{launch_name}")
            if launch_content and ('HelloWorld' in launch_content or 'hello' in launch_content):
                launch_found = True
                score += 25  # Increased from 20 to 25
                feedback_parts.append("Launch configuration found")
                break

    if not launch_found:
        # Check task_result.json for launch evidence
        result_json = copy_and_read("/tmp/task_result.json")
        if result_json:
            try:
                result = json.loads(result_json)
                if result.get('program_ran'):
                    score += 12  # Partial credit (increased from 10)
                    feedback_parts.append("Execution evidence detected")
                    launch_found = True
            except json.JSONDecodeError:
                pass

    if not launch_found:
        feedback_parts.append("No launch configuration found")

    # --- Criterion 2: Breakpoint evidence (20 points) ---
    # Eclipse stores breakpoints in workspace/.metadata/.plugins/org.eclipse.debug.core/.breakpoints
    breakpoint_file = f"{workspace_dir}/.metadata/.plugins/org.eclipse.debug.core/.breakpoints"
    breakpoint_content = copy_and_read(breakpoint_file)

    if breakpoint_content and len(breakpoint_content) > 10:
        # Check if breakpoint is set on HelloWorld.java
        if 'HelloWorld' in breakpoint_content or 'hello' in breakpoint_content:
            score += 25  # Increased from 20 to 25
            feedback_parts.append("Breakpoint on HelloWorld found")
        elif 'lineNumber' in breakpoint_content or 'org.eclipse.jdt.debug' in breakpoint_content:
            score += 18  # Partial credit - some breakpoint exists (increased from 15)
            feedback_parts.append("Breakpoint detected (not on target file)")
        else:
            score += 12  # Some breakpoint data exists (increased from 10)
            feedback_parts.append("Breakpoint file exists")
    else:
        # Check task_result.json as fallback
        result_json = copy_and_read("/tmp/task_result.json")
        if result_json:
            try:
                result = json.loads(result_json)
                if result.get('breakpoint_set'):
                    score += 10
                    feedback_parts.append("Breakpoint marker evidence")
            except json.JSONDecodeError:
                pass
        if 'Breakpoint' not in ' '.join(feedback_parts):
            feedback_parts.append("No breakpoint evidence found")

    # --- Criterion 3: Project compiled (10 points) ---
    try:
        tmp_class = tempfile.NamedTemporaryFile(delete=False, suffix='.class')
        tmp_class.close()
        copy_from_env(f"{project_dir}/target/classes/hello/HelloWorld.class", tmp_class.name)
        with open(tmp_class.name, 'rb') as f:
            magic = f.read(4)
        os.unlink(tmp_class.name)
        if magic == b'\xca\xfe\xba\xbe':
            score += 10
            feedback_parts.append("Project compiled")
    except Exception:
        feedback_parts.append("Project not compiled")

    # --- Criterion 4: Debug history/perspective evidence (10 points) ---
    # Check for debug perspective usage in workbench state
    workbench_file = f"{workspace_dir}/.metadata/.plugins/org.eclipse.e4.workbench/workbench.xmi"
    workbench_content = copy_and_read(workbench_file)
    if workbench_content:
        if 'Debug' in workbench_content or 'debug' in workbench_content:
            score += 10
            feedback_parts.append("Debug perspective used")
        else:
            # Check for debug UI state
            debug_ui_file = f"{workspace_dir}/.metadata/.plugins/org.eclipse.debug.ui/launchConfigurationHistory.xml"
            debug_ui_content = copy_and_read(debug_ui_file)
            if debug_ui_content and len(debug_ui_content) > 10:
                score += 5
                feedback_parts.append("Debug UI history exists")

    # --- Criterion 5: VLM Verification (30 points) ---
    try:
        import sys
        sys.path.insert(0, '/workspace/utils')
        from eclipse_verification_utils import vlm_verify_eclipse_task

        vlm_result = vlm_verify_eclipse_task(
            traj, env_info,
            task_description="Run and debug HelloWorld.java in Eclipse IDE with a breakpoint",
            checklist_items=[
                "Eclipse IDE is open and visible",
                "The gs-maven project is imported/open",
                "HelloWorld.java is visible in the editor",
                "A breakpoint marker (blue dot) is visible in the editor margin",
                "The Debug perspective or debug toolbar is visible",
                "Console output shows program execution",
                "The debugger paused at the breakpoint (yellow highlight on code line)",
            ]
        )

        if vlm_result:
            vlm_score = vlm_result.get('vlm_score', 0)
            # Scale VLM score to max 30 points (reduced from 40)
            scaled_vlm_score = int(vlm_score * 0.3)
            score += scaled_vlm_score
            feedback_parts.append(f"VLM: {vlm_result.get('vlm_feedback', 'checked')}")

            if vlm_result.get('vlm_passed'):
                feedback_parts.append("VLM passed")
        else:
            feedback_parts.append("VLM verification not available")

    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM skipped: {e}")

    # Require file-based evidence + reasonable score to pass
    # Score of 50+ indicates at least some file evidence and/or VLM confirmation
    passed = score >= 50

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
