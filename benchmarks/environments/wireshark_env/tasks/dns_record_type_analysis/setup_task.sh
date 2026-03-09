#!/bin/bash
# Setup script for DNS Record Type Analysis task
echo "=== Setting up DNS Record Type Analysis ==="

. /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 scrot "$path" 2>/dev/null || DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

rm -f /tmp/task_result.json /tmp/ground_truth_* /tmp/initial_* /tmp/task_start_*

PCAP="/home/ga/Documents/captures/dns.cap"

if [ ! -f "$PCAP" ]; then
    echo "ERROR: $PCAP not found!"
    exit 1
fi

rm -f /home/ga/Documents/captures/dns_audit_report.txt

# --- Compute ground truth using tshark ---

# Unique domain names queried
GT_DOMAINS=$(tshark -r "$PCAP" -Y "dns.flags.response == 0" -T fields -e dns.qry.name 2>/dev/null | sort -u | grep -v "^$")
echo "$GT_DOMAINS" > /tmp/ground_truth_dns_domains

# DNS record types (numeric to name mapping done in Python)
GT_RECORD_TYPES_RAW=$(tshark -r "$PCAP" -Y "dns.flags.response == 0" -T fields -e dns.qry.type 2>/dev/null | sort | uniq -c | sort -rn)
echo "$GT_RECORD_TYPES_RAW" > /tmp/ground_truth_dns_record_types_raw

# Map numeric types to names and count
python3 << 'PYEOF'
import subprocess, collections

DNS_TYPE_MAP = {
    "1": "A", "2": "NS", "5": "CNAME", "6": "SOA",
    "12": "PTR", "15": "MX", "16": "TXT", "28": "AAAA",
    "29": "LOC", "33": "SRV", "35": "NAPTR", "255": "ANY",
    "257": "CAA", "52": "TLSA", "43": "DS",
}

result = subprocess.run(
    ["tshark", "-r", "/home/ga/Documents/captures/dns.cap",
     "-Y", "dns.flags.response == 0", "-T", "fields", "-e", "dns.qry.type"],
    capture_output=True, text=True
)

type_counts = collections.Counter()
for line in result.stdout.strip().split("\n"):
    for t in line.strip().split(","):
        t = t.strip()
        if t:
            name = DNS_TYPE_MAP.get(t, f"TYPE{t}")
            type_counts[name] += 1

with open("/tmp/ground_truth_dns_type_counts", "w") as f:
    for name, count in sorted(type_counts.items(), key=lambda x: -x[1]):
        f.write(f"{name}\t{count}\n")

# Also save just the type names
with open("/tmp/ground_truth_dns_type_names", "w") as f:
    f.write("\n".join(sorted(type_counts.keys())))

print("DNS type counts:")
for name, count in sorted(type_counts.items(), key=lambda x: -x[1]):
    print(f"  {name}: {count}")
PYEOF

# DNS server IPs (destination of queries)
GT_DNS_SERVERS=$(tshark -r "$PCAP" -Y "dns.flags.response == 0" -T fields -e ip.dst 2>/dev/null | sort -u)
echo "$GT_DNS_SERVERS" > /tmp/ground_truth_dns_servers

# Query count
GT_QUERY_COUNT=$(tshark -r "$PCAP" -Y "dns.flags.response == 0" 2>/dev/null | wc -l)
echo "$GT_QUERY_COUNT" > /tmp/ground_truth_dns_query_count

# Response count
GT_RESPONSE_COUNT=$(tshark -r "$PCAP" -Y "dns.flags.response == 1" 2>/dev/null | wc -l)
echo "$GT_RESPONSE_COUNT" > /tmp/ground_truth_dns_response_count

date +%s > /tmp/task_start_timestamp

echo "Ground truth computed:"
echo "  Domains: $(echo "$GT_DOMAINS" | wc -l) unique"
echo "  DNS servers: $GT_DNS_SERVERS"
echo "  Queries: $GT_QUERY_COUNT"
echo "  Responses: $GT_RESPONSE_COUNT"

# Launch Wireshark
pkill -f wireshark 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 wireshark '$PCAP' > /tmp/wireshark_task.log 2>&1 &"
sleep 5

take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
