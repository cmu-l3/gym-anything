#!/bin/bash
# Export script for overdue_followup_scheduling task

echo "=== Exporting overdue_followup_scheduling Result ==="

source /workspace/scripts/task_utils.sh

if ! type medintux_query &>/dev/null; then
    medintux_query() { mysql -u root DrTuxTest -N -B -e "$1" 2>/dev/null; }
fi
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || true; }
fi

take_screenshot /tmp/overdue_followup_end.png 2>/dev/null || true

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_START_DT=$(date -d "@${TASK_START}" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo "2026-01-01 00:00:00")

# Check which overdue patients got new agenda entries after task start
# (Date_Time > NOW() means future appointments — scheduled for future dates)
# We check GUID field which stores patient GUID when appointment is created via patient file

check_agenda_entry() {
    local guid="$1"
    # Check for agenda entry for this patient (by GUID) added after task start
    # Appointment type should be Consultation and date should be in the future
    medintux_query "
        SELECT COUNT(*) FROM agenda
        WHERE GUID='$guid'
        AND Type='Consultation'
        AND PrimKey > (SELECT COALESCE(MAX(PrimKey),0) FROM agenda WHERE PrimKey=0);
    "
    # Alternative: check by creation time (PrimKey is auto-increment, so higher = newer)
    # Since we can't directly track insertion time in agenda, we check PrimKey
}

# Get baseline PrimKey (highest PrimKey before agent started)
BASELINE_MAXPK=$(medintux_query "SELECT COALESCE(MAX(PrimKey), 0) FROM agenda;")
BASELINE_MAXPK=${BASELINE_MAXPK:-0}
# Note: In setup we didn't record this, so we read it now (task_start has passed already, any new entries are agent's)

# More reliable: check agenda entries for our specific patient GUIDs where PrimKey > baseline
# Since setup_task.sh deleted all agenda entries for these patients and recorded start time,
# ANY new agenda entry for these GUIDs after setup is the agent's work.

GUID_PETIT="0C1E07E8-F19E-410F-8F46-403388A0924D"
GUID_DURAND="C4B37BEC-5F7F-4A56-80A1-1ADB9B6CC52E"
GUID_GIRARD="826A8DE5-F007-4040-BB91-74F2E5C8DA14"
GUID_MOREL="BA73A90A-B637-4321-AB65-952E0FA0F040"
GUID_HENRY="D12A6F18-4C10-4DCC-ABE6-15699EBB7C24"
GUID_ROUX="61FD5B15-0CA8-42C4-A4D6-59B542BD7EA9"
GUID_BLANC="E5D70363-94D8-453C-8E1A-67D9AB289F87"

# For each overdue patient: check if they have any agenda entry (any type, any future date)
check_any_agenda() {
    local guid="$1"
    medintux_query "SELECT COUNT(*) FROM agenda WHERE GUID='$guid';"
}

# Also check what names appear (agent may type name not guid)
check_agenda_by_name() {
    local nom="$1"
    local prenom="$2"
    medintux_query "SELECT COUNT(*) FROM agenda WHERE Nom='$nom' AND Prenom='$prenom';"
}

PETIT_SCHED=$(check_any_agenda "$GUID_PETIT")
DURAND_SCHED=$(check_any_agenda "$GUID_DURAND")
GIRARD_SCHED=$(check_any_agenda "$GUID_GIRARD")
MOREL_SCHED=$(check_any_agenda "$GUID_MOREL")
HENRY_SCHED=$(check_any_agenda "$GUID_HENRY")

# Also check by name (agent might create appointment by typing name, not via patient file)
PETIT_BY_NAME=$(check_agenda_by_name "PETIT" "Nathalie")
DURAND_BY_NAME=$(check_agenda_by_name "DURAND" "Christophe")
GIRARD_BY_NAME=$(check_agenda_by_name "GIRARD" "Michel")
MOREL_BY_NAME=$(check_agenda_by_name "MOREL" "Sylvie")
HENRY_BY_NAME=$(check_agenda_by_name "HENRY" "Emmanuel")

# Take max of GUID-based and name-based checks
PETIT_FINAL=$(( PETIT_SCHED > PETIT_BY_NAME ? PETIT_SCHED : PETIT_BY_NAME ))
DURAND_FINAL=$(( DURAND_SCHED > DURAND_BY_NAME ? DURAND_SCHED : DURAND_BY_NAME ))
GIRARD_FINAL=$(( GIRARD_SCHED > GIRARD_BY_NAME ? GIRARD_SCHED : GIRARD_BY_NAME ))
MOREL_FINAL=$(( MOREL_SCHED > MOREL_BY_NAME ? MOREL_SCHED : MOREL_BY_NAME ))
HENRY_FINAL=$(( HENRY_SCHED > HENRY_BY_NAME ? HENRY_SCHED : HENRY_BY_NAME ))

# Check if non-overdue patients incorrectly got appointments
ROUX_SCHEDULED=$(check_any_agenda "$GUID_ROUX")
BLANC_SCHEDULED=$(check_any_agenda "$GUID_BLANC")
ROUX_SCHEDULED=${ROUX_SCHEDULED:-0}
BLANC_SCHEDULED=${BLANC_SCHEDULED:-0}

PETIT_FINAL=${PETIT_FINAL:-0}
DURAND_FINAL=${DURAND_FINAL:-0}
GIRARD_FINAL=${GIRARD_FINAL:-0}
MOREL_FINAL=${MOREL_FINAL:-0}
HENRY_FINAL=${HENRY_FINAL:-0}

echo "Scheduled: PETIT=$PETIT_FINAL DURAND=$DURAND_FINAL GIRARD=$GIRARD_FINAL MOREL=$MOREL_FINAL HENRY=$HENRY_FINAL"
echo "Should NOT have been scheduled: ROUX=$ROUX_SCHEDULED BLANC=$BLANC_SCHEDULED"

cat > /tmp/overdue_followup_result.json << EOF
{
    "task_start": ${TASK_START},
    "petit_scheduled": ${PETIT_FINAL},
    "durand_scheduled": ${DURAND_FINAL},
    "girard_scheduled": ${GIRARD_FINAL},
    "morel_scheduled": ${MOREL_FINAL},
    "henry_scheduled": ${HENRY_FINAL},
    "roux_scheduled_incorrectly": ${ROUX_SCHEDULED},
    "blanc_scheduled_incorrectly": ${BLANC_SCHEDULED}
}
EOF

echo "Result saved to /tmp/overdue_followup_result.json"
echo "=== Export Complete ==="
