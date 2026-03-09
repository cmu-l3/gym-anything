#!/usr/bin/env python3
"""
Verifier for Configure Global Tools task in Jenkins.

Checks if JDK and Maven installations are configured correctly according to the task description.
"""

import sys
import os
import json
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_global_tools(traj, env_info, task_info):
    """
    Verify JDK and Maven configurations.

    Criteria:
    1. JDK-17 exists with correct name (20 pts)
    2. JDK-17 has correct JAVA_HOME (20 pts)
    3. Maven-3.9.6 exists with correct name (20 pts)
    4. Maven-3.9.6 is set to auto-install (20 pts)
    5. Maven-3.9.6 version is correct (20 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_jdk_name = metadata.get('expected_jdk_name', 'JDK-17')
    expected_jdk_home = metadata.get('expected_jdk_home', '/opt/java/openjdk')
    expected_maven_name = metadata.get('expected_maven_name', 'Maven-3.9.6')
    expected_maven_version = metadata.get('expected_maven_version', '3.9.6')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_global_tools_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        tools = result.get('tools', {})
        jdks = tools.get('jdks', [])
        mavens = tools.get('mavens', [])

        logger.info(f"Verified Tools Config: JDKs={jdks}, Mavens={mavens}")

        score = 0
        feedback_parts = []
        
        # --- Verify JDK ---
        jdk_found = False
        target_jdk = None
        
        # Find JDK by name
        for jdk in jdks:
            if jdk.get('name') == expected_jdk_name:
                jdk_found = True
                target_jdk = jdk
                break
        
        if jdk_found:
            score += 20
            feedback_parts.append(f"JDK '{expected_jdk_name}' found")
            
            # Check Home
            actual_home = target_jdk.get('home', '').rstrip('/')
            expected_home_clean = expected_jdk_home.rstrip('/')
            
            if actual_home == expected_home_clean:
                score += 20
                feedback_parts.append("JDK JAVA_HOME is correct")
            else:
                feedback_parts.append(f"JDK JAVA_HOME incorrect: expected '{expected_jdk_home}', got '{actual_home}'")
        else:
            feedback_parts.append(f"JDK '{expected_jdk_name}' NOT found")

        # --- Verify Maven ---
        maven_found = False
        target_maven = None
        
        for mvn in mavens:
            if mvn.get('name') == expected_maven_name:
                maven_found = True
                target_maven = mvn
                break
                
        if maven_found:
            score += 20
            feedback_parts.append(f"Maven '{expected_maven_name}' found")
            
            # Check Auto Install
            if target_maven.get('auto_install', False):
                score += 20
                feedback_parts.append("Maven auto-install enabled")
                
                # Check Version
                installer_id = target_maven.get('installer_id', '')
                if expected_maven_version in installer_id:
                    score += 20
                    feedback_parts.append(f"Maven version correct ({expected_maven_version})")
                else:
                    feedback_parts.append(f"Maven version mismatch: expected '{expected_maven_version}', got installer ID '{installer_id}'")
            else:
                feedback_parts.append("Maven auto-install NOT enabled (required for this task)")
        else:
            feedback_parts.append(f"Maven '{expected_maven_name}' NOT found")

        passed = (score >= 100)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification failed due to error: {str(e)}"
        }