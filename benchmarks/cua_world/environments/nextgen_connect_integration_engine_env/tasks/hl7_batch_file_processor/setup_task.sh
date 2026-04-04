#!/bin/bash
echo "=== Setting up hl7_batch_file_processor task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Create required directories as ga user
echo "Creating batch processing directories..."
mkdir -p /home/ga/hl7_batch_inbox
mkdir -p /home/ga/hl7_batch_archive
mkdir -p /home/ga/hl7_batch_errors
chown -R ga:ga /home/ga/hl7_batch_inbox /home/ga/hl7_batch_archive /home/ga/hl7_batch_errors
chmod 755 /home/ga/hl7_batch_inbox /home/ga/hl7_batch_archive /home/ga/hl7_batch_errors

# Place the sample batch HL7 file in the inbox directory
echo "Placing sample batch HL7 file in inbox..."
cp /workspace/assets/hl7-v2.5-batch-adt.hl7 /home/ga/hl7_batch_inbox/nightly_batch_20240115.hl7
chown ga:ga /home/ga/hl7_batch_inbox/nightly_batch_20240115.hl7
chmod 644 /home/ga/hl7_batch_inbox/nightly_batch_20240115.hl7

# Also provide a copy for reference (so agent knows what the batch looks like)
cp /workspace/assets/hl7-v2.5-batch-adt.hl7 /home/ga/sample_batch.hl7
chown ga:ga /home/ga/sample_batch.hl7
chmod 644 /home/ga/sample_batch.hl7

# Record initial channel count
INITIAL_COUNT=$(get_channel_count)
rm -f /tmp/initial_batchproc_channel_count 2>/dev/null || sudo rm -f /tmp/initial_batchproc_channel_count 2>/dev/null || true
printf '%s' "$INITIAL_COUNT" > /tmp/initial_batchproc_channel_count 2>/dev/null || true

echo "Initial channel count: $INITIAL_COUNT"

# Open a terminal window for the agent to use
DISPLAY=:1 gnome-terminal --geometry=130x55+70+30 -- bash -c '
echo "========================================================"
echo " NextGen Connect - Nightly HL7 Batch File Processor"
echo "========================================================"
echo ""
echo "TASK: Build a file-polling channel that processes nightly"
echo "      BHS/BTS-wrapped batch HL7 files from hospitals"
echo ""
echo "Batch file structure (BHS/BTS envelope):"
echo "  BHS|^~\\&|BatchSystem|Hospital|...|BATCH001"
echo "  MSH|...  <- individual message 1"
echo "  PID|..."
echo "  MSH|...  <- individual message 2"
echo "  PID|..."
echo "  BTS|4    <- batch message count"
echo ""
echo "Inbox directory: /home/ga/hl7_batch_inbox/"
echo "  Sample file: nightly_batch_20240115.hl7"
echo "Archive dir:  /home/ga/hl7_batch_archive/"
echo "Reference copy: /home/ga/sample_batch.hl7"
echo ""
echo "Channel requirements:"
echo "  Name: Nightly HL7 Batch Processor"
echo "  Source: File Reader (NOT TCP) polling /home/ga/hl7_batch_inbox/*.hl7"
echo "  Preprocessor: JavaScript to split batch -> individual messages"
echo "    OR use channel batch processing (Process Batch=true)"
echo "  After Processing: Move files to /home/ga/hl7_batch_archive/"
echo "  Destination: DB Writer -> batch_processing_log"
echo "    Columns: batch_file, message_seq, patient_mrn, message_type, processed_at"
echo "    Extract: MRN from PID-3.1, message type from MSH-9"
echo ""
echo "Create table first:"
echo "  docker exec nextgen-postgres psql -U postgres -d mirthdb -c \\"
echo "  \"CREATE TABLE IF NOT EXISTS batch_processing_log ("
echo "    batch_file VARCHAR(255),"
echo "    message_seq INTEGER,"
echo "    patient_mrn VARCHAR(50),"
echo "    message_type VARCHAR(20),"
echo "    processed_at TIMESTAMP DEFAULT NOW());\""
echo ""
echo "KEY DIFFERENCE: File Reader source requires different XML than TCP Listener"
echo "  Source connector class: com.mirth.connect.connectors.file.FileReceiverProperties"
echo "  Set directoryPath, fileFilter (*.hl7), moveToDirectory (archive path)"
echo "  Set processBatch=true for batch splitting, or use preprocessor JS"
echo ""
echo "PostgreSQL (container): jdbc:postgresql://nextgen-postgres:5432/mirthdb"
echo "  User: postgres  Password: postgres"
echo "REST API: https://localhost:8443/api | admin:admin"
echo "  Required header: X-Requested-With: OpenAPI"
echo "========================================================"
echo ""
exec bash
' 2>/dev/null &

sleep 2
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

echo "=== Task setup complete ==="
