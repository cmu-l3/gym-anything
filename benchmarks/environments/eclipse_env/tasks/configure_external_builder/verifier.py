#!/usr/bin/env python3
"""
Verifier for configure_external_builder task.

Criteria:
1. Shared launch file 'VersionGenerator.launch' exists in project root (30 pts)
2. Launch file is valid XML and points to 'scripts/gen_version.sh' (20 pts)
3. Launch file is configured for 'auto' and 'clean' builds (15 pts)
4. Launch file has 'refresh' enabled (10 pts)
5. .project file references the builder (15 pts)
6. Output file 'version.txt' was successfully generated (10 pts)
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_external_builder(traj, env_info, task_info):
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
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []

    # Criterion 1: Shared Launch File Existence (30 pts)
    # This proves the user checked "Shared file" in the Common tab
    launch_content = result.get('launch_content', '')
    if result.get('launch_exists', False) and launch_content.strip():
        score += 30
        feedback_parts.append("Shared launch file created")
        
        # Parse XML for details
        try:
            root = ET.fromstring(launch_content)
            
            # Criterion 2: Script Location (20 pts)
            # Look for ATTR_LOCATION
            # Example: <stringAttribute key="org.eclipse.ui.externaltools.ATTR_LOCATION" value="${workspace_loc:/AutoVer/scripts/gen_version.sh}"/>
            location_node = root.find(".//*[@key='org.eclipse.ui.externaltools.ATTR_LOCATION']")
            if location_node is not None:
                location_val = location_node.get('value', '')
                if 'gen_version.sh' in location_val:
                    score += 20
                    feedback_parts.append("Script location correct")
                else:
                    feedback_parts.append(f"Incorrect script location: {location_val}")
            else:
                feedback_parts.append("Script location not configured")

            # Criterion 3: Build Triggers (15 pts)
            # Look for ATTR_BUILD_SCOPE or ATTR_RUN_BUILD_KINDS
            # Format often: "${build_type:full,incremental,auto,clean}"
            scope_node = root.find(".//*[@key='org.eclipse.ui.externaltools.ATTR_BUILD_SCOPE']")
            if scope_node is not None:
                scope_val = scope_node.get('value', '').lower()
                triggers = 0
                if 'auto' in scope_val: triggers += 1
                if 'clean' in scope_val: triggers += 1
                
                if triggers == 2:
                    score += 15
                    feedback_parts.append("Build triggers (Auto+Clean) correct")
                elif triggers > 0:
                    score += 7
                    feedback_parts.append("Build triggers partially correct")
                else:
                    feedback_parts.append("Build triggers missing Auto/Clean")
            else:
                # Fallback: check older attribute style ATTR_RUN_BUILD_KINDS
                kinds_node = root.find(".//*[@key='org.eclipse.ui.externaltools.ATTR_RUN_BUILD_KINDS']")
                if kinds_node is not None:
                    kinds_val = kinds_node.get('value', '')
                    if 'full' in kinds_val and 'clean' in kinds_val: # full often implies auto in some versions
                         score += 10
                         feedback_parts.append("Build triggers found (legacy format)")
                else:
                    feedback_parts.append("Build triggers not found")

            # Criterion 4: Refresh Scope (10 pts)
            # Look for org.eclipse.debug.core.ATTR_REFRESH_SCOPE
            refresh_node = root.find(".//*[@key='org.eclipse.debug.core.ATTR_REFRESH_SCOPE']")
            if refresh_node is not None:
                score += 10
                feedback_parts.append("Refresh configured")
            else:
                feedback_parts.append("Refresh NOT configured")

        except ET.ParseError:
            feedback_parts.append("Launch file is invalid XML")
    else:
        feedback_parts.append("Shared launch file NOT found (Did you check 'Shared file' in Common tab?)")

    # Criterion 5: Project Linkage (15 pts)
    # The .project file must reference the builder
    project_content = result.get('project_content', '')
    if 'VersionGenerator' in project_content or 'org.eclipse.ui.externaltools.ExternalToolBuilder' in project_content:
        score += 15
        feedback_parts.append("Project builder linked")
    else:
        feedback_parts.append("Builder not linked in .project file")

    # Criterion 6: Output Generation (10 pts)
    if result.get('output_exists', False):
        if result.get('output_fresh', False):
            score += 10
            feedback_parts.append("Output generated successfully")
        else:
            score += 5
            feedback_parts.append("Output exists but timestamp is old (did build run?)")
    else:
        feedback_parts.append("Output file 'version.txt' not generated")

    return {
        "passed": score >= 75,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }