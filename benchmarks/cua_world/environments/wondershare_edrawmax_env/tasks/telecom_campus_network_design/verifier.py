#!/usr/bin/env python3
"""Verifier for telecom_campus_network_design task.

Checks that campus_network_topology.eddx contains a complete campus network
topology with perimeter security, layered switching, servers, clients, and
wireless, plus a 2nd-page IP addressing plan.

Scoring (100 pts total, pass threshold = 60):
  A (15): Valid EDDX ZIP archive at the expected path
  B (10): File modified after task start (anti-gaming timestamp check)
  C (20): Document contains >= 2 pages
  D (15): Network device keywords present (router, switch, firewall, server, AP)
  E (20): >= 15 shapes AND >= 8 connectors (full campus network is dense)
  F (10): Security/firewall component present
  G (10): Page 2 contains IP addressing content (subnet, VLAN, IP range text)
"""
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAINER_PATH = "/home/ga/campus_network_topology.eddx"
TS_PATH = "/tmp/telecom_campus_network_design_start_ts"

NETWORK_KEYWORDS = [
    'router', 'switch', 'firewall', 'server', 'access point',
    'wireless', 'wifi', 'wan', 'lan', 'vlan', 'trunk',
    'core', 'distribution', 'access layer', 'isp', 'internet',
    'workstation', 'desktop', 'pc', 'client', 'host',
    'dmz', 'gateway', 'hub', 'bridge', 'modem',
]

SECURITY_KEYWORDS = ['firewall', 'dmz', 'perimeter', 'security', 'acl', 'ips', 'ids']

IP_KEYWORDS = [
    'subnet', 'vlan', '192.168', '10.0', '172.16', '/24', '/16', '/8',
    'ip address', 'ip range', 'cidr', 'dhcp', 'dns', 'gateway',
    'addressing plan', 'address plan', 'network address',
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


def verify_telecom_campus_network_design(traj, env_info, task_info):
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
        page2_xml = _page_xml(zf, 2)

    os.unlink(eddx_tmp.name)

    xml_lower = xml_all.lower()
    page2_lower = page2_xml.lower()

    # --- Criterion C (20 pts): >= 2 pages ---
    if page_count >= 2:
        score += 20
        feedback.append(f'C: {page_count} pages found [+20]')
    else:
        feedback.append(f'C: Only {page_count} page(s); Page 2 (IP Addressing Plan) required [+0]')

    # --- Criterion D (15 pts): network device keywords ---
    found_net = [kw for kw in NETWORK_KEYWORDS if kw in xml_lower]
    if len(found_net) >= 5:
        score += 15
        feedback.append(f'D: Network keywords: {found_net[:6]} [+15]')
    elif len(found_net) >= 3:
        score += 8
        feedback.append(f'D: Some network keywords ({found_net}) but limited coverage [+8]')
    else:
        feedback.append(f'D: Insufficient network device content in diagram [+0]')

    # --- Criterion E (20 pts): >= 15 shapes AND >= 8 connectors ---
    shape_count = len(re.findall(r'<Shape\s+Type="Shape"', xml_all))
    connector_count = len(re.findall(r'<Shape\s+Type="ConnectLine"', xml_all))
    if shape_count >= 15 and connector_count >= 8:
        score += 20
        feedback.append(f'E: {shape_count} shapes, {connector_count} connectors [+20]')
    elif shape_count >= 8 and connector_count >= 4:
        score += 10
        feedback.append(f'E: {shape_count} shapes, {connector_count} connectors — partial (need >=15/8) [+10]')
    else:
        feedback.append(f'E: Too few elements: {shape_count} shapes, {connector_count} connectors [+0]')

    # --- Criterion F (10 pts): firewall/security component ---
    has_security = any(kw in xml_lower for kw in SECURITY_KEYWORDS)
    if has_security:
        score += 10
        feedback.append('F: Security/firewall component present [+10]')
    else:
        feedback.append('F: No firewall or security perimeter device detected [+0]')

    # --- Criterion G (10 pts): page 2 has IP addressing content ---
    found_ip = [kw for kw in IP_KEYWORDS if kw in page2_lower]
    page2_chars = re.findall(r'<Chars\s+V="([^"]*)"', page2_xml)
    if len(found_ip) >= 2 or len(page2_chars) >= 8:
        score += 10
        feedback.append(f'G: Page 2 IP addressing content detected (keywords: {found_ip[:4]}) [+10]')
    else:
        feedback.append('G: Page 2 lacks IP addressing plan content [+0]')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}
