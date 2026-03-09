#!/usr/bin/env python3
"""Verifier for indusengg_vsm_lean_design task.

Checks that vsm_current_future.eddx contains a 2-page Value Stream Map (VSM)
with a Current State VSM (Page 1) and a Future State VSM (Page 2).

Scoring (100 pts total, pass threshold = 60):
  A (15): Valid EDDX ZIP archive at the expected path
  B (10): File modified after task start (anti-gaming timestamp check)
  C (20): Document contains >= 2 pages
  D (20): VSM-specific content on page 1 (supplier, customer, process, inventory,
          push, timeline, cycle time, etc.)
  E (20): >= 12 shapes AND >= 6 connectors across the document
  F (10): Page 2 has future state / kaizen content
  G (5):  Lean/VSM shape types present (VSM library shapes)
"""
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAINER_PATH = "/home/ga/vsm_current_future.eddx"
TS_PATH = "/tmp/indusengg_vsm_lean_design_start_ts"

# VSM-specific content keywords (page 1 — current state)
VSM_KEYWORDS = [
    'supplier', 'customer', 'inventory', 'push', 'pull', 'kanban',
    'cycle time', 'changeover', 'uptime', 'operator',
    'lead time', 'value added', 'non-value', 'takt time',
    'stamping', 'welding', 'assembly', 'treatment', 'production',
    'process', 'timeline', 'information flow', 'production control',
    'planning', 'forecast', 'shipment', 'raw material',
]

# Future state / kaizen keywords (page 2)
FUTURE_KEYWORDS = [
    'future', 'kaizen', 'improvement', 'lean', 'waste', 'reduce',
    'kanban', 'pull', 'flow', 'one-piece', 'continuous',
    'cycle time', 'lead time', 'target', 'goal',
]

# VSM shape library NameU values
VSM_SHAPE_NAMES = [
    'manufacturing process', 'inventory', 'push arrow', 'pull arrow',
    'kaizen burst', 'supplier', 'customer', 'production control',
    'truck', 'timeline', 'data box', 'operator',
    'vsm', 'lean', 'value stream',
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


def verify_indusengg_vsm_lean_design(traj, env_info, task_info):
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

    os.unlink(eddx_tmp.name)

    xml_lower = xml_all.lower()
    page1_lower = page1_xml.lower()
    page2_lower = page2_xml.lower()

    # --- Criterion C (20 pts): >= 2 pages ---
    if page_count >= 2:
        score += 20
        feedback.append(f'C: {page_count} pages found (current + future state) [+20]')
    else:
        feedback.append(f'C: Only {page_count} page(s); 2 pages required (current + future state) [+0]')

    # --- Criterion D (20 pts): VSM-specific content on page 1 ---
    search_p1 = page1_lower if page1_lower else xml_lower
    found_vsm = [kw for kw in VSM_KEYWORDS if kw in search_p1]
    if len(found_vsm) >= 6:
        score += 20
        feedback.append(f'D: VSM content found: {found_vsm[:6]} [+20]')
    elif len(found_vsm) >= 3:
        score += 12
        feedback.append(f'D: Partial VSM content ({found_vsm}); need >= 6 VSM keywords [+12]')
    elif len(found_vsm) >= 1:
        score += 5
        feedback.append(f'D: Minimal VSM content ({found_vsm}); not a complete VSM [+5]')
    else:
        feedback.append('D: No VSM-specific content found on page 1 [+0]')

    # --- Criterion E (20 pts): >= 12 shapes AND >= 6 connectors ---
    shape_count = len(re.findall(r'<Shape\s+Type="Shape"', xml_all))
    connector_count = len(re.findall(r'<Shape\s+Type="ConnectLine"', xml_all))
    if shape_count >= 12 and connector_count >= 6:
        score += 20
        feedback.append(f'E: {shape_count} shapes, {connector_count} connectors [+20]')
    elif shape_count >= 7 and connector_count >= 3:
        score += 10
        feedback.append(f'E: {shape_count} shapes, {connector_count} connectors — partial (need >=12/6) [+10]')
    else:
        feedback.append(f'E: Too few elements: {shape_count} shapes, {connector_count} connectors [+0]')

    # --- Criterion F (10 pts): page 2 has future state content ---
    search_p2 = page2_lower if page2_lower else ''
    found_future = [kw for kw in FUTURE_KEYWORDS if kw in search_p2]
    page2_chars = re.findall(r'<Chars\s+V="([^"]*)"', page2_xml)
    if len(found_future) >= 2 or len(page2_chars) >= 6:
        score += 10
        feedback.append(f'F: Page 2 future state content (keywords: {found_future[:3]}) [+10]')
    else:
        feedback.append('F: Page 2 lacks future state VSM / kaizen content [+0]')

    # --- Criterion G (5 pts): VSM shape library shapes ---
    nameu_vals = re.findall(r'NameU="([^"]*)"', xml_all)
    nameu_lower_vals = [v.lower() for v in nameu_vals]
    found_vsm_shapes = [s for s in VSM_SHAPE_NAMES
                        if any(s in v for v in nameu_lower_vals)]
    if found_vsm_shapes:
        score += 5
        feedback.append(f'G: VSM library shape types detected: {found_vsm_shapes[:3]} [+5]')
    else:
        feedback.append('G: No VSM-specific shape library types detected (generic shapes used) [+0]')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}
