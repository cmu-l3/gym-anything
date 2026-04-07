#!/bin/bash
echo "=== Setting up Firefox IndexedDB Data Recovery Task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Create Web Application Directory
mkdir -p /tmp/webapp
cd /tmp/webapp

# 2. Generate Real-looking MAUDE Database Records (150 records)
cat > /tmp/webapp/generate_data.py << 'PYEOF'
import json
import random

records = []
for i in range(1, 151):
    if i == 73:
        # The hidden target record
        records.append({
            "report_number": "MDR-3042119",
            "device_name": "CARDIAC PACEMAKER",
            "event_type": "Malfunction",
            "event_narrative": "It was reported that during a routine follow-up, the pacemaker exhibited premature battery depletion. The device was replaced without patient complication. The explanted device was returned to the manufacturer for analysis.",
            "manufacturer": "Medtronic",
            "implant_date": "2018-04-12"
        })
    else:
        # Dummy realistic records
        records.append({
            "report_number": f"MDR-{random.randint(1000000, 9999999)}",
            "device_name": random.choice(["INFUSION PUMP", "SURGICAL MESH", "DEFIBRILLATOR", "VENTILATOR", "CATHETER", "STENT", "HIP IMPLANT"]),
            "event_type": random.choice(["Malfunction", "Injury", "Death", "Other"]),
            "event_narrative": "Routine report. No adverse patient effects reported at this time. Device continued to function within acceptable parameters.",
            "manufacturer": random.choice(["Hospira", "Ethicon", "Boston Scientific", "Philips", "Stryker", "Zimmer Biomet", "Abbott"]),
            "implant_date": f"20{random.randint(10, 23)}-0{random.randint(1,9)}-1{random.randint(0,9)}"
        })
        
with open('/tmp/webapp/data.json', 'w') as f:
    json.dump(records, f)
PYEOF

python3 /tmp/webapp/generate_data.py

# 3. Create the HTML Web App UI
cat > /tmp/webapp/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>MedWatch Offline EDC</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background-color: #f4f7f6; }
        .container { background: white; padding: 30px; border-radius: 8px; box-shadow: 0 4px 8px rgba(0,0,0,0.1); max-width: 800px; margin: auto; }
        h1 { color: #2c3e50; }
        .status { padding: 10px; background: #e8f8f5; border-left: 5px solid #1abc9c; margin-bottom: 20px; }
        .error { padding: 10px; background: #fdedec; border-left: 5px solid #e74c3c; margin-top: 20px; color: #c0392b; }
        input[type="text"] { padding: 10px; width: 60%; border: 1px solid #ccc; border-radius: 4px; }
        button { padding: 10px 20px; background-color: #bdc3c7; color: white; border: none; border-radius: 4px; cursor: not-allowed; }
    </style>
</head>
<body>
    <div class="container">
        <h1>MedWatch Offline EDC</h1>
        <div class="status" id="status">Initializing local IndexedDB storage...</div>
        
        <div>
            <input type="text" id="search" placeholder="Enter Report Number (e.g., MDR-3042119)" disabled>
            <button id="searchBtn" disabled>Search Records</button>
        </div>
        
        <div class="error" id="results">
            <strong>System Error 500:</strong> Search module failed to load. The UI cannot query the local database. Please contact IT support. 
        </div>
    </div>

    <script>
        const dbName = "MedWatchDB";
        const request = indexedDB.open(dbName, 1);
        
        request.onupgradeneeded = (event) => {
            const db = event.target.result;
            const objectStore = db.createObjectStore("adverse_events", { keyPath: "report_number" });
            
            // Fetch generated data to populate IndexedDB
            fetch('data.json')
                .then(response => response.json())
                .then(records => {
                    objectStore.transaction.oncomplete = (event) => {
                        const customerObjectStore = db.transaction("adverse_events", "readwrite").objectStore("adverse_events");
                        records.forEach((record) => {
                            customerObjectStore.add(record);
                        });
                        document.getElementById("status").innerHTML = "<strong>Local Database Synced:</strong> 150 offline records cached successfully.";
                    };
                })
                .catch(err => console.error("Data fetch failed:", err));
        };
        
        request.onsuccess = (event) => {
            console.log("Database initialized successfully.");
        };
    </script>
</body>
</html>
EOF

# 4. Start Python HTTP server in background
python3 -m http.server 8080 > /tmp/webapp_server.log 2>&1 &
SERVER_PID=$!
echo "Started web server with PID $SERVER_PID"

# 5. Clear old files if any
rm -f /home/ga/Documents/MDR-3042119_report.json 2>/dev/null

# 6. Ensure Firefox is running
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox http://localhost:8080 &"
    sleep 5
fi

# 7. Wait for window to appear and maximize it
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "MedWatch Offline EDC\|Mozilla Firefox"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Firefox" 2>/dev/null || true

# Wait additional seconds for the IndexedDB JS seeding to complete
sleep 3

# Take screenshot of initial state (for evidence)
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="