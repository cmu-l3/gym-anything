#!/usr/bin/env python3
"""
Verifier for design_linked_household_forms task.

Verification Strategy:
1. Parse the Epi Info 7 Project file (.prj, which is XML).
2. Verify existence of 'Household' and 'Member' views.
3. Verify required fields exist in respective views.
4. Verify the 'Sex' field is a Legal Values (dropdown) field.
5. Verify the relationship between Household and Member.
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_design_linked_household_forms(traj, env_info, task_info):
    """
    Verify the Epi Info 7 project structure.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    project_path = metadata.get('project_path', r"C:\Users\Docker\Documents\Epi Info 7\Projects\HouseholdSurvey\HouseholdSurvey.prj")
    
    score = 0
    max_score = 100
    feedback_parts = []

    # 1. Retrieve Result JSON from Container
    result_json_path = r"C:\Users\Docker\AppData\Local\Temp\task_result.json" # Windows path inside container
    # Map to linux path for copy_from_env? 
    # Usually copy_from_env takes the path as verified in the container.
    # Since the env is Windows, copy_from_env should handle the path provided.
    
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env(result_json_path, temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check File Existence and Timing (Anti-Gaming)
    if not task_result.get('project_exists'):
        return {"passed": False, "score": 0, "feedback": "Project file not found."}
    
    if not task_result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Project file detected but was not modified during the task."}

    score += 10
    feedback_parts.append("Project file created.")

    # 3. Retrieve and Parse .prj File
    temp_prj = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(project_path, temp_prj.name)
        
        # Parse XML
        try:
            tree = ET.parse(temp_prj.name)
            root = tree.getroot()
        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Project file exists but is not valid XML."}

        # Analyze Views
        # Structure: <Project> <View Name="Household"> ... </View> </Project>
        views = {v.get('Name'): v for v in root.findall('View')}
        
        # Check Household View
        if 'Household' in views:
            score += 15
            feedback_parts.append("Household form found.")
            
            household_fields = get_fields_from_view(views['Household'])
            
            # Check fields: Address, CensusTract, VisitDate
            # Note: Field names in Epi Info might be stored in 'Name' attribute of 'Field' tag
            required_hh = ['Address', 'CensusTract', 'VisitDate']
            missing_hh = [f for f in required_hh if f not in household_fields]
            
            if not missing_hh:
                score += 15
                feedback_parts.append("All Household fields present.")
            else:
                score += max(0, 15 - (5 * len(missing_hh)))
                feedback_parts.append(f"Missing Household fields: {', '.join(missing_hh)}.")

            # Check for Relationship (Relate button)
            # Relate buttons are fields with specific FieldTypeID (21 is common, or Name check)
            # We look for any field that points to the 'Member' view
            relate_found = False
            for field in views['Household'].findall(".//Field"):
                 # Check if it relates to Member view (attributes might vary by version, looking for RelatedViewID or similar)
                 # Alternatively, check for a button named "Add Family Member" or field type 'Relate'
                 field_type = field.get('FieldTypeId')
                 # 21 = Relate in some versions, or check specific attributes
                 if field_type == '21' or field.get('Name') == 'AddFamilyMember' or 'Member' in str(field.attrib):
                     relate_found = True
                     break
            
            if relate_found:
                score += 20
                feedback_parts.append("Link to Member form found.")
            else:
                feedback_parts.append("Link to Member form NOT found.")

        else:
            feedback_parts.append("Household form MISSING.")

        # Check Member View
        if 'Member' in views:
            score += 15
            feedback_parts.append("Member form found.")
            
            member_fields = get_fields_from_view(views['Member'])
            required_mem = ['FullName', 'Age', 'Sex']
            missing_mem = [f for f in required_mem if f not in member_fields]
            
            if not missing_mem:
                score += 15
                feedback_parts.append("All Member fields present.")
            else:
                score += max(0, 15 - (5 * len(missing_mem)))
                feedback_parts.append(f"Missing Member fields: {', '.join(missing_mem)}.")

            # Check Legal Values for 'Sex'
            # Look for the Field element with Name="Sex"
            sex_field = None
            for f in views['Member'].findall(".//Field"):
                if f.get('Name') == 'Sex':
                    sex_field = f
                    break
            
            if sex_field:
                # Check if it has SourceTableName or is type LegalValues (11 or 17? varies)
                # Usually has SourceTableName attribute if it's a code table
                if sex_field.get('SourceTableName') or sex_field.get('FieldTypeId') in ['11', '17', '18']:
                     score += 10
                     feedback_parts.append("Sex field configured as Legal Values.")
                else:
                     feedback_parts.append("Sex field exists but not configured as Legal Values.")
        else:
            feedback_parts.append("Member form MISSING.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing project file: {e}"}
    finally:
        if os.path.exists(temp_prj.name):
            os.unlink(temp_prj.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }

def get_fields_from_view(view_element):
    """Extract all field names from a View element."""
    fields = set()
    for field in view_element.findall(".//Field"):
        name = field.get('Name')
        if name:
            fields.add(name)
    return fields