#!/usr/bin/env python3
"""Verifier for analyst_ehr_uml_design task.

Checks that ehr_uml_design.eddx contains a 3-page UML design document:
  Page 1: UML Class Diagram with EHR domain classes
  Page 2: UML Use Case Diagram with actors and use cases
  Page 3: UML Sequence Diagram for Schedule Appointment

Scoring (100 pts total, pass threshold = 60):
  A (15): Valid EDDX ZIP archive at the expected path
  B (10): File modified after task start (anti-gaming timestamp check)
  C (25): Document contains >= 3 pages
  D (20): Class diagram content: EHR domain entities (Patient, Doctor, Appointment, etc.)
  E (15): Use Case content: actor/use case keywords on page 2
  F (15): >= 15 total shapes across all pages (3 full UML diagrams are shape-dense)
"""
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAINER_PATH = "/home/ga/ehr_uml_design.eddx"
TS_PATH = "/tmp/analyst_ehr_uml_design_start_ts"

# EHR domain entities expected in the Class Diagram
CLASS_ENTITIES = [
    'patient', 'doctor', 'appointment', 'prescription',
    'medical record', 'medicalrecord', 'department',
    'nurse', 'diagnosis', 'treatment', 'medication', 'hospital',
]

# Use case / actor keywords expected on Page 2
USE_CASE_KEYWORDS = [
    'actor', 'use case', 'usecase', 'schedule', 'appointment',
    'prescription', 'history', 'discharge', 'report', 'manage',
    'patient', 'doctor', 'nurse', 'administrator', 'admin',
]

# Sequence diagram keywords expected on Page 3
SEQUENCE_KEYWORDS = [
    'sequence', 'lifeline', 'message', 'interface', 'service',
    'database', 'schedule', 'appointment', 'request', 'response',
    'web', 'api', 'return',
]


def _count_pages(zf):
    page_xmls = [n for n in zf.namelist() if re.match(r'pages/page\d+\.xml', n)]
    count = len(page_xmls)
    if count > 0:
        return count
    try:
        doc = zf.read('document.xml').decode('utf-8', errors='ignore')
        m = re.search(r'<Pages[^>]*\bV="(\d+)"', doc)
        if m:
            return int(m.group(1))
    except Exception:
        pass
    return count


def _all_xml(zf):
    parts = []
    for name in zf.namelist():
        if name.endswith('.xml'):
            try:
                parts.append(zf.read(name).decode('utf-8', errors='ignore'))
            except Exception:
                pass
    return '\n'.join(parts)


def _page_xml(zf, page_num):
    for c in [f'pages/page{page_num}.xml', f'page{page_num}.xml']:
        try:
            return zf.read(c).decode('utf-8', errors='ignore')
        except Exception:
            pass
    return ''


def verify_analyst_ehr_uml_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    # --- Fetch task start timestamp ---
    start_ts = 0
    ts_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    ts_tmp.close()
    try:
        copy_from_env(TS_PATH, ts_tmp.name)
        with open(ts_tmp.name) as f:
            start_ts = int(f.read().strip())
    except Exception:
        start_ts = 0
    finally:
        try:
            os.unlink(ts_tmp.name)
        except Exception:
            pass

    # --- Fetch the output EDDX ---
    eddx_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.eddx')
    eddx_tmp.close()
    try:
        copy_from_env(CONTAINER_PATH, eddx_tmp.name)
    except Exception as e:
        return {'passed': False, 'score': 0,
                'feedback': f'Output file not found at {CONTAINER_PATH}: {e}'}

    if not os.path.exists(eddx_tmp.name) or os.path.getsize(eddx_tmp.name) == 0:
        return {'passed': False, 'score': 0,
                'feedback': f'Output file {CONTAINER_PATH} is missing or empty'}

    score = 0
    feedback = []

    # --- Criterion A (15 pts): valid ZIP/EDDX ---
    try:
        with zipfile.ZipFile(eddx_tmp.name, 'r') as zf:
            entries = zf.namelist()
    except zipfile.BadZipFile:
        os.unlink(eddx_tmp.name)
        return {'passed': False, 'score': 0,
                'feedback': f'File at {CONTAINER_PATH} is not a valid EDDX/ZIP archive'}
    score += 15
    feedback.append(f'A: Valid EDDX archive ({len(entries)} entries) [+15]')

    # --- Criterion B (10 pts): modified after task start ---
    file_mtime = int(os.path.getmtime(eddx_tmp.name))
    if start_ts > 0 and file_mtime > start_ts:
        score += 10
        feedback.append('B: File modified after task start [+10]')
    elif start_ts == 0:
        score += 5
        feedback.append('B: Task timestamp unavailable; partial credit [+5]')
    else:
        feedback.append('B: File not modified after task start [+0]')

    with zipfile.ZipFile(eddx_tmp.name, 'r') as zf:
        page_count = _count_pages(zf)
        xml_all = _all_xml(zf)
        page1_xml = _page_xml(zf, 1)
        page2_xml = _page_xml(zf, 2)
        page3_xml = _page_xml(zf, 3)

    os.unlink(eddx_tmp.name)

    xml_lower = xml_all.lower()
    page1_lower = page1_xml.lower()
    page2_lower = page2_xml.lower()
    page3_lower = page3_xml.lower()

    # --- Criterion C (25 pts): >= 3 pages ---
    if page_count >= 3:
        score += 25
        feedback.append(f'C: {page_count} pages found (>= 3 required for Class/UseCase/Sequence) [+25]')
    elif page_count == 2:
        score += 10
        feedback.append(f'C: Only 2 pages found; 3 UML diagram pages required [+10]')
    else:
        feedback.append(f'C: Only {page_count} page(s); 3-page UML document required [+0]')

    # --- Criterion D (20 pts): EHR domain entities in Class Diagram (page 1) ---
    # Search page 1 primarily, fall back to all XML
    search_text = page1_lower if page1_lower else xml_lower
    found_entities = [e for e in CLASS_ENTITIES if e in search_text]
    if len(found_entities) >= 5:
        score += 20
        feedback.append(f'D: EHR class entities found: {found_entities[:6]} [+20]')
    elif len(found_entities) >= 3:
        score += 12
        feedback.append(f'D: Partial EHR entities ({found_entities}); need >= 5 [+12]')
    elif len(found_entities) >= 1:
        score += 5
        feedback.append(f'D: Few EHR entities found ({found_entities}); insufficient class diagram [+5]')
    else:
        feedback.append('D: No EHR domain entities (Patient, Doctor, Appointment, etc.) found [+0]')

    # --- Criterion E (15 pts): Use Case content on page 2 ---
    search_p2 = page2_lower if page2_lower else xml_lower
    found_uc = [kw for kw in USE_CASE_KEYWORDS if kw in search_p2]
    if len(found_uc) >= 5:
        score += 15
        feedback.append(f'E: Use Case keywords: {found_uc[:5]} [+15]')
    elif len(found_uc) >= 3:
        score += 8
        feedback.append(f'E: Partial use case content ({found_uc}) [+8]')
    else:
        found_seq = [kw for kw in SEQUENCE_KEYWORDS if kw in xml_lower]
        if len(found_seq) >= 3:
            score += 5
            feedback.append(f'E: Sequence keywords found but not use case; partial [+5]')
        else:
            feedback.append('E: No use case diagram content detected on page 2 [+0]')

    # --- Criterion F (15 pts): >= 15 total shapes ---
    shape_count = len(re.findall(r'<Shape\s+Type="Shape"', xml_all))
    connector_count = len(re.findall(r'<Shape\s+Type="ConnectLine"', xml_all))
    if shape_count >= 15:
        score += 15
        feedback.append(f'F: {shape_count} shapes, {connector_count} connectors (3 full UML diagrams) [+15]')
    elif shape_count >= 9:
        score += 8
        feedback.append(f'F: {shape_count} shapes — partial (need >= 15 across 3 UML diagrams) [+8]')
    else:
        feedback.append(f'F: Only {shape_count} shapes; 3 detailed UML diagrams require more [+0]')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}
