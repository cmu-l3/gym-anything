#!/bin/bash
set -e
source /workspace/scripts/task_utils.sh

echo "=== Exporting BME280 Embedded Driver Result ==="

WORKSPACE_DIR="/home/ga/workspace/bme280_driver"
RESULT_FILE="/tmp/task_result.json"

# Focus VSCode and save all open files
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# ─────────────────────────────────────────────────────────────
# 1. Provide HIDDEN logic-analyzer mock to test robustness
# ─────────────────────────────────────────────────────────────
# This overwrites the user's mock to prevent hardcoding prints.
cat > "$WORKSPACE_DIR/src/hidden_i2c_mock.c" << 'EOF'
#include "i2c_mock.h"
#include <string.h>

static uint8_t virtual_regs[256];
static uint8_t ctrl_hum_written = 0;

void i2c_mock_init(void) {
    memset(virtual_regs, 0, 256);
    virtual_regs[0xD0] = 0x60; /* BME280 ID */

    /* Hidden Mock calibration (Modified from default to break hardcoding) */
    virtual_regs[0x88] = 0x70; virtual_regs[0x89] = 0x6B;
    virtual_regs[0x8A] = 0x43; virtual_regs[0x8B] = 0x67;
    virtual_regs[0x8C] = 0x18; virtual_regs[0x8D] = 0xFC;
    virtual_regs[0x8E] = 0x7D; virtual_regs[0x8F] = 0x8E;
    
    /* dig_P2 = -15000 (0xC568). If read as unsigned it's +50536 */
    virtual_regs[0x90] = 0x68; virtual_regs[0x91] = 0xC5; 
    
    virtual_regs[0x92] = 0xD0; virtual_regs[0x93] = 0x0B;
    virtual_regs[0x94] = 0x27; virtual_regs[0x95] = 0x0B;
    virtual_regs[0x96] = 0x8C; virtual_regs[0x97] = 0x00;
    virtual_regs[0x98] = 0xF9; virtual_regs[0x99] = 0xFF;
    virtual_regs[0x9A] = 0x8C; virtual_regs[0x9B] = 0x3C;
    virtual_regs[0x9C] = 0xF8; virtual_regs[0x9D] = 0xC6;
    virtual_regs[0x9E] = 0x70; virtual_regs[0x9F] = 0x17;
    virtual_regs[0xA1] = 0x4B;
    virtual_regs[0xE1] = 0x68; virtual_regs[0xE2] = 0x01;
    virtual_regs[0xE3] = 0x00;
    virtual_regs[0xE4] = 0x13; virtual_regs[0xE5] = 0x0B;
    virtual_regs[0xE6] = 0x03;
    virtual_regs[0xE7] = 0x1E;

    /* Hidden Raw data (Cold, high pressure, high humidity) */
    virtual_regs[0xF7] = 0x51; virtual_regs[0xF8] = 0xA0; virtual_regs[0xF9] = 0x00;
    virtual_regs[0xFA] = 0x80; virtual_regs[0xFB] = 0x00; virtual_regs[0xFC] = 0x00;
    virtual_regs[0xFD] = 0x00; virtual_regs[0xFE] = 0x00; /* Stale logic */
}

void i2c_read_regs(uint8_t reg, uint8_t *data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) data[i] = virtual_regs[(reg + i) % 256];
}

void i2c_write_regs(uint8_t reg, uint8_t *data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) {
        uint8_t addr = (reg + i) % 256;
        virtual_regs[addr] = data[i];
        if (addr == 0xF2) ctrl_hum_written = 1;
        if (addr == 0xF4) {
            if (ctrl_hum_written) {
                virtual_regs[0xFD] = 0x7F; /* Hum MSB */
                virtual_regs[0xFE] = 0x00; /* Hum LSB */
            }
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 2. Compile and run AGENT'S code against hidden mock
# ─────────────────────────────────────────────────────────────
echo "Compiling agent's code..."
cd "$WORKSPACE_DIR"
rm -f src/*.o bme280_test

# Compile agent output
gcc -Wall -Iinc -c src/main.c -o src/main.o || true
gcc -Wall -Iinc -c src/bme280.c -o src/bme280.o || true
gcc -Wall -Iinc -c src/hidden_i2c_mock.c -o src/i2c_mock.o || true
gcc -o bme280_test src/main.o src/bme280.o src/i2c_mock.o -lm 2>/dev/null || true

if [ -f "bme280_test" ]; then
    ./bme280_test > /tmp/agent_out.json 2>/dev/null || echo "{\"error\": \"Execution failed or segfaulted\"}" > /tmp/agent_out.json
else
    echo "{\"error\": \"Compilation failed\"}" > /tmp/agent_out.json
fi

# ─────────────────────────────────────────────────────────────
# 3. Create, compile, and run PERFECT truth code against mock
# ─────────────────────────────────────────────────────────────
cat > /tmp/perfect_bme280.h << 'EOF'
#include <stdint.h>
struct bme280_calib_data {
    uint16_t dig_T1; int16_t dig_T2; int16_t dig_T3;
    uint16_t dig_P1; int16_t dig_P2; int16_t dig_P3; int16_t dig_P4;
    int16_t dig_P5; int16_t dig_P6; int16_t dig_P7; int16_t dig_P8; int16_t dig_P9;
    uint8_t  dig_H1; int16_t dig_H2; uint8_t  dig_H3; int16_t dig_H4; int16_t dig_H5; int8_t dig_H6;
};
int bme280_init(void);
int bme280_read_data(float *temp, float *press, float *hum);
EOF

cat > /tmp/perfect_bme280.c << 'EOF'
#include "perfect_bme280.h"
#include "i2c_mock.h"

static struct bme280_calib_data calib;
static int32_t t_fine;

int bme280_init(void) {
    uint8_t id = 0; i2c_read_regs(0xD0, &id, 1);
    if (id != 0x60) return -1;
    uint8_t buf[26]; i2c_read_regs(0x88, buf, 26);
    calib.dig_T1 = (buf[1] << 8) | buf[0]; calib.dig_T2 = (buf[3] << 8) | buf[2]; calib.dig_T3 = (buf[5] << 8) | buf[4];
    calib.dig_P1 = (buf[7] << 8) | buf[6]; calib.dig_P2 = (buf[9] << 8) | buf[8]; calib.dig_P3 = (buf[11] << 8) | buf[10];
    calib.dig_P4 = (buf[13] << 8) | buf[12]; calib.dig_P5 = (buf[15] << 8) | buf[14]; calib.dig_P6 = (buf[17] << 8) | buf[16];
    calib.dig_P7 = (buf[19] << 8) | buf[18]; calib.dig_P8 = (buf[21] << 8) | buf[20]; calib.dig_P9 = (buf[23] << 8) | buf[22];
    uint8_t h1; i2c_read_regs(0xA1, &h1, 1); calib.dig_H1 = h1;
    uint8_t hbuf[7]; i2c_read_regs(0xE1, hbuf, 7);
    calib.dig_H2 = (hbuf[1] << 8) | hbuf[0]; calib.dig_H3 = hbuf[2];
    calib.dig_H4 = (hbuf[3] << 4) | (hbuf[4] & 0x0F); calib.dig_H5 = (hbuf[5] << 4) | (hbuf[4] >> 4); calib.dig_H6 = hbuf[6];

    uint8_t ctrl_meas = 0x27, ctrl_hum = 0x01;
    i2c_write_regs(0xF2, &ctrl_hum, 1);
    i2c_write_regs(0xF4, &ctrl_meas, 1);
    return 0;
}

int bme280_read_data(float *temp, float *press, float *hum) {
    uint8_t data[8]; i2c_read_regs(0xF7, data, 8);
    int32_t raw_press = (data[0] << 12) | (data[1] << 4) | (data[2] >> 4);
    int32_t raw_temp = (data[3] << 12) | (data[4] << 4) | (data[5] >> 4);
    int32_t raw_hum = (data[6] << 8) | data[7];

    int32_t var1 = ((((raw_temp >> 3) - ((int32_t)calib.dig_T1 << 1))) * ((int32_t)calib.dig_T2)) >> 11;
    int32_t var2 = (((((raw_temp >> 4) - ((int32_t)calib.dig_T1)) * ((raw_temp >> 4) - ((int32_t)calib.dig_T1))) >> 12) * ((int32_t)calib.dig_T3)) >> 14;
    t_fine = var1 + var2; *temp = ((t_fine * 5 + 128) >> 8) / 100.0f;

    int64_t p_var1 = ((int64_t)t_fine) - 128000;
    int64_t p_var2 = p_var1 * p_var1 * (int64_t)calib.dig_P6;
    p_var2 = p_var2 + ((p_var1 * (int64_t)calib.dig_P5) << 17) + (((int64_t)calib.dig_P4) << 35);
    p_var1 = ((p_var1 * p_var1 * (int64_t)calib.dig_P3) >> 8) + ((p_var1 * (int64_t)calib.dig_P2) << 12);
    p_var1 = (((((int64_t)1) << 47) + p_var1)) * ((int64_t)calib.dig_P1) >> 33;
    if (p_var1 == 0) { *press = 0; }
    else {
        int64_t p = 1048576 - raw_press;
        p = (((p << 31) - p_var2) * 3125) / p_var1;
        int64_t pv1 = (((int64_t)calib.dig_P9) * (p >> 13) * (p >> 13)) >> 25;
        int64_t pv2 = (((int64_t)calib.dig_P8) * p) >> 19;
        p = ((p + pv1 + pv2) >> 8) + (((int64_t)calib.dig_P7) << 4);
        *press = (float)p / 25600.0f;
    }

    int32_t v_x1_u32r = (t_fine - ((int32_t)76800));
    v_x1_u32r = (((((raw_hum << 14) - (((int32_t)calib.dig_H4) << 20) - (((int32_t)calib.dig_H5) * v_x1_u32r)) + ((int32_t)16384)) >> 15) * (((((((v_x1_u32r * ((int32_t)calib.dig_H6)) >> 10) * (((v_x1_u32r * ((int32_t)calib.dig_H3)) >> 11) + ((int32_t)32768))) >> 10) + ((int32_t)2097152)) * ((int32_t)calib.dig_H2) + 8192) >> 14));
    v_x1_u32r = (v_x1_u32r - (((((v_x1_u32r >> 15) * (v_x1_u32r >> 15)) >> 7) * ((int32_t)calib.dig_H1)) >> 4));
    v_x1_u32r = (v_x1_u32r < 0 ? 0 : v_x1_u32r);
    *hum = (float)(v_x1_u32r >> 12) / 1024.0f;
    return 0;
}
EOF

cat > /tmp/main_perfect.c << 'EOF'
#include "perfect_bme280.h"
#include "i2c_mock.h"
#include <stdio.h>
int main(void) {
    i2c_mock_init();
    if (bme280_init() != 0) { printf("{\"error\": \"Init failed\"}\n"); return 1; }
    float t=0, p=0, h=0; bme280_read_data(&t, &p, &h);
    printf("{\"temperature\": %.2f, \"pressure\": %.2f, \"humidity\": %.2f}\n", t, p, h);
    return 0;
}
EOF

cd /tmp
gcc -Wall -I"$WORKSPACE_DIR/inc" -c main_perfect.c -o main_perfect.o
gcc -Wall -I"$WORKSPACE_DIR/inc" -c perfect_bme280.c -o perfect_bme280.o
gcc -o perfect_test main_perfect.o perfect_bme280.o "$WORKSPACE_DIR/src/i2c_mock.o" -lm
./perfect_test > /tmp/truth_out.json

# ─────────────────────────────────────────────────────────────
# 4. Package Results
# ─────────────────────────────────────────────────────────────
python3 << PYEXPORT
import json, os

result = {}
try:
    with open("/tmp/agent_out.json", "r") as f:
        result["agent_out"] = json.load(f)
except Exception:
    result["agent_out"] = {"error": "Invalid JSON or execution failed"}

try:
    with open("/tmp/truth_out.json", "r") as f:
        result["truth_out"] = json.load(f)
except Exception:
    result["truth_out"] = {}

# Also include the agent's source code for manual/regex checks if necessary
try:
    with open("$WORKSPACE_DIR/src/bme280.c", "r") as f:
        result["bme280_c"] = f.read()
except Exception:
    result["bme280_c"] = ""

with open("$RESULT_FILE", "w") as out:
    json.dump(result, out, indent=2)
PYEXPORT

echo "=== Export Complete ==="