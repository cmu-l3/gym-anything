#!/bin/bash
set -euo pipefail

echo "=== Setting up hospital_it_ransomware_response task ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="hospital_it_ransomware_response"

# Remove stale output files
rm -f "/tmp/${TASK_NAME}_result.json" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_start_ts" 2>/dev/null || true
rm -f "/tmp/${TASK_NAME}_baseline.json" 2>/dev/null || true

# Wait for Rocket.Chat
if ! wait_for_http "${ROCKETCHAT_BASE_URL}/api/info" 600; then
  echo "ERROR: Rocket.Chat API is not reachable"
  exit 1
fi

# Login as admin
for _ in $(seq 1 60); do
  if api_login "$ROCKETCHAT_TASK_USERNAME" "$ROCKETCHAT_TASK_PASSWORD"; then
    break
  fi
  sleep 2
done

LOGIN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/json" \
  -d "{\"user\":\"${ROCKETCHAT_TASK_USERNAME}\",\"password\":\"${ROCKETCHAT_TASK_PASSWORD}\"}" \
  "${ROCKETCHAT_BASE_URL}/api/v1/login" 2>/dev/null)
TOKEN=$(echo "$LOGIN_RESP" | jq -r '.data.authToken')
USERID=$(echo "$LOGIN_RESP" | jq -r '.data.userId')

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get auth token"
  exit 1
fi

rc_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"
  if [ -n "$data" ]; then
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  else
    curl -sS -X "$method" \
      -H "X-Auth-Token: $TOKEN" \
      -H "X-User-Id: $USERID" \
      -H "Content-Type: application/json" \
      "${ROCKETCHAT_BASE_URL}/api/v1/${endpoint}" 2>/dev/null
  fi
}

create_user_if_not_exists() {
  local username="$1"
  local name="$2"
  local email="$3"
  rc_api POST "users.create" \
    "{\"username\":\"${username}\",\"name\":\"${name}\",\"email\":\"${email}\",\"password\":\"UserPass123!\",\"verified\":true,\"roles\":[\"user\"],\"joinDefaultChannels\":false,\"requirePasswordChange\":false,\"sendWelcomeEmail\":false}" >/dev/null 2>&1 || true
  echo "Ensured user: $username"
}

# Create users
create_user_if_not_exists "clinical.coordinator" "Dr. Sarah Kim - Clinical Coordinator" "clinical.coordinator@riverside-medical.local"
create_user_if_not_exists "it.security" "Marcus Torres - IT Security" "it.security@riverside-medical.local"
create_user_if_not_exists "nursing.supervisor" "Nancy Chen - Nursing Supervisor" "nursing.supervisor@riverside-medical.local"
create_user_if_not_exists "ciso" "David Park - CISO" "ciso@riverside-medical.local"
create_user_if_not_exists "ehr.vendor.support" "EHR Vendor Support" "support@ehr-vendor.com"
create_user_if_not_exists "helpdesk.lead" "Tom Walsh - Helpdesk Lead" "helpdesk.lead@riverside-medical.local"
create_user_if_not_exists "biomedical.eng" "Lisa Nguyen - Biomedical Engineering" "biomedical.eng@riverside-medical.local"
create_user_if_not_exists "network.admin" "Kevin Park - Network Admin" "network.admin@riverside-medical.local"

# Delete any pre-existing incident/emergency channels to ensure clean state
for ch in "inc-ransomware" "incident-command" "emergency-response" "ir-2026" "ransomware-response" "ehr-incident"; do
  rc_api POST "groups.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
  rc_api POST "channels.delete" "{\"roomName\":\"${ch}\"}" >/dev/null 2>&1 || true
done

# Create #clinical-it-alerts channel
CLINICAL_RESP=$(rc_api POST "channels.create" \
  '{"name":"clinical-it-alerts","members":["clinical.coordinator","it.security","nursing.supervisor","ciso","helpdesk.lead","biomedical.eng","network.admin"],"readOnly":false}')
CLINICAL_ID=$(echo "$CLINICAL_RESP" | jq -r '.channel._id // empty')
if [ -z "$CLINICAL_ID" ]; then
  CLINICAL_INFO=$(rc_api GET "channels.info?roomName=clinical-it-alerts")
  CLINICAL_ID=$(echo "$CLINICAL_INFO" | jq -r '.channel._id // empty')
fi

# Seed clinical-it-alerts with escalating messages (realistic hospital IT incident)
CLINICAL_MSG1_ID=""
CLINICAL_MSG2_ID=""
CLINICAL_MSG3_ID=""

if [ -n "$CLINICAL_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#clinical-it-alerts","text":"[07:42] EHR system login latency elevated. Multiple staff reporting 15-30s login delays on Floors 3, 4, and 5. Helpdesk ticket volume up. Investigating."}' >/dev/null

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#clinical-it-alerts","text":"[08:15] EHR access failures spreading. ICU, OR scheduling, and pharmacy modules intermittently unavailable. Network team notified. Vendor support on standby."}' >/dev/null

  sleep 0.3
  CLINICAL_MSG3_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#clinical-it-alerts","text":"[08:47] CRITICAL: Antivirus system flagged suspicious encryption activity on ehr-app-01 and ehr-app-02. File extensions modified on shared drives. Possible ransomware. EHR vendor escalated to P1. All non-essential network segments should be considered at risk. IT Security engaged. @it.security @ciso please respond IMMEDIATELY."}')
  CLINICAL_MSG3_ID=$(echo "$CLINICAL_MSG3_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#clinical-it-alerts","text":"[09:02] Backup replication to offsite DR site has stopped. Last successful backup: 06:30 today. Attempting manual verification now. Do not restart any EHR application servers until security assessment is complete."}' >/dev/null
fi

# Create #nursing-coordination channel
NURSING_RESP=$(rc_api POST "channels.create" \
  '{"name":"nursing-coordination","members":["nursing.supervisor","clinical.coordinator","helpdesk.lead","biomedical.eng"],"readOnly":false}')
NURSING_ID=$(echo "$NURSING_RESP" | jq -r '.channel._id // empty')
if [ -z "$NURSING_ID" ]; then
  NURSING_INFO=$(rc_api GET "channels.info?roomName=nursing-coordination")
  NURSING_ID=$(echo "$NURSING_INFO" | jq -r '.channel._id // empty')
fi

NURSING_MSG_ID=""
if [ -n "$NURSING_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#nursing-coordination","text":"Nursing staff cannot access patient charts in EHR. Floor 3 and 4 nurses have reverted to paper documentation. @nursing.supervisor what is the official guidance? Do we activate downtime procedures?"}' >/dev/null

  sleep 0.3
  NURSING_MSG_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#nursing-coordination","text":"@admin @clinical.coordinator - This is Nursing Supervisor Chen. We need immediate decision on EHR downtime procedures. Medication administration records cannot be accessed electronically. ICU is particularly affected - they have 12 critical patients. Requesting urgent IT response and clinical leadership guidance. This is a patient safety issue."}')
  NURSING_MSG_ID=$(echo "$NURSING_MSG_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#nursing-coordination","text":"Biomedical devices on Floor 4 that depend on EHR integration (infusion pumps, vitals monitoring) showing connectivity errors. Biomedical Engineering notified. Manual monitoring protocols in effect."}' >/dev/null
fi

# Create #it-security-ops channel
ITSEC_RESP=$(rc_api POST "channels.create" \
  '{"name":"it-security-ops","members":["it.security","ciso","network.admin","helpdesk.lead"],"readOnly":false}')
ITSEC_ID=$(echo "$ITSEC_RESP" | jq -r '.channel._id // empty')
if [ -z "$ITSEC_ID" ]; then
  ITSEC_INFO=$(rc_api GET "channels.info?roomName=it-security-ops")
  ITSEC_ID=$(echo "$ITSEC_INFO" | jq -r '.channel._id // empty')
fi

ITSEC_MSG_ID=""
if [ -n "$ITSEC_ID" ]; then
  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#it-security-ops","text":"[EDR Alert] Suspicious process tree detected on ehr-app-01: conhost.exe spawning cmd.exe -> powershell.exe with obfuscated arguments. Process hash matches known ransomware dropper (Ryuk variant). Endpoint isolated from network. Forensic collection initiated."}' >/dev/null

  sleep 0.3
  ITSEC_MSG_RESP=$(rc_api POST "chat.postMessage" \
    '{"channel":"#it-security-ops","text":"@ciso @admin Confirmed: LockBit ransomware indicators on ehr-app-01, ehr-app-02, and file-server-clinical-01. Lateral movement detected. Attacker had access since approximately 03:15 this morning (based on initial beacon). Affected: \\\\RIVERSIDE-EHR-01 (encrypted), \\\\RIVERSIDE-FS-CLINICAL (partial encryption in progress). Recommend: IMMEDIATE network segmentation, activate BC/DR plan, contact FBI Cyber Division and HHS. HIPAA breach notification likely required. Do NOT pay ransom."}')
  ITSEC_MSG_ID=$(echo "$ITSEC_MSG_RESP" | jq -r '.message._id // empty')

  sleep 0.3
  rc_api POST "chat.postMessage" \
    '{"channel":"#it-security-ops","text":"Contacted FBI Cyber Division field office. They want chain of custody documentation for affected systems. Preserve all logs before any remediation. Snapshot of compromised VMs being taken now."}' >/dev/null
fi

# Record baseline state
BASELINE_GROUPS=$(rc_api GET "groups.listAll?count=200" | jq '[.groups[].name] // []' 2>/dev/null || echo '[]')
BASELINE_CHANNELS=$(rc_api GET "channels.list?count=200" | jq '[.channels[].name] // []' 2>/dev/null || echo '[]')

cat > "/tmp/${TASK_NAME}_baseline.json" << EOF
{
  "task_start": $(date +%s),
  "clinical_it_alerts_id": "${CLINICAL_ID:-}",
  "nursing_coordination_id": "${NURSING_ID:-}",
  "it_security_ops_id": "${ITSEC_ID:-}",
  "clinical_critical_msg_id": "${CLINICAL_MSG3_ID:-}",
  "nursing_urgent_msg_id": "${NURSING_MSG_ID:-}",
  "itsec_confirmed_msg_id": "${ITSEC_MSG_ID:-}",
  "baseline_groups": ${BASELINE_GROUPS},
  "baseline_channels": ${BASELINE_CHANNELS}
}
EOF

date +%s > "/tmp/${TASK_NAME}_start_ts"

# Restart browser at login page
if ! restart_firefox "$ROCKETCHAT_LOGIN_URL" 4; then
  echo "ERROR: Browser failed to start"
  exit 1
fi

focus_firefox || true
navigate_to_url "$ROCKETCHAT_LOGIN_URL"
sleep 2
focus_firefox || true

take_screenshot "/tmp/${TASK_NAME}_start.png"

echo "=== Setup complete ==="
echo "clinical-it-alerts critical msg ID: ${CLINICAL_MSG3_ID:-unknown}"
echo "nursing-coordination urgent msg ID: ${NURSING_MSG_ID:-unknown}"
echo "it-security-ops confirmed msg ID: ${ITSEC_MSG_ID:-unknown}"
