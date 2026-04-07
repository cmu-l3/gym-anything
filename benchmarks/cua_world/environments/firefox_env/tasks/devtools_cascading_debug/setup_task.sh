#!/bin/bash
# setup_task.sh - Pre-task hook for devtools_cascading_debug
#
# Creates a local web application (employee directory) with 5 cascading bugs,
# starts an HTTP server, and launches Firefox pointing to it.
#
# Cascading bug chain:
#   Bug 1: script src typo (app.jss) -> loading spinner forever
#   Bug 2: wrong fetch URL (employee.json vs employees.json) -> error message
#   Bug 3: wrong data property (data.employees vs data.staff) -> TypeError
#   Bug 4: CSS class mismatch (emp-row vs employee-row) -> unstyled table
#   Bug 5: wrong event handler name (filterTable vs searchTable) -> search broken

set -e

echo "=== Setting up devtools_cascading_debug task ==="

# ── 1. Kill any running Firefox instances ──
pkill -u ga -f firefox 2>/dev/null || true
sleep 2
pkill -9 -u ga -f firefox 2>/dev/null || true
sleep 1

# ── 2. Kill any existing HTTP server on port 8080 ──
fuser -k 8080/tcp 2>/dev/null || true
sleep 1

# ── 3. Clean up previous outputs (BEFORE recording timestamp) ──
rm -f /home/ga/Documents/incident_report.json 2>/dev/null || true
rm -rf /home/ga/webapp 2>/dev/null || true

# ── 4. Record task start timestamp ──
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# ── 5. Find Firefox profile ──
# Check for profile directory (not places.sqlite, which may not exist until Firefox runs)
PROFILE_DIR=""
for candidate in \
    "/home/ga/snap/firefox/common/.mozilla/firefox/default.profile" \
    "/home/ga/.mozilla/firefox/default.profile"; do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        break
    fi
done
if [ -z "$PROFILE_DIR" ]; then
    # Fallback: search for places.sqlite (may exist from previous runs)
    PROFILE_DIR=$(find /home/ga -name "places.sqlite" 2>/dev/null | head -1 | xargs -I{} dirname {} 2>/dev/null || echo "")
fi
if [ -n "$PROFILE_DIR" ]; then
    echo "$PROFILE_DIR" > /tmp/firefox_profile_path
    echo "Found Firefox profile: $PROFILE_DIR"
else
    echo "WARNING: Could not find Firefox profile."
fi

# ── 6. Create webapp directory structure ──
mkdir -p /home/ga/webapp/data
mkdir -p /home/ga/Documents

# ── 7. Write index.html (with Bug 1: app.jss, Bug 5: filterTable) ──
cat > /home/ga/webapp/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Acme Corp Employee Directory</title>
    <link rel="stylesheet" href="style.css">
</head>
<body>
    <header>
        <h1>Acme Corp Employee Directory</h1>
        <p>Internal HR Portal &mdash; Confidential</p>
    </header>

    <div class="search-container">
        <form onsubmit="return filterTable()">
            <input type="text" id="searchInput" placeholder="Search employees by name or department...">
            <button type="submit">Search</button>
            <button type="button" onclick="resetSearch()">Reset</button>
        </form>
    </div>

    <div id="loading" class="loading-spinner">
        <div class="spinner"></div>
        <p>Loading employee data...</p>
    </div>

    <div id="employee-table-container" style="display: none;">
        <table class="employee-table" id="employeeTable">
            <thead>
                <tr>
                    <th>ID</th>
                    <th>Name</th>
                    <th>Department</th>
                    <th>Email</th>
                    <th>Phone</th>
                    <th>Start Date</th>
                </tr>
            </thead>
            <tbody id="tableBody">
            </tbody>
        </table>
        <div id="statusBar" class="status-bar">
            <span id="employeeCount"></span>
        </div>
    </div>

    <footer>
        <p>&copy; 2024 Acme Corp. All rights reserved. For internal use only.</p>
    </footer>

    <script src="app.jss"></script>
</body>
</html>
HTMLEOF

# ── 8. Write app.js (with Bug 2: employee.json, Bug 3: data.employees, Bug 4: emp-row) ──
cat > /home/ga/webapp/app.js << 'JSEOF'
// Acme Corp Employee Directory - Main Application Logic
(function() {
    'use strict';

    var API_URL = 'data/employee.json';

    document.addEventListener('DOMContentLoaded', function() {
        loadEmployees();
    });

    function loadEmployees() {
        fetch(API_URL)
            .then(function(response) {
                if (!response.ok) {
                    throw new Error('HTTP ' + response.status + ': ' + response.statusText);
                }
                return response.json();
            })
            .then(function(data) {
                var employees = data.employees;
                if (!employees || !Array.isArray(employees)) {
                    throw new TypeError(
                        'Expected an array of employees but got: ' + typeof employees
                    );
                }
                renderTable(employees);
                window._employeeData = employees;
            })
            .catch(function(error) {
                document.getElementById('loading').innerHTML =
                    '<p class="error">Error loading data: ' + error.message + '</p>';
                console.error('Failed to load employee data:', error);
            });
    }

    function renderTable(employees) {
        var tbody = document.getElementById('tableBody');
        tbody.innerHTML = '';

        employees.forEach(function(emp) {
            var row = document.createElement('tr');
            row.className = 'emp-row';
            row.innerHTML =
                '<td>' + emp.id + '</td>' +
                '<td>' + emp.name + '</td>' +
                '<td>' + emp.department + '</td>' +
                '<td>' + emp.email + '</td>' +
                '<td>' + emp.phone + '</td>' +
                '<td>' + emp.start_date + '</td>';
            tbody.appendChild(row);
        });

        document.getElementById('loading').style.display = 'none';
        document.getElementById('employee-table-container').style.display = 'block';
        document.getElementById('employeeCount').textContent =
            'Showing ' + employees.length + ' of ' + employees.length + ' employees';
    }

    // Search/filter functionality
    window.searchTable = function() {
        var query = document.getElementById('searchInput').value.toLowerCase().trim();
        if (!window._employeeData) return false;

        var filtered = window._employeeData.filter(function(emp) {
            return emp.name.toLowerCase().indexOf(query) !== -1 ||
                   emp.department.toLowerCase().indexOf(query) !== -1 ||
                   emp.email.toLowerCase().indexOf(query) !== -1;
        });

        renderTable(filtered);
        document.getElementById('employeeCount').textContent =
            'Showing ' + filtered.length + ' of ' + window._employeeData.length + ' employees';
        return false;
    };

    window.resetSearch = function() {
        document.getElementById('searchInput').value = '';
        if (window._employeeData) {
            renderTable(window._employeeData);
        }
    };

})();
JSEOF

# ── 9. Write style.css (correct — no bugs in CSS) ──
cat > /home/ga/webapp/style.css << 'CSSEOF'
/* Acme Corp Employee Directory Styles */
* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    background-color: #f5f5f5;
    color: #333;
    line-height: 1.6;
}

header {
    background-color: #1a365d;
    color: white;
    padding: 20px 40px;
    box-shadow: 0 2px 4px rgba(0,0,0,0.1);
}

header h1 {
    font-size: 24px;
    font-weight: 600;
}

header p {
    font-size: 14px;
    opacity: 0.8;
    margin-top: 4px;
}

.search-container {
    padding: 20px 40px;
    background: white;
    border-bottom: 1px solid #e2e8f0;
}

.search-container form {
    display: flex;
    gap: 10px;
    align-items: center;
}

.search-container input[type="text"] {
    flex: 1;
    padding: 10px 16px;
    border: 1px solid #cbd5e0;
    border-radius: 6px;
    font-size: 14px;
}

.search-container button {
    padding: 10px 20px;
    border: none;
    border-radius: 6px;
    font-size: 14px;
    cursor: pointer;
}

.search-container button[type="submit"] {
    background-color: #2b6cb0;
    color: white;
}

.search-container button[type="button"] {
    background-color: #e2e8f0;
    color: #4a5568;
}

.loading-spinner {
    text-align: center;
    padding: 80px 20px;
    color: #718096;
}

.spinner {
    width: 40px;
    height: 40px;
    border: 4px solid #e2e8f0;
    border-top: 4px solid #2b6cb0;
    border-radius: 50%;
    animation: spin 1s linear infinite;
    margin: 0 auto 16px;
}

@keyframes spin {
    to { transform: rotate(360deg); }
}

.error {
    color: #c53030;
    font-weight: 600;
    padding: 20px;
}

#employee-table-container {
    padding: 20px 40px;
}

.employee-table {
    width: 100%;
    border-collapse: collapse;
    background: white;
    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    border-radius: 8px;
    overflow: hidden;
}

.employee-table thead th {
    background-color: #2d3748;
    color: white;
    padding: 12px 16px;
    text-align: left;
    font-size: 13px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
}

.employee-row {
    border-bottom: 1px solid #e2e8f0;
}

.employee-row:hover {
    background-color: #f7fafc;
}

.employee-row td {
    padding: 12px 16px;
    font-size: 14px;
}

.employee-row td:first-child {
    font-weight: 600;
    color: #2b6cb0;
}

.status-bar {
    padding: 12px 16px;
    background: white;
    border-top: 1px solid #e2e8f0;
    font-size: 13px;
    color: #718096;
    box-shadow: 0 1px 3px rgba(0,0,0,0.1);
    border-radius: 0 0 8px 8px;
}

footer {
    text-align: center;
    padding: 20px;
    color: #a0aec0;
    font-size: 12px;
    margin-top: 40px;
}
CSSEOF

# ── 10. Write data/employees.json (correct data, keyed under "staff") ──
cat > /home/ga/webapp/data/employees.json << 'DATAEOF'
{
    "staff": [
        {
            "id": 1001,
            "name": "Sarah Chen",
            "department": "Engineering",
            "email": "s.chen@acmecorp.com",
            "phone": "(555) 234-5678",
            "start_date": "2019-03-15"
        },
        {
            "id": 1002,
            "name": "Marcus Johnson",
            "department": "Marketing",
            "email": "m.johnson@acmecorp.com",
            "phone": "(555) 345-6789",
            "start_date": "2020-07-22"
        },
        {
            "id": 1003,
            "name": "Priya Patel",
            "department": "Engineering",
            "email": "p.patel@acmecorp.com",
            "phone": "(555) 456-7890",
            "start_date": "2021-01-10"
        },
        {
            "id": 1004,
            "name": "James O'Brien",
            "department": "Sales",
            "email": "j.obrien@acmecorp.com",
            "phone": "(555) 567-8901",
            "start_date": "2018-11-03"
        },
        {
            "id": 1005,
            "name": "Yuki Tanaka",
            "department": "Design",
            "email": "y.tanaka@acmecorp.com",
            "phone": "(555) 678-9012",
            "start_date": "2022-04-18"
        },
        {
            "id": 1006,
            "name": "David Kim",
            "department": "Engineering",
            "email": "d.kim@acmecorp.com",
            "phone": "(555) 789-0123",
            "start_date": "2020-09-01"
        },
        {
            "id": 1007,
            "name": "Elena Rodriguez",
            "department": "Human Resources",
            "email": "e.rodriguez@acmecorp.com",
            "phone": "(555) 890-1234",
            "start_date": "2017-06-12"
        },
        {
            "id": 1008,
            "name": "Robert Nguyen",
            "department": "Finance",
            "email": "r.nguyen@acmecorp.com",
            "phone": "(555) 901-2345",
            "start_date": "2021-08-25"
        },
        {
            "id": 1009,
            "name": "Aisha Williams",
            "department": "Sales",
            "email": "a.williams@acmecorp.com",
            "phone": "(555) 012-3456",
            "start_date": "2023-02-14"
        },
        {
            "id": 1010,
            "name": "Thomas Mueller",
            "department": "Engineering",
            "email": "t.mueller@acmecorp.com",
            "phone": "(555) 123-4567",
            "start_date": "2019-10-30"
        }
    ]
}
DATAEOF

# ── 11. Set ownership ──
chown -R ga:ga /home/ga/webapp
chown -R ga:ga /home/ga/Documents

# ── 12. Save original (buggy) copies for diff comparison in export ──
cp /home/ga/webapp/index.html /tmp/original_index.html
cp /home/ga/webapp/app.js /tmp/original_app.js

# ── 13. Start HTTP server ──
echo "Starting HTTP server on port 8080..."
su - ga -c "cd /home/ga/webapp && nohup python3 -m http.server 8080 > /tmp/http_server.log 2>&1 &"

# Wait for server to be ready
for i in {1..15}; do
    if curl -s -o /dev/null -w '%{http_code}' http://localhost:8080 2>/dev/null | grep -q "200"; then
        echo "HTTP server ready after ${i}s"
        break
    fi
    sleep 1
done

# ── 14. Launch Firefox ──
echo "Launching Firefox..."
su - ga -c "DISPLAY=:1 firefox -P default --no-remote http://localhost:8080 > /tmp/firefox_launch.log 2>&1 &"

# ── 15. Wait for Firefox window ──
echo "Waiting for Firefox window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" > /dev/null 2>&1; then
        echo "Firefox window detected after ${i}s"
        break
    fi
    sleep 1
done

# ── 16. Maximize window ──
sleep 2
WINDOW_ID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "firefox|mozilla" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
fi

# ── 17. Take initial screenshot ──
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="
echo "Web application served at http://localhost:8080 (with 5 cascading bugs)"
echo "Agent should use Firefox DevTools to diagnose, fix, and verify each issue."
