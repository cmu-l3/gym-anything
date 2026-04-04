#!/bin/bash
# setup_task.sh for juice_shop_threat_model

echo "=== Setting up Juice Shop Threat Model Task ==="

# 1. timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
rm -f /home/ga/Desktop/juice_shop_threat_model.drawio
rm -f /home/ga/Desktop/juice_shop_threat_model.png

# 3. Create Architecture Specification Document
# This contains the "truth" the agent needs to model
cat > /home/ga/Desktop/juice_shop_architecture.md << 'EOF'
# OWASP Juice Shop — Architecture Specification
## For Security Design Review / Threat Modeling

### Overview
OWASP Juice Shop is an e-commerce web application for selling fruit juices.
It is built as a Single Page Application (SPA) with a RESTful API backend.

---

### Component Inventory

#### External Entities
1. **Browser / End User** — Customers and administrators accessing the web UI
2. **Stripe Payment Gateway** — External payment processing API (PCI DSS scope)
3. **SMTP Email Service** — Transactional email delivery (order confirmations, password resets)

#### Application Processes
4. **Angular SPA (Frontend)** — Client-side single-page application
   - Served as static files
   - Communicates with backend via REST API (JSON over HTTPS)

5. **Express.js API Server (Backend)** — Node.js REST API
   - Handles all business logic
   - Routes: /api/Products, /api/Orders, /api/Users
   - Calls external Stripe API
   - Dispatches transactional emails via SMTP

6. **Authentication Module** — JWT-based authentication subsystem
   - Handles login (local + OAuth2)
   - Issues JWT tokens

#### Data Stores
7. **SQLite Database** — Primary relational data store
   - Stores user credentials (bcrypt hashes), orders, products
   - Local file-based storage

8. **File System (Uploads & FTP)** — Local filesystem storage
   - Stores user profile photos and complaint files
   - Legacy FTP interface exists

---

### Trust Boundaries (REQUIRED in Diagram)

**TB1: Internet / DMZ Boundary**
- Separates External Entities (User, Stripe, SMTP) from the Application.

**TB2: Application / Data Boundary**
- Separates the API/Auth processes from the Data Stores (Database, Filesystem).

---

### STRIDE Analysis Requirements
Please identify threats across these categories:
- **S**poofing
- **T**ampering
- **R**epudiation
- **I**nformation Disclosure
- **D**enial of Service
- **E**levation of Privilege
EOF

chown ga:ga /home/ga/Desktop/juice_shop_architecture.md
chmod 644 /home/ga/Desktop/juice_shop_architecture.md

# 4. Launch draw.io
# We launch it empty so the agent has to create the file from scratch
echo "Launching draw.io..."
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio";
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio";
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io" > /dev/null; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

# Maximize
sleep 2
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Dismiss startup dialog (creates blank diagram)
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="