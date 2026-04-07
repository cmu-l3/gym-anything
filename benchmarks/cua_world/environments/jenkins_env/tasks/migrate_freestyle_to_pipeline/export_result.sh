#!/bin/bash
# Export script for Migrate Freestyle to Pipeline task.
# Inspects orders-api-pipeline: config XML, pipeline script, parameters,
# stages, credential bindings, triggers, build discarder, and build status.

echo "=== Exporting Migrate Freestyle to Pipeline Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# ── Check if pipeline job exists ──────────────────────────────
PIPELINE_CONFIG=""
PIPELINE_API=""
if job_exists "orders-api-pipeline"; then
    PIPELINE_CONFIG=$(get_job_config "orders-api-pipeline" 2>/dev/null)
    PIPELINE_API=$(jenkins_api "job/orders-api-pipeline/api/json" 2>/dev/null)
    echo "orders-api-pipeline config length: ${#PIPELINE_CONFIG}"
else
    echo "orders-api-pipeline does NOT exist"
fi

# ── Get last build info ──────────────────────────────────────
LAST_BUILD_JSON=$(jenkins_api "job/orders-api-pipeline/lastBuild/api/json" 2>/dev/null || echo '{}')

# ── Parse everything with Python ─────────────────────────────
python3 << PYEOF
import json, re, sys
import xml.etree.ElementTree as ET

def parse_xml_safe(xml_text):
    if not xml_text or len(xml_text.strip()) < 10:
        return None
    try:
        return ET.fromstring(xml_text)
    except Exception:
        return None

PIPELINE_CONFIG = """${PIPELINE_CONFIG}"""
PIPELINE_API = """${PIPELINE_API}"""
LAST_BUILD_JSON = """${LAST_BUILD_JSON}"""
TASK_START = int("${TASK_START}" or "0")

result = {}

# ── Job existence and type ────────────────────────────────────
root = parse_xml_safe(PIPELINE_CONFIG)
job_exists = root is not None
result["job_exists"] = job_exists

if job_exists:
    tag = root.tag.lower()
    result["is_pipeline"] = 'flow-definition' in tag or 'workflow' in tag
else:
    result["is_pipeline"] = False

# ── Extract pipeline script ───────────────────────────────────
pipeline_script = ""
if root is not None:
    for s in root.iter('script'):
        if s.text and len(s.text.strip()) > 10:
            pipeline_script = s.text
            break
result["pipeline_script"] = pipeline_script
result["script_length"] = len(pipeline_script)

# ── Parameters ────────────────────────────────────────────────
params_found = {}
if root is not None:
    for param_def in root.iter():
        tag = param_def.tag
        name_el = param_def.find('name')
        if name_el is None or not name_el.text:
            continue
        pname = name_el.text.strip()

        if 'StringParameterDefinition' in tag:
            default_el = param_def.find('defaultValue')
            params_found[pname] = {
                "type": "string",
                "default": (default_el.text or "").strip() if default_el is not None else ""
            }
        elif 'BooleanParameterDefinition' in tag:
            default_el = param_def.find('defaultValue')
            params_found[pname] = {
                "type": "boolean",
                "default": (default_el.text or "").strip() if default_el is not None else ""
            }
        elif 'ChoiceParameterDefinition' in tag:
            choices = []
            for s_el in param_def.iter('string'):
                if s_el.text:
                    choices.append(s_el.text.strip())
            if not choices:
                choices_el = param_def.find('choices')
                if choices_el is not None and choices_el.text:
                    choices = [c.strip() for c in choices_el.text.strip().splitlines() if c.strip()]
            params_found[pname] = {
                "type": "choice",
                "choices": choices
            }

# Also check pipeline script for parameters block
if not params_found and pipeline_script:
    # Fallback: look for parameter definitions in pipeline script
    for m in re.finditer(r"string\s*\(\s*name:\s*['\"](\w+)['\"]", pipeline_script):
        params_found[m.group(1)] = {"type": "string", "source": "script"}
    for m in re.finditer(r"booleanParam\s*\(\s*name:\s*['\"](\w+)['\"]", pipeline_script):
        params_found[m.group(1)] = {"type": "boolean", "source": "script"}
    for m in re.finditer(r"choice\s*\(\s*name:\s*['\"](\w+)['\"]", pipeline_script):
        params_found[m.group(1)] = {"type": "choice", "source": "script"}

result["parameters"] = params_found

# ── Script content checks ─────────────────────────────────────
script_lower = pipeline_script.lower()
script_text = pipeline_script

result["has_credential_staging_db"] = "staging-db-creds" in script_text
result["has_credential_staging_ssh"] = "staging-ssh-key" in script_text
result["has_db_host"] = "orders-db.staging.internal" in script_text
result["has_db_port"] = "5432" in script_text

# Stage detection
result["has_stage_build"] = bool(re.search(r"stage\s*\(\s*['\"]Build['\"]", script_text))
result["has_stage_test"] = bool(re.search(r"stage\s*\(\s*['\"]Test['\"]", script_text))
result["has_stage_security"] = bool(re.search(r"stage\s*\(\s*['\"]Security\s*Scan['\"]", script_text, re.IGNORECASE))
result["has_stage_deploy"] = bool(re.search(r"stage\s*\(\s*['\"]Deploy['\"]", script_text))

# Shell command fragments
result["shell_has_building"] = "Building Orders API" in script_text
result["shell_has_integration"] = "Integration Tests" in script_text or "Running Integration Tests" in script_text
result["shell_has_owasp"] = "OWASP" in script_text
result["shell_has_deploying"] = "Deploying to Staging" in script_text

# Post-build actions in pipeline
result["has_archive_jar"] = "archiveArtifacts" in script_text and ("target" in script_text or "*.jar" in script_text)
result["has_archive_security"] = "archiveArtifacts" in script_text and "security-reports" in script_text
result["has_junit"] = "junit" in script_lower

# Security node label
result["has_security_node_label"] = "security-node" in script_text

# Cron trigger
has_cron_in_script = bool(re.search(r"cron\s*\(\s*['\"].*H/30", script_text))
has_cron_in_xml = False
if root is not None:
    for timer in root.iter('hudson.triggers.TimerTrigger'):
        spec = timer.find('spec')
        if spec is not None and spec.text and 'H/30' in spec.text:
            has_cron_in_xml = True
    # Also check for pipeline cron triggers in properties
    for t in root.iter():
        if 'TimerTrigger' in t.tag or 'pipelineTriggers' in t.tag:
            text = ET.tostring(t, encoding='unicode')
            if 'H/30' in text:
                has_cron_in_xml = True
result["has_cron_trigger"] = has_cron_in_script or has_cron_in_xml

# Build discarder
has_discarder_in_script = bool(re.search(r"buildDiscarder|logRotator", script_text))
has_discarder_in_xml = False
num_to_keep = ""
artifact_num_to_keep = ""
if root is not None:
    for rotator in root.iter('hudson.tasks.LogRotator'):
        ntk = rotator.find('numToKeep')
        antk = rotator.find('artifactNumToKeep')
        if ntk is not None and ntk.text:
            num_to_keep = ntk.text.strip()
            has_discarder_in_xml = True
        if antk is not None and antk.text:
            artifact_num_to_keep = antk.text.strip()
    for prop in root.iter('jenkins.model.BuildDiscarderProperty'):
        has_discarder_in_xml = True
        for rotator in prop.iter():
            ntk = rotator.find('numToKeep')
            antk = rotator.find('artifactNumToKeep')
            if ntk is not None and ntk.text:
                num_to_keep = ntk.text.strip()
            if antk is not None and antk.text:
                artifact_num_to_keep = antk.text.strip()
# Also check script text for specific numbers
if not num_to_keep and pipeline_script:
    m = re.search(r"numToKeepStr\s*:\s*['\"](\d+)['\"]", pipeline_script)
    if m:
        num_to_keep = m.group(1)
if not artifact_num_to_keep and pipeline_script:
    m = re.search(r"artifactNumToKeepStr\s*:\s*['\"](\d+)['\"]", pipeline_script)
    if m:
        artifact_num_to_keep = m.group(1)

result["has_build_discarder"] = has_discarder_in_script or has_discarder_in_xml
result["num_to_keep"] = num_to_keep
result["artifact_num_to_keep"] = artifact_num_to_keep

# ── Build status ──────────────────────────────────────────────
try:
    build = json.loads(LAST_BUILD_JSON)
except Exception:
    build = {}

build_result = build.get("result", "")
build_number = build.get("number", 0)
build_timestamp = build.get("timestamp", 0) // 1000 if build.get("timestamp") else 0

result["build_triggered"] = build_number > 0 and build_timestamp > TASK_START
result["build_result"] = build_result
result["build_number"] = build_number

result["export_timestamp"] = "$(date -Iseconds)"

# ── Write JSON ────────────────────────────────────────────────
with open('/tmp/_mftp_result_tmp.json', 'w') as f:
    json.dump(result, f, indent=2, default=str)

print("Result:")
for k, v in sorted(result.items()):
    if k != "pipeline_script":
        print(f"  {k}: {v}")
print(f"  pipeline_script length: {len(pipeline_script)}")
PYEOF

# ── Safe copy to final location ───────────────────────────────
if [ -f /tmp/_mftp_result_tmp.json ]; then
    rm -f /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || \
        sudo rm -f /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || true
    cp /tmp/_mftp_result_tmp.json /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || \
        sudo cp /tmp/_mftp_result_tmp.json /tmp/migrate_freestyle_to_pipeline_result.json
    chmod 666 /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || \
        sudo chmod 666 /tmp/migrate_freestyle_to_pipeline_result.json 2>/dev/null || true
    rm -f /tmp/_mftp_result_tmp.json
fi

echo ""
echo "Result JSON:"
cat /tmp/migrate_freestyle_to_pipeline_result.json
echo ""
echo "=== Export Complete ==="
