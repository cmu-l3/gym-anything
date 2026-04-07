#!/bin/bash
echo "=== Exporting results ==="
su - ga -c "curl -s http://localhost:9222/json" > /tmp/active_tabs.json 2>/dev/null || true
su - ga -c 'python3 -c "
import json, requests, websocket
try:
    tabs = requests.get(\"http://localhost:9222/json\").json()
    if tabs:
        ws_url = tabs[0].get(\"webSocketDebuggerUrl\", \"\")
        if ws_url:
            ws = websocket.create_connection(ws_url)
            ws.send(json.dumps({\"id\": 1, \"method\": \"Runtime.evaluate\", \"params\": {\"expression\": \"document.documentElement.outerHTML\"}}))
            result = json.loads(ws.recv())
            html = result.get(\"result\", {}).get(\"result\", {}).get(\"value\", \"\")
            ws.close()
            with open(\"/tmp/page_content.json\", \"w\") as f:
                json.dump({\"url\": tabs[0][\"url\"], \"title\": tabs[0].get(\"title\",\"\"), \"html\": html}, f)
except: pass
" 2>/dev/null' || true
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f chrome 2>/dev/null || true
echo "=== Export complete ==="
