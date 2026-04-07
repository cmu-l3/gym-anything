#!/usr/bin/env python3
"""
Verifier for Enable XML Documentation task in Visual Studio 2022.

Verification Strategy (File-based + State Verification):
1. Project property configuration: Checks if `<GenerateDocumentationFile>` is True in `.csproj`
2. XML Artifact Existence: Checks if the file was produced in the `bin/Release/net6.0/` directory
3. XML Completeness: Parses the generated XML file to ensure all public classes (4) and methods (16) are documented
4. Content richness: Checks for `<param>` and `<returns>` tags in the XML
5. Anti-gaming: Validates file modification timestamps to ensure the build happened during the task.
"""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_xml_documentation(traj, env_info, task_info):
    """
    Verify the configuration and generation of XML documentation in Visual Studio.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # Create temp files to hold copied artifacts
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        # Copy the JSON results
        try:
            copy_from_env("C:\\task_result.json", temp_json.name)
            with open(temp_json.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        # 1. Project file config (10 points)
        doc_enabled = result.get('doc_enabled', False)
        if doc_enabled:
            score += 10
            feedback_parts.append("Project XML doc generation enabled")
        else:
            feedback_parts.append("Project XML doc generation NOT enabled in .csproj")

        # 2. Source file comments presence (5 points)
        if result.get('source_files_has_comments', False):
            score += 5
            feedback_parts.append("Source files contain /// comments")
        else:
            feedback_parts.append("Some source files missing /// comments")

        # 3. XML File Exists and Build succeeded in Release (15 points total)
        xml_exists = result.get('xml_exists', False)
        if xml_exists:
            score += 10
            feedback_parts.append("Release XML documentation file exists")
            
            # Anti-gaming: check timestamp
            task_start = result.get('task_start', 0)
            xml_mtime = result.get('xml_mtime', 0)
            if xml_mtime > task_start and task_start > 0:
                score += 5
                feedback_parts.append("Build verified as new (timestamp valid)")
            else:
                feedback_parts.append("Warning: XML file timestamp predates task start")
                
            # Now parse the XML for detailed scoring
            try:
                copy_from_env("C:\\task_result_doc.xml", temp_xml.name)
                tree = ET.parse(temp_xml.name)
                root = tree.getroot()
                members_node = root.find('members')
                
                if members_node is not None:
                    # Find all types (T:) and methods (M:)
                    classes = [m for m in members_node.findall('member') if m.get('name', '').startswith('T:')]
                    methods = [m for m in members_node.findall('member') if m.get('name', '').startswith('M:')]
                    
                    # 4. Classes Documented (Max 16 points: 4 pts per class)
                    documented_classes = 0
                    for c in classes:
                        summary = c.find('summary')
                        if summary is not None and summary.text and summary.text.strip():
                            documented_classes += 1
                    
                    class_pts = min(16, documented_classes * 4)
                    score += class_pts
                    feedback_parts.append(f"{documented_classes}/4 classes documented")

                    # 5. Methods Documented (Max 32 points: 2 pts per method)
                    # 6. Params Documented (Max 12 points)
                    # 7. Returns Documented (Max 10 points)
                    documented_methods = 0
                    params_found = 0
                    returns_found = 0
                    
                    for m in methods:
                        # Summary check
                        summary = m.find('summary')
                        if summary is not None and summary.text and summary.text.strip():
                            documented_methods += 1
                        
                        # Param check
                        params = m.findall('param')
                        params_found += len(params)
                        
                        # Returns check
                        returns = m.find('returns')
                        if returns is not None and returns.text and returns.text.strip():
                            returns_found += 1
                    
                    method_pts = min(32, documented_methods * 2)
                    score += method_pts
                    feedback_parts.append(f"{documented_methods}/16 methods documented")
                    
                    # Total expected params is 19. Proportional scoring up to 12.
                    param_pts = min(12, int((params_found / 19.0) * 12)) if params_found > 0 else 0
                    score += param_pts
                    feedback_parts.append(f"{params_found}/19 parameters documented")
                    
                    # Total expected return values is 16 (all return something). Proportional scoring up to 10.
                    return_pts = min(10, int((returns_found / 16.0) * 10)) if returns_found > 0 else 0
                    score += return_pts
                    feedback_parts.append(f"{returns_found}/16 return tags present")
                else:
                    feedback_parts.append("XML is malformed (no <members> node)")
            except Exception as xml_e:
                feedback_parts.append(f"Failed to parse XML: {xml_e}")
        else:
            feedback_parts.append("Release XML output missing. Did the build succeed in Release config?")
            
    finally:
        # Cleanup temp files
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # Calculate pass threshold
    # Must get >= 60 points AND have produced the XML file AND documented at least 10 methods
    key_criteria_met = xml_exists and (doc_enabled) and (documented_methods >= 10 if 'documented_methods' in locals() else False)
    passed = score >= 60 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }