#!/bin/bash
set -e
echo "=== Setting up task: upload_scanned_document@1 ==="

# 1. Create the dummy PDF file (Real Data requirement: Valid PDF structure)
mkdir -p /home/ga/Documents
PDF_FILE="/home/ga/Documents/Consult_Report.pdf"

# Create a minimal valid PDF with "Cardiology Consult" text to be realistic
cat << EOF > "$PDF_FILE"
%PDF-1.4
1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj
2 0 obj << /Type /Pages /Kids [3 0 R] /Count 1 >> endobj
3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Contents 4 0 R >> endobj
4 0 obj << /Length 55 >> stream
BT /F1 24 Tf 100 700 Td (Cardiology Consultation Report - Robert Baker) Tj ET
endstream
endobj
xref
0 5
0000000000 65535 f
0000000010 00000 n
0000000060 00000 n
0000000117 00000 n
0000000206 00000 n
trailer << /Size 5 /Root 1 0 R >>
startxref
311
%%EOF

echo "Created PDF at $PDF_FILE"

# 2. Record start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# 3. Get Patient ID for Robert Baker (verify he exists)
PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE lastname='Baker' AND firstname='Robert' LIMIT 1")

if [ -z "$PID" ]; then
    echo "ERROR: Patient Robert Baker not found! Injecting him now..."
    # Fallback: Create patient if missing (safety net)
    docker exec nosh-db mysql -uroot -prootpassword nosh -e "INSERT INTO demographics (lastname, firstname, DOB, sex) VALUES ('Baker', 'Robert', '1958-05-14', 'Male');"
    PID=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT pid FROM demographics WHERE lastname='Baker' AND firstname='Robert' LIMIT 1")
fi

echo "$PID" > /tmp/target_pid.txt
echo "Target Patient PID: $PID"

# 4. Record initial document count for this patient
# This allows us to detect "do nothing" even if documents already exist
INITIAL_COUNT=$(docker exec nosh-db mysql -uroot -prootpassword nosh -N -e "SELECT COUNT(*) FROM documents WHERE pid=$PID")
echo "$INITIAL_COUNT" > /tmp/initial_doc_count.txt
echo "Initial document count: $INITIAL_COUNT"

# 5. Launch Firefox to Login Page
if ! pgrep -f "firefox" > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox -width 1920 -height 1080 'http://localhost/login' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "firefox"; then
        break
    fi
    sleep 1
done

# Maximize Firefox
DISPLAY=:1 wmctrl -r "Mozilla Firefox" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Mozilla Firefox" 2>/dev/null || true

# 6. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="