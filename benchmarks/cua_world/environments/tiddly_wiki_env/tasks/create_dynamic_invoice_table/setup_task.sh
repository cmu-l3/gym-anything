#!/bin/bash
echo "=== Setting up create_dynamic_invoice_table task ==="

source /workspace/scripts/task_utils.sh

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Seed the invoice data into TiddlyWiki
echo "Seeding 15 invoice tiddlers..."
su - ga -c 'node -e "
const fs = require(\"fs\");
const path = require(\"path\");

const invoices = [
  { id: \"INV-1001\", client: \"Altus Health Systems\", amount: \"4500.00\", status: \"Paid\", due: \"2024-01-15\" },
  { id: \"INV-1002\", client: \"NovaTech Manufacturing\", amount: \"8450.00\", status: \"Paid\", due: \"2024-01-20\" },
  { id: \"INV-1003\", client: \"Summit Financial\", amount: \"1200.00\", status: \"Paid\", due: \"2024-02-05\" },
  { id: \"INV-1004\", client: \"Apex Logistics\", amount: \"3400.00\", status: \"Paid\", due: \"2024-02-18\" },
  { id: \"INV-1005\", client: \"Nexus Consulting\", amount: \"6700.00\", status: \"Pending\", due: \"2024-03-01\" },
  { id: \"INV-1006\", client: \"Altus Health Systems\", amount: \"4500.00\", status: \"Pending\", due: \"2024-03-15\" },
  { id: \"INV-1007\", client: \"NovaTech Manufacturing\", amount: \"2100.00\", status: \"Pending\", due: \"2024-03-22\" },
  { id: \"INV-1008\", client: \"Summit Financial\", amount: \"5600.00\", status: \"Overdue\", due: \"2024-02-28\" },
  { id: \"INV-1009\", client: \"Apex Logistics\", amount: \"8900.00\", status: \"Pending\", due: \"2024-04-10\" },
  { id: \"INV-1010\", client: \"Nexus Consulting\", amount: \"1500.00\", status: \"Pending\", due: \"2024-04-15\" },
  { id: \"INV-1011\", client: \"Altus Health Systems\", amount: \"3200.00\", status: \"Pending\", due: \"2024-04-20\" },
  { id: \"INV-1012\", client: \"NovaTech Manufacturing\", amount: \"7800.00\", status: \"Pending\", due: \"2024-05-01\" },
  { id: \"INV-1013\", client: \"Summit Financial\", amount: \"4300.00\", status: \"Pending\", due: \"2024-05-15\" },
  { id: \"INV-1014\", client: \"Apex Logistics\", amount: \"2500.00\", status: \"Pending\", due: \"2024-05-20\" },
  { id: \"INV-1015\", client: \"Nexus Consulting\", amount: \"5400.00\", status: \"Pending\", due: \"2024-06-05\" }
];

const tiddlerDir = \"/home/ga/mywiki/tiddlers\";
if (!fs.existsSync(tiddlerDir)) fs.mkdirSync(tiddlerDir, { recursive: true });

invoices.forEach(inv => {
  const content = \`title: \${inv.id}\\ntags: Invoice\\nclient: \${inv.client}\\namount: \${inv.amount}\\nstatus: \${inv.status}\\ndue_date: \${inv.due}\\n\\nInvoice details for \${inv.id}.\`;
  fs.writeFileSync(path.join(tiddlerDir, inv.id + \".tid\"), content);
});
console.log(\"Seeded 15 invoices.\");
"'

# 2. Verify TiddlyWiki is running
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "TiddlyWiki server is running"
else
    echo "WARNING: TiddlyWiki server not accessible"
fi

# 3. Ensure Firefox is focused
DISPLAY=:1 xdotool search --name "TiddlyWiki\|firefox\|Mozilla" windowactivate 2>/dev/null || true

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="