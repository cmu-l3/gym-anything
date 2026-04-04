#!/bin/bash
# Export script for Project CI Environment Setup task.
# Inspects alpha-backend-build, alpha-frontend-build, npm-registry-token, and the view.

echo "=== Exporting Project CI Environment Setup Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

# ── Fetch job config XMLs ─────────────────────────────────────
echo "Fetching job configs..."
BACKEND_CONFIG=""
FRONTEND_CONFIG=""

job_exists "alpha-backend-build"  && BACKEND_CONFIG=$(get_job_config "alpha-backend-build" 2>/dev/null)
job_exists "alpha-frontend-build" && FRONTEND_CONFIG=$(get_job_config "alpha-frontend-build" 2>/dev/null)

echo "alpha-backend-build config length:  ${#BACKEND_CONFIG}"
echo "alpha-frontend-build config length: ${#FRONTEND_CONFIG}"

# ── Fetch credential info ─────────────────────────────────────
echo "Checking npm-registry-token credential..."
CRED_JSON=$(jenkins_api "credentials/store/system/domain/_/credential/npm-registry-token/api/json" 2>/dev/null || echo '{}')
echo "Credential JSON: $CRED_JSON"

# ── Fetch view info ───────────────────────────────────────────
echo "Checking 'Project-Alpha CI' view..."
VIEW_JSON=$(jenkins_api "view/Project-Alpha%20CI/api/json" 2>/dev/null || echo '{}')
echo "View JSON: $VIEW_JSON"

# ── Parse everything with Python ─────────────────────────────
python3 << PYEOF
import json, re, sys
import xml.etree.ElementTree as ET

# ── Helpers ──────────────────────────────────────────────────

def parse_xml_safe(xml_text):
    if not xml_text or len(xml_text.strip()) < 10:
        return None
    try:
        return ET.fromstring(xml_text)
    except Exception:
        return None

def is_pipeline_job(config_xml):
    """Return True if job uses workflow-job (Pipeline) definition."""
    if not config_xml:
        return False
    root = parse_xml_safe(config_xml)
    if root is None:
        return False
    tag = root.tag.lower()
    return 'flow-definition' in tag or 'workflow' in tag

def get_git_url(config_xml):
    """Return Git remote URL from config XML, or empty string."""
    if not config_xml:
        return ''
    root = parse_xml_safe(config_xml)
    if root is None:
        # Fallback: text search
        m = re.search(r'<url>\s*(https?://[^\s<]+)\s*</url>', config_xml)
        return m.group(1).strip() if m else ''
    # CpsScmFlowDefinition or standard GitSCM
    for url_el in root.iter('url'):
        val = (url_el.text or '').strip()
        if val.startswith('http') and 'github' in val:
            return val
    # Also check userRemoteConfigs
    for cfg in root.iter('hudson.plugins.git.UserRemoteConfig'):
        url_el = cfg.find('url')
        if url_el is not None and url_el.text:
            return url_el.text.strip()
    return ''

def get_scm_class(config_xml):
    """Return the SCM class attribute or tag for the job."""
    if not config_xml:
        return ''
    root = parse_xml_safe(config_xml)
    if root is None:
        return ''
    # Check <scm class="..."> attribute
    for el in root.iter('scm'):
        cls = el.get('class', '')
        if cls:
            return cls
    # For CpsScmFlowDefinition
    for el in root.iter('definition'):
        cls = el.get('class', '')
        if 'ScmFlow' in cls or 'Git' in cls:
            return cls
    return ''

def get_scm_branch(config_xml):
    """Return branch name from BranchSpec, or empty string."""
    if not config_xml:
        return ''
    root = parse_xml_safe(config_xml)
    if root is None:
        m = re.search(r'<name>\s*(\*/?\w+)\s*</name>', config_xml)
        return m.group(1).strip() if m else ''
    for spec in root.iter('hudson.plugins.git.BranchSpec'):
        name_el = spec.find('name')
        if name_el is not None and name_el.text:
            return name_el.text.strip()
    return ''

def get_scm_poll_spec(config_xml):
    """Return SCM polling cron spec, or empty string."""
    if not config_xml:
        return ''
    root = parse_xml_safe(config_xml)
    if root is None:
        m = re.search(r'<spec>\s*([^\s<]+[^<]*)\s*</spec>', config_xml)
        return m.group(1).strip() if m else ''
    for trigger in root.iter('hudson.triggers.SCMTrigger'):
        spec_el = trigger.find('spec')
        if spec_el is not None and spec_el.text:
            return spec_el.text.strip()
    # Also look for <triggers> containing SCMTrigger
    for triggers in root.iter('triggers'):
        for child in triggers:
            if 'SCM' in child.tag:
                spec_el = child.find('spec')
                if spec_el is not None and spec_el.text:
                    return spec_el.text.strip()
    return ''

def get_choice_param(config_xml, param_name):
    """Return list of choices for a ChoiceParameter, or empty list."""
    if not config_xml:
        return []
    root = parse_xml_safe(config_xml)
    if root is None:
        return []
    for param in root.iter():
        if 'choice' in param.tag.lower():
            name_el = param.find('name')
            if name_el is not None and (name_el.text or '').strip() == param_name:
                # Choices are either <choices> with newline-separated or <choice> children
                choices_el = param.find('choices')
                if choices_el is not None and choices_el.text:
                    return [c.strip() for c in choices_el.text.strip().splitlines() if c.strip()]
                # Some plugins use a nested <a class="string-array"> structure
                for a_el in param.iter('a'):
                    items = [s.find('string') for s in a_el if s.find('string') is not None]
                    if items:
                        return [(s.text or '').strip() for s in items if s is not None]
                # Collect <string> children
                strings = [s.text for s in param.iter('string') if s.text]
                if strings:
                    return [s.strip() for s in strings if s.strip()]
    # Fallback: find param_name in raw XML then extract choices block
    idx = config_xml.find('<name>' + param_name + '</name>')
    if idx != -1:
        chunk = config_xml[max(0, idx-200):idx+500]
        m = re.search(r'<choices[^>]*>(.*?)</choices>', chunk, re.DOTALL)
        if m:
            return [c.strip() for c in m.group(1).strip().splitlines() if c.strip()]
    return []

def get_build_discarder_keep(config_xml):
    """Return numToKeep value from build discarder, or empty string."""
    if not config_xml:
        return ''
    root = parse_xml_safe(config_xml)
    if root is None:
        m = re.search(r'<numToKeep>\s*(-?\d+)\s*</numToKeep>', config_xml)
        return m.group(1).strip() if m else ''
    for strategy in root.iter('hudson.tasks.LogRotator'):
        num_el = strategy.find('numToKeep')
        if num_el is not None and num_el.text:
            return num_el.text.strip()
    for prop in root.iter('jenkins.model.BuildDiscarderProperty'):
        for strategy in prop.iter():
            num_el = strategy.find('numToKeep')
            if num_el is not None and num_el.text:
                return num_el.text.strip()
    return ''

def check_pipeline_script_for_git(config_xml, target_url):
    """Check if pipeline script contains a git() step targeting target_url."""
    if not config_xml:
        return False
    root = parse_xml_safe(config_xml)
    script_text = config_xml
    if root is not None:
        for s in root.iter('script'):
            if s.text and len(s.text.strip()) > 10:
                script_text = s.text
                break
    return target_url in script_text or 'pipeline-examples' in script_text

# ── Parse inputs ──────────────────────────────────────────────

BACKEND_CONFIG  = """${BACKEND_CONFIG}"""
FRONTEND_CONFIG = """${FRONTEND_CONFIG}"""
CRED_JSON_STR   = """${CRED_JSON}"""
VIEW_JSON_STR   = """${VIEW_JSON}"""
TARGET_GIT_URL  = "https://github.com/jenkinsci/pipeline-examples"

# ── Backend job analysis ──────────────────────────────────────
backend_exists  = len(BACKEND_CONFIG.strip()) > 50
backend_is_pipeline = is_pipeline_job(BACKEND_CONFIG) if backend_exists else False
backend_git_url     = get_git_url(BACKEND_CONFIG) if backend_exists else ''
backend_scm_class   = get_scm_class(BACKEND_CONFIG) if backend_exists else ''
backend_scm_branch  = get_scm_branch(BACKEND_CONFIG) if backend_exists else ''
backend_poll_spec   = get_scm_poll_spec(BACKEND_CONFIG) if backend_exists else ''

# Also accept git URL found in pipeline script
if not backend_git_url and backend_exists:
    if check_pipeline_script_for_git(BACKEND_CONFIG, TARGET_GIT_URL):
        backend_git_url = TARGET_GIT_URL

backend_git_url_correct = (
    TARGET_GIT_URL in backend_git_url or
    'jenkinsci/pipeline-examples' in backend_git_url
)

# ── Frontend job analysis ─────────────────────────────────────
frontend_exists = len(FRONTEND_CONFIG.strip()) > 50
node_choices    = get_choice_param(FRONTEND_CONFIG, 'NODE_VERSION') if frontend_exists else []
frontend_keep   = get_build_discarder_keep(FRONTEND_CONFIG) if frontend_exists else ''

# ── Credential analysis ───────────────────────────────────────
try:
    cred = json.loads(CRED_JSON_STR)
except Exception:
    cred = {}
cred_exists = bool(cred.get('id') or cred.get('displayName'))
cred_type   = cred.get('typeName', cred.get('_class', ''))
cred_is_secret_text = (
    'StringCredentials' in cred_type or
    'SecretText' in cred_type or
    'secret' in cred_type.lower() or
    'string' in cred_type.lower()
)

# ── View analysis ─────────────────────────────────────────────
try:
    view = json.loads(VIEW_JSON_STR)
except Exception:
    view = {}
view_exists = bool(view.get('_class') or view.get('name'))
view_job_names = [j.get('name', '') for j in view.get('jobs', [])]
view_has_backend  = 'alpha-backend-build'  in view_job_names
view_has_frontend = 'alpha-frontend-build' in view_job_names

# ── Assemble result ───────────────────────────────────────────
result = {
    "alpha_backend_build": {
        "exists":            backend_exists,
        "is_pipeline":       backend_is_pipeline,
        "git_url":           backend_git_url,
        "git_url_correct":   backend_git_url_correct,
        "scm_class":         backend_scm_class,
        "scm_branch":        backend_scm_branch,
        "scm_poll_spec":     backend_poll_spec,
        "has_h15_polling":   'H/15' in backend_poll_spec or '/15' in backend_poll_spec,
    },
    "alpha_frontend_build": {
        "exists":            frontend_exists,
        "node_version_choices": node_choices,
        "build_discarder_keep": frontend_keep,
    },
    "npm_registry_token": {
        "exists":            cred_exists,
        "type":              cred_type,
        "is_secret_text":    cred_is_secret_text,
    },
    "view_project_alpha_ci": {
        "exists":            view_exists,
        "jobs_in_view":      view_job_names,
        "has_backend_job":   view_has_backend,
        "has_frontend_job":  view_has_frontend,
    },
    "export_timestamp": "$(date -Iseconds)"
}

with open('/tmp/project_ci_environment_setup_result.json', 'w') as f:
    json.dump(result, f, indent=2)

print("Result:")
for k, v in result.items():
    print(f"  {k}: {v}")
PYEOF

# ── Safe copy to final location ───────────────────────────────
if [ -f /tmp/project_ci_environment_setup_result.json ]; then
    TEMP_JSON=$(mktemp /tmp/pces_final.XXXXXX.json)
    cp /tmp/project_ci_environment_setup_result.json "$TEMP_JSON"
    rm -f /tmp/project_ci_environment_setup_result.json 2>/dev/null || \
        sudo rm -f /tmp/project_ci_environment_setup_result.json 2>/dev/null || true
    cp "$TEMP_JSON" /tmp/project_ci_environment_setup_result.json 2>/dev/null || \
        sudo cp "$TEMP_JSON" /tmp/project_ci_environment_setup_result.json
    chmod 666 /tmp/project_ci_environment_setup_result.json 2>/dev/null || \
        sudo chmod 666 /tmp/project_ci_environment_setup_result.json 2>/dev/null || true
    rm -f "$TEMP_JSON"
fi

echo ""
echo "Result JSON:"
cat /tmp/project_ci_environment_setup_result.json
echo ""
echo "=== Export Complete ==="
