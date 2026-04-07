#!/bin/bash
# export_result.sh — promotion_pipeline_setup
echo "=== Exporting promotion_pipeline_setup result ==="

source /workspace/scripts/task_utils.sh

python3 << 'PYEOF'
import json, subprocess, xml.etree.ElementTree as ET

URL  = "http://localhost:8082"
AUTH = ("admin", "password")

def art_get(path):
    try:
        r = subprocess.run(
            ["curl", "-s", "-u", f"{AUTH[0]}:{AUTH[1]}",
             f"{URL}/artifactory/api{path}"],
            capture_output=True, text=True, timeout=15
        )
        return json.loads(r.stdout)
    except Exception:
        return None

def http_code(path, user=None, passwd=None):
    u = user or AUTH[0]
    p = passwd or AUTH[1]
    try:
        r = subprocess.run(
            ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
             "-u", f"{u}:{p}",
             f"{URL}/artifactory/api{path}"],
            capture_output=True, text=True, timeout=10
        )
        return r.stdout.strip()
    except Exception:
        return "000"

def get_perm(name):
    perm = art_get(f"/security/permissions/{name}") or {}
    group_privs = {}
    if isinstance(perm.get("principals"), dict):
        group_privs = perm["principals"].get("groups", {})
    return {
        "found": bool(perm.get("name") == name),
        "repositories": perm.get("repositories", []),
        "group_privs": group_privs,
    }

def get_sys_config():
    """Fetch system configuration XML and parse mail + security sections."""
    try:
        r = subprocess.run(
            ["curl", "-s", "-u", f"{AUTH[0]}:{AUTH[1]}",
             f"{URL}/artifactory/api/system/configuration"],
            capture_output=True, text=True, timeout=15
        )
        root = ET.fromstring(r.stdout)
    except Exception:
        return {"mail": {}, "anon_enabled": None}

    def find_text(parent, tag):
        for el in parent.iter():
            if el.tag.endswith(tag):
                return el.text
        return None

    # Parse mailServer
    mail = {}
    for child in root.iter():
        if child.tag.endswith("mailServer"):
            mail["found"] = True
            mail["enabled"] = (find_text(child, "enabled") or "").lower() == "true"
            mail["host"] = find_text(child, "host")
            port_txt = find_text(child, "port")
            mail["port"] = int(port_txt) if port_txt and port_txt.isdigit() else None
            mail["tls"] = (find_text(child, "tls") or "").lower() == "true"
            mail["from"] = find_text(child, "from")
            mail["subjectPrefix"] = find_text(child, "subjectPrefix")
            break

    # Parse anonymous access
    anon = None
    for child in root.iter():
        if child.tag.endswith("anonAccessEnabled"):
            anon = (child.text or "").lower() == "true"
            break

    return {"mail": mail, "anon_enabled": anon}


result = {}

# ── Repositories ──────────────────────────────────────────────────────────────
repos = art_get("/repositories") or []
repo_map = {r.get("key", "").lower(): r for r in repos if isinstance(r, dict)}

for key in ("medsecure-dev", "medsecure-staging", "medsecure-prod"):
    r = repo_map.get(key, {})
    slug = key.replace("-", "_")
    result[slug] = {
        "found": bool(r),
        "type": r.get("type", ""),
        "packageType": r.get("packageType", ""),
    }

# Remote repo with URL
r = repo_map.get("maven-central-proxy", {})
detail = art_get("/repositories/maven-central-proxy") or {}
result["maven_central_proxy"] = {
    "found": bool(r),
    "type": r.get("type", ""),
    "packageType": r.get("packageType", ""),
    "url": detail.get("url", "") or detail.get("remoteUrl", ""),
}

# Virtual repo with aggregation details
r = repo_map.get("medsecure-maven-all", {})
detail2 = art_get("/repositories/medsecure-maven-all") or {}
result["medsecure_maven_all"] = {
    "found": bool(r),
    "type": r.get("type", ""),
    "packageType": r.get("packageType", ""),
    "repositories": detail2.get("repositories", []),
    "defaultDeploymentRepo": detail2.get("defaultDeploymentRepo", ""),
}

# ── Groups ────────────────────────────────────────────────────────────────────
for grp in ("platform-engineers", "qa-team"):
    slug = grp.replace("-", "_")
    code = http_code(f"/security/groups/{grp}")
    if code == "200":
        result[f"{slug}_group"] = {"found": True}
    else:
        groups = art_get("/security/groups") or []
        names = [(g.get("name", "") if isinstance(g, dict) else str(g)).lower()
                 for g in groups]
        result[f"{slug}_group"] = {"found": grp in names}

# ── User (auth-based check for OSS) ──────────────────────────────────────────
code = http_code("/system/ping", user="eng-sarah", passwd="SarahEng2024!")
result["eng_sarah_user"] = {"auth_works": code == "200"}

# ── Permissions ───────────────────────────────────────────────────────────────
result["deploy_perms"] = get_perm("deploy-perms")
result["qa_perms"] = get_perm("qa-perms")

# ── Artifacts in pipeline repos ───────────────────────────────────────────────
ARTIFACT_PATH = "org/apache/commons/commons-io/2.15.1/commons-io-2.15.1.jar"
for repo in ("medsecure-dev", "medsecure-staging", "medsecure-prod"):
    slug = repo.replace("-", "_")
    code = http_code(f"/storage/{repo}/{ARTIFACT_PATH}")
    result[f"artifact_in_{slug}"] = {"found": code == "200"}

# ── System configuration (SMTP + anonymous access) ───────────────────────────
sys_cfg = get_sys_config()
result["smtp_config"] = sys_cfg.get("mail", {})

# Anonymous access: use behavioral check (unauthenticated repo list)
try:
    r = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}",
         f"{URL}/artifactory/api/repositories"],
        capture_output=True, text=True, timeout=10
    )
    anon_http = r.stdout.strip()
    result["anon_access_enabled"] = (anon_http == "200")
except Exception:
    result["anon_access_enabled"] = sys_cfg.get("anon_enabled")

# ── Write ─────────────────────────────────────────────────────────────────────
with open("/tmp/promotion_pipeline_setup_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result JSON written to /tmp/promotion_pipeline_setup_result.json")
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export Complete ==="
