#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug HL7 Anonymizer Task ==="

WORKSPACE_DIR="/home/ga/workspace/hl7_anonymizer"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/utils"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data/input"
sudo -u ga mkdir -p "$WORKSPACE_DIR/output"
sudo -u ga mkdir -p "$WORKSPACE_DIR/test"

# ─────────────────────────────────────────────────────────────
# 1. Generate package.json and Test Suite
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "hl7-anonymizer",
  "version": "1.0.0",
  "description": "HL7 v2 parsing and anonymization pipeline",
  "main": "src/index.js",
  "scripts": {
    "start": "node src/index.js",
    "test": "mocha test/*.js"
  },
  "devDependencies": {
    "mocha": "^10.2.0"
  }
}
EOF

cat > "$WORKSPACE_DIR/test/test.js" << 'EOF'
const assert = require('assert');
const parser = require('../src/parser');
const anonymizer = require('../src/anonymizer');
const { shiftDate } = require('../src/utils/dateFormatter');

describe('HL7 Pipeline Tests', () => {
    it('Date Formatter: should shift dates correctly across month boundaries', () => {
        // May 31, 1990 shifted by -15 days should be May 16, 1990
        assert.strictEqual(shiftDate('19900531', -15), '19900516');
    });

    it('Anonymizer: should completely remove PHI (name, address, phone)', () => {
        const mockParsed = {
            patient: {
                id: '123',
                name: 'Doe^John',
                dob: '19800101',
                address: '123 Main St',
                phone: '555-1234'
            }
        };
        const result = anonymizer.anonymize(mockParsed);
        assert.strictEqual(result.patient.name, undefined, 'Name must be removed');
        assert.strictEqual(result.patient.address, undefined, 'Address must be removed');
        assert.strictEqual(result.patient.phone, undefined, 'Phone must be removed');
    });

    it('Parser: should not crash if AL1 (allergies) segment is missing', () => {
        const raw = "MSH|^~\\&|APP|FAC|APP|FAC|202310010900||ADT^A01|MSG|P|2.3\nPID|1||10002||Smith^Jane||19900531|F|||456 Oak Ave||555-0200";
        assert.doesNotThrow(() => {
            parser.parse(raw);
        });
    });

    it('Parser: should extract ALL lab results (OBX), not just the first one', () => {
        const raw = "PID|1||123||Smith^John\nOBX|1|NM|WBC||5.5|K/uL\nOBX|2|NM|RBC||4.5|M/uL";
        const parsed = parser.parse(raw);
        assert.strictEqual(parsed.labs.length, 2, 'Should find both OBX segments');
    });
});
EOF

# ─────────────────────────────────────────────────────────────
# 2. Generate Application Source Code (with bugs)
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/index.js" << 'EOF'
const fs = require('fs').promises;
const path = require('path');
const parser = require('./parser');
const anonymizer = require('./anonymizer');

async function main() {
    const inputDir = path.join(__dirname, '../data/input');
    const outputDir = path.join(__dirname, '../output');

    try {
        const files = await fs.readdir(inputDir);
        let results = [];

        // BUG: async callback inside forEach doesn't block execution
        files.forEach(async (file) => {
            if (!file.endsWith('.hl7')) return;
            const data = await fs.readFile(path.join(inputDir, file), 'utf8');
            const parsed = parser.parse(data);
            const anonymized = anonymizer.anonymize(parsed);
            if (anonymized) {
                results.push(anonymized);
            }
        });

        await fs.mkdir(outputDir, { recursive: true });
        
        // This writes before the promises inside forEach resolve
        await fs.writeFile(
            path.join(outputDir, 'anonymized_dataset.json'),
            JSON.stringify(results, null, 2)
        );
        console.log('Processing complete.');
    } catch (err) {
        console.error('Pipeline error:', err);
    }
}

if (require.main === module) {
    main();
}
EOF

cat > "$WORKSPACE_DIR/src/parser.js" << 'EOF'
function parse(raw) {
    const segments = raw.split(/\r?\n/).map(s => s.trim()).filter(s => s);
    const msg = { patient: {}, allergies: [], labs: [] };

    const pidSeg = segments.find(s => s.startsWith('PID|'));
    if (pidSeg) {
        const parts = pidSeg.split('|');
        msg.patient = {
            id: parts[3],
            name: parts[5],
            dob: parts[7],
            address: parts[11],
            phone: parts[13]
        };
    }

    // BUG: Assumes AL1 always exists. Throws TypeError if missing.
    const al1Seg = segments.find(s => s.startsWith('AL1|'));
    const al1Parts = al1Seg.split('|');
    msg.allergies.push({ type: al1Parts[2], reaction: al1Parts[5] });

    // BUG: Uses find() instead of filter(), dropping subsequent lab results
    const obxSeg = segments.find(s => s.startsWith('OBX|'));
    if (obxSeg) {
        const parts = obxSeg.split('|');
        msg.labs.push({ test: parts[3], value: parts[5], units: parts[6] });
    }

    return msg;
}
module.exports = { parse };
EOF

cat > "$WORKSPACE_DIR/src/utils/dateFormatter.js" << 'EOF'
function shiftDate(dateStr, daysToShift) {
    if (!dateStr || dateStr.length < 8) return dateStr;
    const year = parseInt(dateStr.substring(0,4), 10);
    const month = parseInt(dateStr.substring(4,6), 10);
    const day = parseInt(dateStr.substring(6,8), 10);

    // BUG: JS Date month is 0-indexed! (0 = January, 11 = December)
    const d = new Date(year, month, day);
    d.setDate(d.getDate() + daysToShift);

    const outYear = d.getFullYear();
    const outMonth = String(d.getMonth()).padStart(2, '0');
    const outDay = String(d.getDate()).padStart(2, '0');
    return `${outYear}${outMonth}${outDay}`;
}
module.exports = { shiftDate };
EOF

cat > "$WORKSPACE_DIR/src/anonymizer.js" << 'EOF'
const { shiftDate } = require('./utils/dateFormatter');

function anonymize(parsedMsg) {
    if (!parsedMsg || !parsedMsg.patient) return null;

    // Clone the object to avoid mutating the original
    const anonymized = JSON.parse(JSON.stringify(parsedMsg));

    // BUG: Only deletes name. Fails to redact address and phone!
    delete anonymized.patient.name;

    if (anonymized.patient.dob) {
        // Shift DOB backwards by 15 days to de-identify
        anonymized.patient.dob = shiftDate(anonymized.patient.dob, -15);
    }

    return anonymized;
}
module.exports = { anonymize };
EOF

# ─────────────────────────────────────────────────────────────
# 3. Create Sample HL7 Data
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/data/input/msg_001.hl7" << 'EOF'
MSH|^~\&|CLINIC|FAC|RESEARCH|LAB|202310010800||ADT^A01|MSG001|P|2.3
PID|1||PT-1001||Doe^John||19800101|M|||123 Elm St^^Springfield^IL^62701||555-0100
AL1|1|^|PENICILLIN||HIVES
OBX|1|NM|GLU^Glucose||95|mg/dL
OBX|2|NM|K^Potassium||4.2|mEq/L
EOF

cat > "$WORKSPACE_DIR/data/input/msg_002.hl7" << 'EOF'
MSH|^~\&|CLINIC|FAC|RESEARCH|LAB|202310010900||ADT^A01|MSG002|P|2.3
PID|1||PT-1002||Smith^Jane||19900531|F|||456 Oak Ave^^Metropolis^NY^10001||555-0200
OBX|1|NM|WBC^White Blood Count||6.5|K/uL
EOF

cat > "$WORKSPACE_DIR/data/input/msg_003.hl7" << 'EOF'
MSH|^~\&|CLINIC|FAC|RESEARCH|LAB|202310011000||ADT^A01|MSG003|P|2.3
PID|1||PT-1003||Lee^David||19751215|M|||789 Pine Ln^^Gotham^NJ^07001||555-0300
AL1|1|^|PEANUTS||ANAPHYLAXIS
OBX|1|NM|HGB^Hemoglobin||14.2|g/dL
OBX|2|NM|PLT^Platelets||250|K/uL
OBX|3|NM|RBC^Red Blood Cells||4.8|M/uL
EOF

# Fix permissions
chown -R ga:ga "$WORKSPACE_DIR"

# Install Mocha
cd "$WORKSPACE_DIR"
sudo -u ga npm install > /dev/null 2>&1

echo "=== Task setup complete ==="