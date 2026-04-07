#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Web Accessibility Remediations Task ==="

WORKSPACE_DIR="/home/ga/workspace/agency_dashboard"
sudo -u ga mkdir -p "$WORKSPACE_DIR/css"
sudo -u ga mkdir -p "$WORKSPACE_DIR/js"
sudo -u ga mkdir -p "$WORKSPACE_DIR/assets"

# 1. Create index.html (Violations: missing lang, missing alt, no skip-nav)
cat > "$WORKSPACE_DIR/index.html" << 'EOF'
<!DOCTYPE html>
<html>
<!-- AGENCY_DASHBOARD_V2 -->
<head>
    <meta charset="UTF-8">
    <title>Agency Analytics Dashboard</title>
    <link rel="stylesheet" href="css/styles.css">
</head>
<body>
    <header class="top-nav">
        <img src="assets/logo.png" class="logo">
        <h1>Internal Analytics Dashboard</h1>
    </header>
    <div class="layout">
        <nav class="sidebar">
            <ul>
                <li><a href="index.html" class="sidebar-link active">Dashboard</a></li>
                <li><a href="reports.html" class="sidebar-link">Reports</a></li>
                <li><a href="login.html" class="sidebar-link">Logout</a></li>
            </ul>
        </nav>
        <main id="main-content" class="content">
            <h2>Q3 Performance Overview</h2>
            <div class="stats-grid">
                <div class="stat-card">
                    <span class="stat-label">Total Applications</span>
                    <span class="stat-value">12,450</span>
                    <span class="muted-text">+5% from last month</span>
                </div>
                <div class="stat-card">
                    <span class="stat-label">Approval Rate</span>
                    <span class="stat-value">84.2%</span>
                    <span class="muted-text">-1.2% from last month</span>
                </div>
            </div>
            <div class="chart-container">
                <img src="assets/q3_chart.png" class="data-chart">
            </div>
        </main>
    </div>
    <script src="js/dashboard.js"></script>
</body>
</html>
EOF

# 2. Create login.html (Violations: missing lang, form inputs missing labels, no skip-nav)
cat > "$WORKSPACE_DIR/login.html" << 'EOF'
<!DOCTYPE html>
<html>
<!-- AGENCY_DASHBOARD_V2 -->
<head>
    <meta charset="UTF-8">
    <title>Login - Agency Dashboard</title>
    <link rel="stylesheet" href="css/styles.css">
</head>
<body>
    <div class="login-container">
        <div class="login-box">
            <img src="assets/logo.png" class="logo">
            <h2>Secure Gateway Login</h2>
            <form action="index.html" method="GET">
                <div class="form-group">
                    <input type="text" id="username" placeholder="Enter Username">
                </div>
                <div class="form-group">
                    <input type="password" id="password" placeholder="Enter Password">
                </div>
                <button type="submit" class="btn-primary">Sign In</button>
            </form>
            <p class="muted-text">Authorized personnel only.</p>
        </div>
    </div>
</body>
</html>
EOF

# 3. Create reports.html (Violations: missing lang, no skip-nav, <div> button, missing table <th> scopes)
cat > "$WORKSPACE_DIR/reports.html" << 'EOF'
<!DOCTYPE html>
<html>
<!-- AGENCY_DASHBOARD_V2 -->
<head>
    <meta charset="UTF-8">
    <title>Reports - Agency Dashboard</title>
    <link rel="stylesheet" href="css/styles.css">
</head>
<body>
    <header class="top-nav">
        <img src="assets/logo.png" class="logo">
        <h1>Internal Analytics Dashboard</h1>
    </header>
    <div class="layout">
        <nav class="sidebar">
            <ul>
                <li><a href="index.html" class="sidebar-link">Dashboard</a></li>
                <li><a href="reports.html" class="sidebar-link active">Reports</a></li>
                <li><a href="login.html" class="sidebar-link">Logout</a></li>
            </ul>
        </nav>
        <main id="main-content" class="content">
            <div class="content-header">
                <h2>Regional Output Data</h2>
                <div id="export-btn" class="action-btn">Export to CSV</div>
            </div>
            <table class="data-table">
                <thead>
                    <tr>
                        <th>Region ID</th>
                        <th>Region Name</th>
                        <th>Applications</th>
                        <th>Approvals</th>
                        <th>Processing Time (Days)</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>R1</td>
                        <td>Northeast</td>
                        <td>4,200</td>
                        <td>3,850</td>
                        <td>12.4</td>
                    </tr>
                    <tr>
                        <td>R2</td>
                        <td>Southeast</td>
                        <td>3,100</td>
                        <td>2,400</td>
                        <td>15.1</td>
                    </tr>
                    <tr>
                        <td>R3</td>
                        <td>Midwest</td>
                        <td>2,800</td>
                        <td>2,600</td>
                        <td>10.8</td>
                    </tr>
                    <tr>
                        <td>R4</td>
                        <td>West</td>
                        <td>2,350</td>
                        <td>1,900</td>
                        <td>18.2</td>
                    </tr>
                </tbody>
            </table>
        </main>
    </div>
    <script src="js/dashboard.js"></script>
</body>
</html>
EOF

# 4. Create css/styles.css (Violations: color contrast below 4.5:1)
cat > "$WORKSPACE_DIR/css/styles.css" << 'EOF'
/* Main Stylesheet for Agency Dashboard */
body {
    font-family: Arial, sans-serif;
    margin: 0;
    padding: 0;
    background-color: #f4f6f9;
    color: #333333;
}

/* Typography and generic elements */
h1, h2, h3 { margin-top: 0; }
.top-nav { background: #003366; color: white; padding: 15px 20px; display: flex; align-items: center; }
.top-nav .logo { height: 30px; margin-right: 15px; }

/* Layout */
.layout { display: flex; min-height: calc(100vh - 60px); }
.sidebar { width: 220px; background: #ffffff; border-right: 1px solid #ddd; padding: 20px 0; }
.sidebar ul { list-style: none; padding: 0; margin: 0; }
.sidebar li { padding: 10px 20px; }

/* VIOLATION: .sidebar-link contrast ratio is ~3.5:1 (against #ffffff) */
.sidebar-link { color: #888888; text-decoration: none; display: block; }
.sidebar-link:hover, .sidebar-link.active { color: #003366; font-weight: bold; }

.content { flex: 1; padding: 30px; }

/* Dashboard components */
.stats-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; margin-bottom: 30px; }
.stat-card { background: white; padding: 20px; border-radius: 4px; border: 1px solid #e0e0e0; }

/* VIOLATION: .stat-label contrast ratio is ~2.3:1 (against #ffffff) */
.stat-label { display: block; font-size: 14px; text-transform: uppercase; color: #aaaaaa; margin-bottom: 5px; }
.stat-value { display: block; font-size: 28px; font-weight: bold; margin-bottom: 5px; }

/* VIOLATION: .muted-text contrast ratio is ~2.8:1 (against #ffffff) */
.muted-text { font-size: 13px; color: #999999; }

/* Tables */
.content-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 20px; }
.data-table { width: 100%; border-collapse: collapse; background: white; }
.data-table th, .data-table td { padding: 12px 15px; text-align: left; border-bottom: 1px solid #ddd; }
.data-table th { background: #f0f0f0; font-weight: bold; }

/* Buttons & Interactive */
.action-btn { background: #005a9c; color: white; padding: 8px 15px; border-radius: 4px; cursor: pointer; display: inline-block; }
.action-btn:hover { background: #004080; }

/* Login */
.login-container { display: flex; justify-content: center; align-items: center; height: 100vh; }
.login-box { background: white; padding: 40px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); text-align: center; width: 300px; }
.form-group { margin-bottom: 15px; text-align: left; }
.form-group input { width: 100%; padding: 10px; border: 1px solid #ccc; border-radius: 4px; box-sizing: border-box; }
.btn-primary { background: #005a9c; color: white; border: none; padding: 10px; width: 100%; border-radius: 4px; cursor: pointer; font-size: 16px; margin-bottom: 15px; }
EOF

# 5. Create js/dashboard.js
cat > "$WORKSPACE_DIR/js/dashboard.js" << 'EOF'
document.addEventListener("DOMContentLoaded", function() {
    console.log("Dashboard loaded.");

    // Handle export functionality (attached to a non-semantic div in reports.html)
    const exportBtn = document.getElementById("export-btn");
    if (exportBtn) {
        exportBtn.addEventListener("click", function() {
            console.log("Exporting data to CSV...");
            alert("Data exported successfully.");
        });
    }
});
EOF

# 6. Create AUDIT_REPORT.md
cat > "$WORKSPACE_DIR/AUDIT_REPORT.md" << 'EOF'
# Section 508 Accessibility Audit Findings
**Target**: Internal Analytics Dashboard
**Status**: FAILED (7 Violations)

The following WCAG 2.1 Level AA violations must be remediated immediately.

## 1. Missing Document Language (WCAG 3.1.1)
The `<html>` element is missing the `lang` attribute in all three HTML files (`index.html`, `login.html`, `reports.html`).
**Fix:** Add `lang="en"` to the `<html>` tags.

## 2. Missing Image Alt Text (WCAG 1.1.1)
Images in `index.html` lack descriptive text.
**Fix:** Add a descriptive `alt` attribute to all `<img>` elements in `index.html`. Do not leave them empty (`alt=""`).

## 3. Unlabeled Form Inputs (WCAG 1.3.1 / 3.3.2)
The authentication inputs in `login.html` lack programmatic labels. Placeholder text alone is insufficient.
**Fix:** Add explicit `<label>` elements with a `for` attribute that matches the input's `id`, or add an `aria-label` attribute directly to the `<input>` elements.

## 4. Insufficient Color Contrast (WCAG 1.4.3)
Several text classes in `css/styles.css` fall below the 4.5:1 minimum contrast ratio against their white (`#ffffff`) background.
**Fix:** Darken the color hex codes for `.sidebar-link`, `.stat-label`, and `.muted-text` to meet or exceed a 4.5:1 contrast ratio.

## 5. Non-Semantic Interactive Elements (WCAG 2.1.1)
The "Export to CSV" button in `reports.html` is implemented using a generic `<div>` tag (`<div id="export-btn">`). Keyboard users cannot focus or activate it.
**Fix:** Change the element to a standard `<button>` tag, OR add `role="button"` and `tabindex="0"` to the div. (Make sure CSS/JS still works).

## 6. Missing Skip Navigation Link (WCAG 2.4.1)
Keyboard users have no way to bypass the navigation blocks.
**Fix:** Add a skip-nav link (`<a href="#main-content">Skip to main content</a>`) as one of the first focusable elements inside the `<body>` of all three HTML files. Ensure the main content area has `id="main-content"`.

## 7. Missing Table Header Scopes (WCAG 1.3.1)
The data table in `reports.html` uses `<th>` elements, but their direction is not programmatically defined.
**Fix:** Add `scope="col"` to the column headers in the `<thead>`, and change the first cell of each row in `<tbody>` to a `<th>` with `scope="row"`.
EOF

# Ensure proper permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Record task start time
date +%s > /tmp/task_start_time

# Start VS Code opened to the workspace and the audit report
if ! pgrep -f "code.*agency_dashboard" > /dev/null; then
    echo "Starting VS Code..."
    su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR $WORKSPACE_DIR/AUDIT_REPORT.md &"
    sleep 8
fi

# Focus and maximize VS Code
WID=$(DISPLAY=:1 wmctrl -l | grep -i "Visual Studio Code" | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="