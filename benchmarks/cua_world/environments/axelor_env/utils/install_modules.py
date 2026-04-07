#!/usr/bin/env python3
"""Install Axelor modules via REST API.
Installs Base, CRM, Sale, and Purchase modules sequentially with pauses.
"""
import urllib.request, urllib.parse, json, http.cookiejar, time, sys

AXELOR_URL = "http://localhost"
MODULES = ["base", "crm", "sale", "purchase"]

def log(msg):
    """Print to both stdout (captured by hook log) and stderr (visible in console)."""
    print(msg, flush=True)
    print(msg, file=sys.stderr, flush=True)

def login():
    cj = http.cookiejar.CookieJar()
    opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cj))
    opener.open(f"{AXELOR_URL}/login.jsp")
    data = urllib.parse.urlencode({"username": "admin", "password": "admin"}).encode()
    opener.open(urllib.request.Request(f"{AXELOR_URL}/login.jsp", data=data, method="POST"))
    return opener

def get_apps(opener):
    search_data = json.dumps({"offset": 0, "limit": 40, "fields": ["name", "code", "active", "id", "version"]}).encode()
    req = urllib.request.Request(f"{AXELOR_URL}/ws/rest/com.axelor.apps.base.db.App/search",
        data=search_data, headers={"Content-Type": "application/json"}, method="POST")
    resp = opener.open(req)
    apps = json.loads(resp.read())
    return {app["code"]: app for app in apps.get("data", [])}

def install_app(opener, app_info):
    action_data = json.dumps({
        "action": "action-app-method-install-app",
        "data": {"context": {
            "_model": "com.axelor.apps.base.db.App",
            "id": app_info["id"],
            "version": app_info.get("version", 0),
            "code": app_info["code"],
            "importDemoData": True,
            "languageSelect": "en"
        }}
    }).encode()
    req = urllib.request.Request(f"{AXELOR_URL}/ws/action/",
        data=action_data, headers={"Content-Type": "application/json"}, method="POST")
    resp = opener.open(req)
    return json.loads(resp.read())

def main():
    opener = login()
    log("Logged in to Axelor API")

    app_map = get_apps(opener)
    log(f"Found {len(app_map)} apps")

    for code in MODULES:
        if code not in app_map:
            log(f"  {code}: NOT FOUND")
            continue

        app_info = app_map[code]
        if app_info.get("active"):
            log(f"  {code}: already active, skipping")
            continue

        log(f"  Installing {code} (id={app_info['id']})...")
        try:
            result = install_app(opener, app_info)
            log(f"    Status: {result.get('status', 'unknown')}")
        except Exception as e:
            log(f"    Error: {e}")

        log(f"    Waiting 20s for install to complete...")
        time.sleep(20)

        try:
            opener = login()
        except:
            time.sleep(10)
            opener = login()

    # Final verification
    app_map = get_apps(opener)
    active = [code for code, info in app_map.items() if info.get("active")]
    log(f"Active modules: {', '.join(sorted(active)) if active else 'none'}")

    # Verify all required modules are active
    missing = [m for m in MODULES if m not in active]
    if missing:
        log(f"WARNING: These modules failed to install: {', '.join(missing)}")
    else:
        log(f"All {len(MODULES)} required modules installed successfully")

if __name__ == "__main__":
    main()
