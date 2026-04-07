#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up E-Commerce i18n Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

WORKSPACE_DIR="/home/ga/workspace/shopfront-i18n"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/i18n"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src/locales"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"

# ─── package.json ──────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/package.json" << 'EOF'
{
  "name": "shopfront-i18n",
  "version": "1.0.0",
  "description": "Storefront i18n module",
  "main": "src/i18n/index.js",
  "scripts": {
    "test": "node tests/i18n.test.js"
  }
}
EOF

# ─── src/i18n/config.js (BUG 1: Circular Fallbacks & returnNull) ───
cat > "$WORKSPACE_DIR/src/i18n/config.js" << 'EOF'
module.exports = {
    defaultLocale: 'en',
    // BUG: Circular fallback chain. Missing Japanese keys will trigger a stack overflow!
    // It should just fall back to 'en' for all missing locales.
    fallbacks: {
        'ja': 'de',
        'de': 'pt-BR',
        'pt-BR': 'ja'
    },
    // BUG: Swallows missing keys returning null instead of the key name
    returnNull: true
};
EOF

# ─── src/i18n/interpolator.js (BUG 2: Incorrect Regex) ─────────────
cat > "$WORKSPACE_DIR/src/i18n/interpolator.js" << 'EOF'
module.exports = function interpolate(str, variables) {
    if (!str || !variables) return str;
    
    // BUG: Matches {{var}} instead of single braces {var} used in the locale JSON files.
    // Variables will not be interpolated!
    return str.replace(/{{\s*(\w+)\s*}}/g, (match, key) => {
        return variables[key] !== undefined ? variables[key] : match;
    });
};
EOF

# ─── src/i18n/formatter.js (BUG 3 & 4: Currencies and Dates) ───────
cat > "$WORKSPACE_DIR/src/i18n/formatter.js" << 'EOF'
module.exports = {
    formatCurrency: function(amount, currency, locale = 'en-US') {
        // BUG: Hardcoded 2 decimal places for all currencies. 
        // This breaks JPY which has 0 minor units.
        return new Intl.NumberFormat(locale, {
            style: 'currency',
            currency: currency,
            minimumFractionDigits: 2,
            maximumFractionDigits: 2
        }).format(amount);
    },

    formatDate: function(dateStr, locale = 'en-US') {
        // BUG: Hardcoded American date format MM/DD/YYYY for all locales.
        // Needs to be locale-aware (e.g., DE uses DD.MM.YYYY, JP uses YYYY/MM/DD)
        const d = new Date(dateStr);
        const month = String(d.getMonth() + 1).padStart(2, '0');
        const day = String(d.getDate()).padStart(2, '0');
        const year = d.getFullYear();
        
        return `${month}/${day}/${year}`;
    }
};
EOF

# ─── src/i18n/index.js (The i18n engine - Correct) ─────────────────
cat > "$WORKSPACE_DIR/src/i18n/index.js" << 'EOF'
const config = require('./config');
const interpolate = require('./interpolator');
const formatter = require('./formatter');
const fs = require('fs');
const path = require('path');

const locales = {};
const localesDir = path.join(__dirname, '../locales');
fs.readdirSync(localesDir).forEach(file => {
    if (file.endsWith('.json')) {
        const locale = file.replace('.json', '');
        locales[locale] = require(path.join(localesDir, file));
    }
});

function getNested(obj, keyPath) {
    return keyPath.split('.').reduce((acc, part) => acc && acc[part], obj);
}

function t(key, vars = {}, locale = config.defaultLocale) {
    let val = locales[locale] ? getNested(locales[locale], key) : undefined;

    // Handle fallbacks
    if (val === undefined) {
        const fallback = config.fallbacks[locale];
        if (fallback && fallback !== locale) {
            return t(key, vars, fallback);
        }
        if (locale !== config.defaultLocale) {
            return t(key, vars, config.defaultLocale);
        }
        return config.returnNull ? null : key;
    }

    // Handle plurals based on CLDR rules
    if (vars && vars.count !== undefined) {
        const pr = new Intl.PluralRules(locale).select(vars.count);
        const pluralKey = `${key}_${pr}`;
        const pluralVal = getNested(locales[locale], pluralKey);
        
        if (pluralVal) {
            val = pluralVal;
        } else {
            const otherVal = getNested(locales[locale], `${key}_other`);
            if (otherVal) val = otherVal;
        }
    }

    return interpolate(val, vars);
}

module.exports = {
    t,
    formatCurrency: formatter.formatCurrency,
    formatDate: formatter.formatDate
};
EOF

# ─── Locales ───────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/src/locales/en.json" << 'EOF'
{
  "greeting": "Hello {name}!",
  "cart": {
    "title": "Shopping Cart",
    "itemCount_one": "1 item",
    "itemCount_other": "{count} items"
  }
}
EOF

cat > "$WORKSPACE_DIR/src/locales/ja.json" << 'EOF'
{
  "greeting": "こんにちは {name}！",
  "cart": {
    "title": "ショッピングカート",
    "itemCount_other": "商品{count}点"
  }
}
EOF

cat > "$WORKSPACE_DIR/src/locales/pt-BR.json" << 'EOF'
{
  "greeting": "Olá {name}!",
  "cart": {
    "title": "Carrinho de Compras",
    "itemCount_one": "1 item",
    "itemCount_other": "{count} itens"
  }
}
EOF

# BUG 5: de.json uses Slavic plural forms (zero, few, many) which are invalid for German
cat > "$WORKSPACE_DIR/src/locales/de.json" << 'EOF'
{
  "greeting": "Hallo {name}!",
  "cart": {
    "title": "Warenkorb",
    "itemCount_zero": "0 Artikels",
    "itemCount_one": "1 Artikel",
    "itemCount_few": "Ein paar Artikels",
    "itemCount_many": "Viele Artikels",
    "itemCount_other": "{count} Artikels"
  }
}
EOF

# ─── tests/i18n.test.js ────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/i18n.test.js" << 'EOF'
const assert = require('assert');
const i18n = require('../src/i18n');

let passed = 0;
let failed = 0;

function runTest(name, fn) {
    try {
        fn();
        console.log(`✅ PASS: ${name}`);
        passed++;
    } catch (e) {
        console.log(`❌ FAIL: ${name}`);
        if (e.expected !== undefined) {
            console.log(`   Expected: ${e.expected}`);
            console.log(`   Actual:   ${e.actual}`);
        } else {
            console.log(`   Error: ${e.message}`);
        }
        failed++;
    }
}

console.log("=== Running i18n Validation Suite ===\n");

// 1. Config tests
runTest('Fallback chain avoids circular loops', () => {
    assert.strictEqual(i18n.t('nonexistent.key', {}, 'ja'), 'nonexistent.key');
});
runTest('Missing keys return the key string, not null', () => {
    assert.strictEqual(i18n.t('missing.key', {}, 'en'), 'missing.key');
});

// 2. Interpolator tests
runTest('Interpolates single braces {var}', () => {
    assert.strictEqual(i18n.t('greeting', {name: 'Alice'}, 'en'), 'Hello Alice!');
});
runTest('Interpolates numbers inside strings', () => {
    assert.strictEqual(i18n.t('cart.itemCount', {count: 5}, 'en'), '5 items');
});

// 3. Currency tests
runTest('Formats USD with decimals', () => {
    const usd = i18n.formatCurrency(1234.56, 'USD', 'en-US');
    assert.ok(usd.includes('.56'), 'USD should have 2 decimal places');
});
runTest('Formats JPY without decimals', () => {
    const jpy = i18n.formatCurrency(1234, 'JPY', 'ja-JP');
    assert.ok(!jpy.includes('.00'), 'JPY should not have decimal places');
});

// 4. Date tests
runTest('Formats DE date as DD.MM.YYYY', () => {
    const date = i18n.formatDate('2024-03-15', 'de-DE');
    assert.ok(date.startsWith('15.'), 'German date should start with day 15.');
});
runTest('Formats JP date as YYYY/MM/DD', () => {
    const date = i18n.formatDate('2024-03-15', 'ja-JP');
    assert.ok(date.startsWith('2024'), 'Japanese date should start with year 2024.');
});

// 5. Plural tests
runTest('German plurals: 0 should fall back to _other', () => {
    assert.strictEqual(i18n.t('cart.itemCount', {count: 0}, 'de'), '0 Artikels');
});
runTest('German plurals: 1 should use _one', () => {
    assert.strictEqual(i18n.t('cart.itemCount', {count: 1}, 'de'), '1 Artikel');
});

console.log(`\nTests completed: ${passed} passed, ${failed} failed.`);
if (failed > 0) process.exit(1);
EOF

# Set ownership
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
echo "Starting VSCode..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR" &
sleep 5

# Ensure window is visible and maximized
WID=$(DISPLAY=:1 wmctrl -l | grep -i 'Visual Studio Code' | awk '{print $1; exit}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null
fi

# Take initial screenshot showing the environment
sleep 2
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task Setup Complete ==="