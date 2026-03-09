#!/usr/bin/env python3
"""Verifier for sysarch_aws_cloud_architecture task.

Checks that aws_cloud_architecture.eddx contains a real 3-tier AWS cloud
architecture diagram spanning at least two pages.

Scoring (100 pts total, pass threshold = 60):
  A (15): Valid EDDX ZIP archive at the expected path
  B (10): File modified after task start (anti-gaming timestamp check)
  C (20): Document contains >= 2 pages
  D (15): AWS/cloud architecture keywords present in diagram content
  E (20): >= 12 shapes AND >= 6 connectors (complex multi-component architecture)
  F (10): Three-tier evidence (web/presentation + app/logic + data tier keywords)
  G (10): Page 2 has non-trivial text (DR / failover content)
"""
import os
import re
import tempfile
import zipfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

CONTAINER_PATH = "/home/ga/aws_cloud_architecture.eddx"
TS_PATH = "/tmp/sysarch_aws_cloud_architecture_start_ts"

# AWS/cloud service keywords that indicate real architecture content
AWS_KEYWORDS = [
    'ec2', 'rds', 's3', 'vpc', 'subnet', 'elb', 'alb', 'nlb',
    'lambda', 'cloudfront', 'route53', 'iam', 'security group',
    'availability zone', 'internet gateway', 'nat gateway',
    'elastic', 'auto scaling', 'eks', 'ecs', 'fargate',
    'aurora', 'dynamodb', 'elasticache', 'sqs', 'sns',
    'load balancer', 'web tier', 'app tier', 'data tier',
    'application tier', 'presentation tier', 'database tier',
]

# Three-tier evidence keywords
TIER_WEB = ['web', 'presentation', 'frontend', 'nginx', 'apache', 'cloudfront']
TIER_APP = ['app', 'application', 'logic', 'backend', 'api', 'service', 'lambda', 'ec2']
TIER_DATA = ['data', 'database', 'rds', 'db', 'aurora', 'dynamo', 's3', 'storage', 'cache']


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


def verify_sysarch_aws_cloud_architecture(traj, env_info, task_info):
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
        feedback.append(f'B: File modified after task start [+10]')
    elif start_ts == 0:
        score += 5
        feedback.append('B: Task timestamp unavailable; partial credit [+5]')
    else:
        feedback.append(f'B: File not modified after task start [+0]')

    with zipfile.ZipFile(eddx_tmp.name, 'r') as zf:
        page_count = _count_pages(zf)
        xml_all = _all_xml(zf)
        page2_xml = _page_xml(zf, 2)

    os.unlink(eddx_tmp.name)

    xml_lower = xml_all.lower()

    # --- Criterion C (20 pts): >= 2 pages ---
    if page_count >= 2:
        score += 20
        feedback.append(f'C: {page_count} pages found [+20]')
    else:
        feedback.append(f'C: Only {page_count} page(s); Page 2 (DR architecture) required [+0]')

    # --- Criterion D (15 pts): AWS/cloud keywords in content ---
    found_aws = [kw for kw in AWS_KEYWORDS if kw in xml_lower]
    if len(found_aws) >= 4:
        score += 15
        feedback.append(f'D: AWS/cloud keywords found: {found_aws[:6]} [+15]')
    elif len(found_aws) >= 2:
        score += 8
        feedback.append(f'D: Some cloud keywords found ({found_aws}) but limited AWS content [+8]')
    else:
        feedback.append(f'D: Insufficient AWS/cloud architecture keywords in diagram [+0]')

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

    # --- Criterion F (10 pts): three-tier evidence ---
    has_web = any(kw in xml_lower for kw in TIER_WEB)
    has_app = any(kw in xml_lower for kw in TIER_APP)
    has_data = any(kw in xml_lower for kw in TIER_DATA)
    tier_count = sum([has_web, has_app, has_data])
    if tier_count >= 3:
        score += 10
        feedback.append('F: All three tiers (web/app/data) detected in diagram [+10]')
    elif tier_count >= 2:
        score += 5
        feedback.append(f'F: Only {tier_count}/3 tiers detected [+5]')
    else:
        feedback.append('F: 3-tier structure not evident in diagram [+0]')

    # --- Criterion G (10 pts): page 2 has text (DR content) ---
    page2_chars = re.findall(r'<Chars\s+V="([^"]*)"', page2_xml)
    page2_text = ' '.join(page2_chars).strip()
    if len(page2_text) >= 20 or len(page2_chars) >= 4:
        score += 10
        feedback.append(f'G: Page 2 contains text content ({len(page2_chars)} elements) [+10]')
    else:
        feedback.append('G: Page 2 lacks content for DR/failover architecture [+0]')

    passed = score >= 60
    return {'passed': passed, 'score': score, 'feedback': ' | '.join(feedback)}
