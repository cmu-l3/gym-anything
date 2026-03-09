#!/usr/bin/env python3
"""
Verifier for technical_manual_master_assembly task.
Verifies that a LibreOffice Master Document (.odm) was created and correctly links sub-documents.
"""

import json
import os
import sys
import tempfile
import zipfile
import shutil
import logging
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_master_document(traj, env_info, task_info):
    """
    Verify the Master Document assembly.
    
    Criteria:
    1. File 'hydra_manual_master.odm' exists and was created/modified during task.
    2. File is a valid ODF Master Document (mimetype check).
    3. File contains links to the 3 specific ODT files (01, 02, 03) in correct order.
    4. File contains a Table of Contents structure.
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result metadata
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    # Basic checks
    if not result_meta.get('output_exists'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Master document file 'hydra_manual_master.odm' not found."
        }

    # Copy the ODM file for analysis
    remote_path = result_meta['output_path']
    temp_odm = tempfile.NamedTemporaryFile(delete=False, suffix='.odm')
    temp_odm_path = temp_odm.name
    temp_odm.close()

    try:
        copy_from_env(remote_path, temp_odm_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to copy output file: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. File Created During Task (Anti-gaming) (15 pts)
    if result_meta.get('file_created_during_task'):
        score += 15
        feedback_parts.append("File created/modified during task")
    else:
        feedback_parts.append("File timestamp indicates no change during task")

    # Analyze ODF structure
    try:
        if not zipfile.is_zipfile(temp_odm_path):
            return {"passed": False, "score": score, "feedback": "Output file is not a valid ODF/ZIP archive."}

        with zipfile.ZipFile(temp_odm_path, 'r') as z:
            # 2. Check Mimetype (15 pts)
            try:
                mimetype = z.read('mimetype').decode('utf-8').strip()
                if mimetype == 'application/vnd.oasis.opendocument.text-master':
                    score += 15
                    feedback_parts.append("Correct Master Document format")
                else:
                    feedback_parts.append(f"Incorrect file format: {mimetype} (expected text-master)")
            except KeyError:
                feedback_parts.append("Invalid ODF: mimetype file missing")

            # Parse content.xml
            try:
                content_xml = z.read('content.xml')
                root = ET.fromstring(content_xml)
                
                # Namespaces
                ns = {
                    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                    'xlink': 'http://www.w3.org/1999/xlink'
                }

                # 3. Check for Links (45 pts total, 15 per link)
                # Links in Master Doc are typically inside text:section with text:section-source
                # or text:section with text:link-name? 
                # In .odm, they appear as <text:section text:name="..."><text:section-source xlink:href="..."/></text:section>
                
                sections = root.findall('.//text:section', ns)
                linked_files = []
                
                for section in sections:
                    source = section.find('text:section-source', ns)
                    if source is not None:
                        href = source.get(f"{{{ns['xlink']}}}href")
                        if href:
                            linked_files.append(href)

                # Check for specific files
                expected_files = ["01_safety.odt", "02_operation.odt", "03_maintenance.odt"]
                links_found = 0
                
                # Check ordering and existence
                # We relax absolute/relative path check, just look for filename substring
                found_indices = []
                for exp in expected_files:
                    found = False
                    for idx, link in enumerate(linked_files):
                        if exp in link:
                            links_found += 1
                            found_indices.append(idx)
                            found = True
                            break
                    if found:
                        feedback_parts.append(f"Link found: {exp}")
                    else:
                        feedback_parts.append(f"Link MISSING: {exp}")

                # Scoring links
                score += (links_found * 15)

                # Check ordering (indices should be increasing)
                if len(found_indices) == 3 and found_indices == sorted(found_indices):
                    feedback_parts.append("Links are in correct order")
                elif len(found_indices) > 1 and found_indices != sorted(found_indices):
                    feedback_parts.append("Links are NOT in correct order")
                    score = max(0, score - 10) # Penalty for wrong order

                # 4. Check for Table of Contents (25 pts)
                # Look for <text:table-of-content>
                toc = root.find('.//text:table-of-content', ns)
                if toc is not None:
                    score += 25
                    feedback_parts.append("Table of Contents found")
                else:
                    feedback_parts.append("Table of Contents MISSING")

            except KeyError:
                feedback_parts.append("Invalid ODF: content.xml missing")
            except ET.ParseError:
                feedback_parts.append("XML Parse Error in content.xml")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odm_path):
            os.unlink(temp_odm_path)

    passed = (score >= 85)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }