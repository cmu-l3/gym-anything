#!/usr/bin/env python3
"""
Verifier for configure_shared_library task.
Verifies that the Global Pipeline Library is configured in XML and the test job uses it.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_shared_library(traj, env_info, task_info):
    """
    Verify shared library configuration and job creation.
    
    Points:
    - Library Configured in System (GlobalLibraries.xml exists): 10 pts
    - Library Configuration Correct (Name, URL, Version): 40 pts
    - Job Created: 10 pts
    - Job Configuration Correct (Uses @Library): 30 pts
    - Anti-Gaming (Timestamps/Freshness): 10 pts
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_lib_name = metadata.get('expected_lib_name', 'jenkins-shared-lib')
    expected_repo = metadata.get('expected_repo', 'https://github.com/jenkins-infra/pipeline-library.git')
    expected_version = metadata.get('expected_version', 'master')
    expected_job_name = metadata.get('expected_job_name', 'shared-lib-test')

    # Load result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/shared_lib_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 1. Verify Library Configuration (50 pts total)
    lib_exists = result.get('lib_config_exists', False)
    lib_content = result.get('lib_config_content', '')
    
    if lib_exists and lib_content:
        score += 10
        feedback_parts.append("Global Libraries config file created")
        
        # Parse XML to check details
        try:
            root = ET.fromstring(lib_content)
            # Namespace handling might be tricky in Jenkins XML, usually standard tags though.
            # Structure: org.jenkinsci.plugins.workflow.libs.GlobalLibraries > libraries > org.jenkinsci.plugins.workflow.libs.LibraryConfiguration
            
            # Find the library configuration
            library_found = False
            details_correct = False
            
            # Search for any library config
            for lib in root.findall(".//org.jenkinsci.plugins.workflow.libs.LibraryConfiguration"):
                name = lib.find('name').text if lib.find('name') is not None else ""
                version = lib.find('defaultVersion').text if lib.find('defaultVersion') is not None else ""
                
                # Check SCM URL (deeply nested)
                # retriever > scm > userRemoteConfigs > hudson.plugins.git.UserRemoteConfig > url
                scm_url = ""
                # Try finding URL recursively or via specific path
                url_elem = lib.find(".//url")
                if url_elem is not None:
                    scm_url = url_elem.text
                
                if name == expected_lib_name:
                    library_found = True
                    checks = []
                    
                    if expected_repo in scm_url:
                        checks.append("Repo URL Correct")
                        score += 20
                    else:
                        checks.append(f"Repo URL mismatch (found '{scm_url}')")
                        
                    if version == expected_version:
                        checks.append("Version Correct")
                        score += 20
                    else:
                        checks.append(f"Version mismatch (found '{version}')")
                        
                    feedback_parts.append(f"Library '{name}' found: " + ", ".join(checks))
                    break
            
            if not library_found:
                 feedback_parts.append(f"Library configuration found, but name '{expected_lib_name}' is missing")
        except ET.ParseError:
            feedback_parts.append("Failed to parse GlobalLibraries.xml")
    else:
        feedback_parts.append("Global Libraries config file NOT found (System config not saved?)")

    # 2. Verify Job Creation (40 pts total)
    job_exists = result.get('job_exists', False)
    job_content = result.get('job_config_content', '')
    
    if job_exists:
        score += 10
        feedback_parts.append(f"Job '{expected_job_name}' exists")
        
        if job_content:
            # Check for annotation in script
            if "@Library" in job_content and expected_lib_name in job_content:
                score += 30
                feedback_parts.append("Job script correctly imports the library")
            else:
                feedback_parts.append("Job script missing '@Library' annotation or incorrect library name")
    else:
        feedback_parts.append(f"Job '{expected_job_name}' NOT found")

    # 3. Anti-Gaming (10 pts)
    # Check if config was modified/created during task
    lib_modified = result.get('lib_modified_during_task', False)
    job_created = result.get('job_created_during_task', False)
    
    if lib_modified or job_created:
        score += 10
        feedback_parts.append("Changes verified as new")
    else:
        feedback_parts.append("No file timestamps indicate recent changes")

    # Final tally
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }