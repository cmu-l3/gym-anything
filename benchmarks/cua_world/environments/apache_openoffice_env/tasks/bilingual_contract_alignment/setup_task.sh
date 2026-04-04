#!/bin/bash
set -e

echo "=== Setting up Bilingual Contract Alignment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure Documents directory exists
sudo -u ga mkdir -p /home/ga/Documents

# Clean up any previous task artifacts
rm -f /home/ga/Documents/GlobalTech_Schmidt_Agreement.odt
rm -f /home/ga/Documents/contract_data.json

# Create the source data JSON file
cat > /home/ga/Documents/contract_data.json << 'EOF'
{
  "document_title": {
    "en": "DISTRIBUTION AGREEMENT",
    "de": "VERTRIEBSVERTRAG"
  },
  "header_text": "CONFIDENTIAL / VERTRAULICH",
  "preamble": {
    "en": "This Agreement is made on March 15, 2025, between GlobalTech Solutions Inc., a corporation organized under the laws of California (\"Supplier\"), and Schmidt Engineering GmbH, a company organized under the laws of Germany (\"Distributor\").",
    "de": "Dieser Vertrag wird am 15. März 2025 zwischen GlobalTech Solutions Inc., einer Gesellschaft nach dem Recht von Kalifornien („Lieferant“), und der Schmidt Engineering GmbH, einer Gesellschaft nach dem Recht von Deutschland („Vertriebshändler“), geschlossen."
  },
  "clauses": [
    {
      "id": 1,
      "title_en": "1. APPOINTMENT",
      "text_en": "The Supplier hereby appoints the Distributor as its non-exclusive distributor for the promotion and sale of the Products in the Territory. The Distributor accepts such appointment.",
      "title_de": "1. ERNENNUNG",
      "text_de": "Der Lieferant ernennt hiermit den Vertriebshändler zu seinem nicht-exklusiven Vertriebshändler für die Bewerbung und den Verkauf der Produkte im Vertragsgebiet. Der Vertriebshändler nimmt diese Ernennung an."
    },
    {
      "id": 2,
      "title_en": "2. TERRITORY",
      "text_en": "The Territory shall be defined as the Federal Republic of Germany, Austria, and Switzerland (DACH region).",
      "title_de": "2. VERTRAGSGEBIET",
      "text_de": "Das Vertragsgebiet umfasst die Bundesrepublik Deutschland, Österreich und die Schweiz (DACH-Region)."
    },
    {
      "id": 3,
      "title_en": "3. PRICES AND PAYMENT",
      "text_en": "The prices for the Products shall be as set forth in the Supplier's current price list. Payment shall be made in Euros (EUR) within thirty (30) days from the date of invoice.",
      "title_de": "3. PREISE UND ZAHLUNGSBEDINGUNGEN",
      "text_de": "Die Preise für die Produkte richten sich nach der aktuellen Preisliste des Lieferanten. Zahlungen sind in Euro (EUR) innerhalb von dreißig (30) Tagen nach Rechnungsdatum zu leisten."
    },
    {
      "id": 4,
      "title_en": "4. FORCE MAJEURE",
      "text_en": "Neither party shall be liable for any failure or delay in performing its obligations under this Agreement if such failure or delay is due to causes beyond its reasonable control, including but not limited to acts of God, war, or strikes.",
      "title_de": "4. HÖHERE GEWALT",
      "text_de": "Keine Partei haftet für eine Nichterfüllung oder Verzögerung bei der Erfüllung ihrer Verpflichtungen aus diesem Vertrag, wenn diese Nichterfüllung oder Verzögerung auf Ursachen zurückzuführen ist, die außerhalb ihrer angemessenen Kontrolle liegen, einschließlich, aber nicht beschränkt auf höhere Gewalt, Krieg oder Streiks."
    },
    {
      "id": 5,
      "title_en": "5. CONFIDENTIALITY",
      "text_en": "Each party agrees to keep confidential all technical and commercial information received from the other party which is marked as confidential.",
      "title_de": "5. GEHEIMHALTUNG",
      "text_de": "Jede Partei verpflichtet sich, alle von der anderen Partei erhaltenen technischen und kommerziellen Informationen, die als vertraulich gekennzeichnet sind, geheim zu halten."
    },
    {
      "id": 6,
      "title_en": "6. TERM AND TERMINATION",
      "text_en": "This Agreement shall come into force on the Effective Date and shall remain in force for a period of two (2) years. Either party may terminate this Agreement by giving three (3) months written notice.",
      "title_de": "6. LAUFZEIT UND KÜNDIGUNG",
      "text_de": "Dieser Vertrag tritt am Inkrafttretensdatum in Kraft und bleibt für einen Zeitraum von zwei (2) Jahren in Kraft. Jede Partei kann diesen Vertrag unter Einhaltung einer Frist von drei (3) Monaten schriftlich kündigen."
    },
    {
      "id": 7,
      "title_en": "7. GOVERNING LAW",
      "text_en": "This Agreement shall be governed by and construed in accordance with the laws of the Federal Republic of Germany, excluding the UN Convention on Contracts for the International Sale of Goods (CISG).",
      "title_de": "7. ANWENDBARES RECHT",
      "text_de": "Dieser Vertrag unterliegt dem Recht der Bundesrepublik Deutschland unter Ausschluss des UN-Kaufrechts (CISG)."
    },
    {
      "id": 8,
      "title_en": "8. MISCELLANEOUS",
      "text_en": "Amendments to this Agreement must be made in writing. If any provision of this Agreement is held to be invalid, the remaining provisions shall remain in full force and effect.",
      "title_de": "8. SONSTIGES",
      "text_de": "Änderungen dieses Vertrages bedürfen der Schriftform. Sollte eine Bestimmung dieses Vertrages unwirksam sein, so bleiben die übrigen Bestimmungen davon unberührt."
    }
  ]
}
EOF

chown ga:ga /home/ga/Documents/contract_data.json

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

# Ensure Writer is NOT running (clean state)
pkill -f soffice || true

# Wait for process to exit
sleep 2

# Take initial screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="