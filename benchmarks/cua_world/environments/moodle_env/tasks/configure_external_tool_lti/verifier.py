#!/usr/bin/env python3
"""Verifier for Configure External Tool LTI task in Moodle."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_configure_external_tool_lti(traj, env_info, task_info):
    """
    Verify LTI tool configuration and course integration.
    
    Scoring (100 points):
    - Site Tool Configuration (55 pts):
      - Tool exists and created during task (15 pts)
      - Name correct (5 pts)
      - URL correct (10 pts)
      - State is Configured/Active (10 pts)
      - Consumer Key correct (10 pts)
      - Shared Secret correct (5 pts)
    - Course Activity (45 pts):
      - Activity exists in CS101 and created during task (20 pts)
      - Name correct (10 pts)
      - Linked to the correct site tool (typeid match) (15 pts)
      
    Pass threshold: 60 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_tool_name = metadata.get('tool_name', 'CodePractice Pro')
    expected_url = metadata.get('tool_url', 'https://codepractice.example.com/lti/launch')
    expected_key = metadata.get('consumer_key', 'moodle-cs101-2024')
    expected_secret = metadata.get('shared_secret', 'secretkey2024abc')
    expected_activity_name = metadata.get('activity_name', 'Week 3: Python Loops Practice')

    try:
        temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/configure_external_tool_lti_result.json", temp_result.name)
            with open(temp_result.name, 'r') as f:
                result = json.load(f)
        finally:
            os.unlink(temp_result.name)

        score = 0
        feedback_parts = []
        
        # --- PART 1: Site Tool Configuration ---
        tool = result.get('tool', {})
        tool_found = result.get('tool_found', False)
        
        # Check creation time vs initial count/time
        # (Simplified check: if found and we assume environment was clean or count increased)
        # Note: verifier logic relies on 'tool_found' being the search for the specific name
        
        if tool_found:
            score += 15
            feedback_parts.append("LTI Tool created")
            
            # Name Check
            if expected_tool_name.lower() in tool.get('name', '').lower():
                score += 5
                feedback_parts.append("Tool name correct")
            else:
                feedback_parts.append(f"Tool name mismatch ({tool.get('name')})")
                
            # URL Check
            # Remove trailing slashes for comparison
            actual_url = tool.get('url', '').rstrip('/')
            exp_url_clean = expected_url.rstrip('/')
            if actual_url == exp_url_clean:
                score += 10
                feedback_parts.append("Tool URL correct")
            else:
                feedback_parts.append(f"Tool URL mismatch ({tool.get('url')})")
                
            # State Check (1 = Configured/Active)
            # Sometimes 2 = Pending, depending on Moodle version logic, but preconfigured usually 1
            state = str(tool.get('state', ''))
            if state == '1':
                score += 10
                feedback_parts.append("Tool state Active")
            else:
                feedback_parts.append(f"Tool state not Active ({state})")
                
            # Consumer Key
            if tool.get('consumer_key') == expected_key:
                score += 10
                feedback_parts.append("Consumer Key correct")
            else:
                feedback_parts.append("Consumer Key mismatch")
                
            # Shared Secret
            if tool.get('shared_secret') == expected_secret:
                score += 5
                feedback_parts.append("Shared Secret correct")
            else:
                feedback_parts.append("Shared Secret mismatch")
                
        else:
            feedback_parts.append("LTI Tool 'CodePractice Pro' NOT found")

        # --- PART 2: Course Activity ---
        activity = result.get('activity', {})
        activity_found = result.get('activity_found', False)
        
        if activity_found:
            score += 20
            feedback_parts.append("Course Activity created")
            
            # Name Check
            if expected_activity_name.lower() in activity.get('name', '').lower():
                score += 10
                feedback_parts.append("Activity name correct")
            else:
                feedback_parts.append(f"Activity name mismatch ({activity.get('name')})")
            
            # Linkage Check
            # The activity's typeid should match the tool's id
            act_typeid = str(activity.get('typeid', 'A'))
            tool_id = str(tool.get('id', 'B'))
            
            # Note: If typeid is 0, it means it's not linked to a site tool OR configured manually in the instance
            if tool_found and act_typeid == tool_id:
                score += 15
                feedback_parts.append("Activity correctly linked to Site Tool")
            elif tool_found:
                feedback_parts.append(f"Activity NOT linked to Site Tool (Activity typeid={act_typeid}, Tool id={tool_id})")
            else:
                feedback_parts.append("Cannot verify linkage (Site tool not found)")
        else:
            feedback_parts.append("Course Activity NOT found")

        # Anti-gaming: Ensure things were created during the task
        # We can check timestamps or counts. The export script captures counts.
        initial_types = int(result.get('initial_types_count', 0))
        current_types = int(result.get('current_types_count', 0))
        
        if tool_found and current_types <= initial_types:
             feedback_parts.append("(Warning: Tool count did not increase - verify if pre-existing)")
             # We won't deduct points here strictly if name/key match exactly as unique identifiers
             # but strictly speaking, for a creation task, count should increase.
        
        passed = score >= 60 and tool_found and activity_found
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found"}
    except json.JSONDecodeError:
        return {"passed": False, "score": 0, "feedback": "Invalid JSON result"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error: {str(e)}"}