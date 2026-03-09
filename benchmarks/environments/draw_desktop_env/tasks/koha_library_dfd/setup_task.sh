#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up koha_library_dfd task ==="

# 1. Create the System Specification File
cat > /home/ga/Desktop/koha_system_spec.txt << 'EOF'
KOHA INTEGRATED LIBRARY SYSTEM (ILS) - SYSTEM SPECIFICATION
===========================================================

1. SYSTEM OVERVIEW
------------------
Koha is an open-source enterprise Integrated Library System used to automate library operations. 
The system manages the catalog, patrons, circulation, and acquisitions.

2. EXTERNAL ENTITIES (Sources/Sinks)
------------------------------------
The system interacts with the following external entities:

- PATRON: Members of the library who search the catalog, borrow books, and manage their accounts.
- LIBRARIAN: Staff members who perform administrative tasks, cataloging, and circulation oversight.
- PUBLISHER/VENDOR: External organizations that supply books and serials.
- OCLC/WORLDCAT: External bibliographic database service for importing records and Inter-Library Loan (ILL).
- SIP2 KIOSK: Self-service checkout machines located in the library.

3. CORE MODULES (Processes)
---------------------------
The system is decomposed into the following core processes (Level 1):

P1: CIRCULATION
    - Handles checkouts, returns, and renewals.
    - Updates the Transaction Log and modifies Item status in the Biblio Catalog.
    - Validates borrowing limits against the Patron Database.

P2: CATALOGING
    - Adds and modifies bibliographic records.
    - Imports MARC records from OCLC/WorldCat.
    - Updates the Biblio Catalog.

P3: ACQUISITIONS
    - Manages budgets and orders.
    - Sends Purchase Orders to Publisher/Vendor.
    - Updates the Acquisitions Ledger.
    - Creates preliminary records in Biblio Catalog.

P4: OPAC (Online Public Access Catalog)
    - Provides search interface for Patrons.
    - Reads from Biblio Catalog.
    - Allows Patrons to place holds (updates Transaction Log).

P5: PATRON MANAGEMENT
    - Manages member accounts.
    - Librarians create/edit records in the Patron Database.
    - Handles fines and fees.

P6: SERIALS
    - Manages periodical subscriptions.
    - Updates the Serials Registry.
    - Receives shipment notifications from Publisher/Vendor.

P7: REPORTS
    - Generates statistics for Librarians.
    - Reads data from all Data Stores (Biblio, Patron DB, Transactions, Ledger).

4. DATA STORES
--------------
D1: BIBLIO CATALOG (Books, Items, MARC records)
D2: PATRON DATABASE (Member details, permissions, fines)
D3: TRANSACTION LOG (Current checkouts, circulation history, holds)
D4: ACQUISITIONS LEDGER (Budgets, funds, orders, invoices)
D5: SERIALS REGISTRY (Subscriptions, prediction patterns)

5. KEY DATA FLOWS
-----------------
- Patron -> Search Query -> OPAC
- OPAC -> Search Results -> Patron
- SIP2 Kiosk -> Checkout Request -> Circulation
- Circulation -> Status Update -> SIP2 Kiosk
- Librarian -> MARC Import -> Cataloging
- Cataloging -> Record Data -> Biblio Catalog
- Acquisitions -> Purchase Order -> Publisher/Vendor
- Publisher/Vendor -> Invoice -> Acquisitions
EOF

chown ga:ga /home/ga/Desktop/koha_system_spec.txt
chmod 644 /home/ga/Desktop/koha_system_spec.txt

# 2. Cleanup previous runs
rm -f /home/ga/Desktop/koha_library_dfd.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/koha_library_dfd.png 2>/dev/null || true

# 3. Launch draw.io
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio"; 
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"; 
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"; fi

if [ -z "$DRAWIO_BIN" ]; then echo "ERROR: draw.io binary not found"; exit 1; fi

echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "draw.io"; then break; fi
    sleep 1
done

sleep 5
# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss startup dialog (creates blank diagram)
DISPLAY=:1 xdotool key Escape
sleep 2

# 4. Record Initial State
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="