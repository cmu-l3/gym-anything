#!/usr/bin/env python3
"""Verifier for bcp_ransomware_response task.

Checks that ransomware_ir_flowchart.eddx contains a professional cross-functional
swimlane incident response diagram with the required structural elements.

Scoring (100 pts total, pass threshold = 60):
  A (15): Valid EDDX ZIP archive at the expected path
  B (10): File was modified after task start (anti-gaming timestamp check)
  C (20): Document contains >= 2 pages
  D (15): Swimlane/pool/lane structure present in diagram XML
  E (20): >= 10 shape elements AND >= 5 connector elements
  F (10): Decision diamond shapes present (incident response requires branching)
  G (10): Page 2 contains non-trivial text (executive summary content)
"""
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAINER_PATH = "/home/ga/ransomware_ir_flowchart.eddx"
TS_PATH = "/tmp/bcp_ransomware_response_start_ts"


def _count_pages(zf):
    """Return number of pages detected in the EDDX archive."""
    # Method 1: count pages/pageN.xml entries
    page_xmls = [n for n in zf.namelist() if re.match(r'pages/page\d+\.xml', n)]
    count = len(page_xmls)
    if count > 0:
        return count
    # Method 2: parse document.xml for <Pages V="N"/>
    try:
        doc = zf.read('document.xml').decode('utf-8', errors='ignore')
        m = re.search(r'<Pages[^>]*\bV="(\d+)"', doc)
        if m:
            return int(m.group(1))
    except Exception:
        pass
    return count


def _all_xml(zf):
    """Concatenate all XML file contents from the archive."""
    parts = []
    for name in zf.namelist():
        if name.endswith('.xml'):
            try:
                parts.append(zf.read(name).decode('utf-8', errors='ignore'))
            except Exception:
                pass
    return '\n'.join(parts)


def _page_xml(zf, page_num):
    """Return XML text for a specific page, or empty string."""
    candidates = [
        f'pages/page{page_num}.xml',
        f'page{page_num}.xml',
    ]
    for c in candidates:
        try:
            return zf.read(c).decode('utf-8', errors='ignore')
        except Exception:
            pass
    return ''


def verify_bcp_ransomware_response(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {'passed': False, 'score': 0, 'feedback': 'copy_from_env not available'}

    # --- Fetch task start timestamp (for anti-gaming check) ---
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

    # --- Fetch the output EDDX file ---
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

    # --- Criterion A (15 pts): valid ZIP/EDDX archive ---
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
        feedback.append(f'B: File modified after task start (mtime={file_mtime} > start={start_ts}) [+10]')
    elif start_ts == 0:
        # Timestamp unavailable — award partial credit
        score += 5
        feedback.append('B: Task timestamp unavailable; partial credit awarded [+5]')
    else:
        feedback.append(f'B: File mtime ({file_mtime}) not after task start ({start_ts}) — possible pre-existing file [+0]')

    with zipfile.ZipFile(eddx_tmp.name, 'r') as zf:
        page_count = _count_pages(zf)
        xml_all = _all_xml(zf)
        page2_xml = _page_xml(zf, 2)

    os.unlink(eddx_tmp.name)

    # --- Criterion C (20 pts): >= 2 pages ---
    if page_count >= 2:
        score += 20
        feedback.append(f'C: {page_count} pages found (>= 2 required) [+20]')
    elif page_count == 1:
        feedback.append('C: Only 1 page found; Page 2 (Executive Summary) is required [+0]')
    else:
        feedback.append('C: No pages detected in archive [+0]')

    # --- Criterion D (15 pts): swimlane/pool/lane structure ---
    nameu_vals = re.findall(r'NameU="([^"]*)"', xml_all)
    nameu_lower = [v.lower() for v in nameu_vals]
    has_swimlane = (
        any('swim' in v for v in nameu_lower) or
        any('lane' in v for v in nameu_lower) or
        any('pool' in v for v in nameu_lower) or
        'swimlane' in xml_all.lower() or
        'cross-functional' in xml_all.lower() or
        re.search(r'<Lane\b|<Pool\b|<Swimlane\b|<SwimLane\b', xml_all) is not None
    )
    if has_swimlane:
        score += 15
        feedback.append('D: Swimlane/pool/lane diagram structure detected [+15]')
    else:
        feedback.append('D: No swimlane structure found; diagram should use cross-functional swimlane layout [+0]')

    # --- Criterion E (20 pts): >= 10 shapes AND >= 5 connectors ---
    shape_count = len(re.findall(r'<Shape\s+Type="Shape"', xml_all))
    connector_count = len(re.findall(r'<Shape\s+Type="ConnectLine"', xml_all))
    if shape_count >= 10 and connector_count >= 5:
        score += 20
        feedback.append(f'E: {shape_count} shapes and {connector_count} connectors (thresholds: 10/5) [+20]')
    elif shape_count >= 6 and connector_count >= 3:
        score += 10
        feedback.append(f'E: {shape_count} shapes, {connector_count} connectors — partial (need >=10 shapes, >=5 connectors) [+10]')
    else:
        feedback.append(f'E: Too few elements: {shape_count} shapes, {connector_count} connectors [+0]')

    # --- Criterion F (10 pts): decision diamonds present ---
    has_decision = any('decision' in v for v in nameu_lower)
    if has_decision:
        score += 10
        feedback.append('F: Decision diamond shapes present (required for IR branching logic) [+10]')
    else:
        feedback.append('F: No decision diamond shapes detected; IR workflow must include decision points [+0]')

    # --- Criterion G (10 pts): page 2 has non-trivial text ---
    page2_chars = re.findall(r'<Chars\s+V="([^"]*)"', page2_xml)
    page2_text = ' '.join(page2_chars).strip()
    has_page2_content = len(page2_text) >= 30 or len(page2_chars) >= 5
    if has_page2_content:
        score += 10
        feedback.append(f'G: Page 2 contains text content ({len(page2_chars)} text elements) [+10]')
    else:
        feedback.append('G: Page 2 lacks sufficient text for an Executive Summary [+0]')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}
