#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up BME280 Embedded Driver Task ==="

WORKSPACE_DIR="/home/ga/workspace/bme280_driver"
sudo -u ga mkdir -p "$WORKSPACE_DIR/inc"
sudo -u ga mkdir -p "$WORKSPACE_DIR/src"
sudo -u ga mkdir -p "$WORKSPACE_DIR/datasheet"

cd "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 1. Provide Datasheet Excerpt
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/datasheet/BST-BME280-DS002_Excerpt.txt" << 'EOF'
BOSCH SENSORTEC BME280 DATASHEET EXCERPT (v1.6)

1. DEVICE ID
Register Address: 0xD0
Expected Value: 0x60 (Note: BMP280 is 0x58)

2. REGISTER MAP
0xF2 : ctrl_hum  (Humidity Control)
0xF4 : ctrl_meas (Temperature & Pressure Control)
0xF7...0xFC : Raw Data Registers (Press MSB, LSB, XLSB; Temp MSB, LSB, XLSB)
0xFD...0xFE : Raw Data Registers (Hum MSB, LSB)

3. REGISTER WRITE SEQUENCE
IMPORTANT: Changes to 'ctrl_hum' (0xF2) only become effective after a write operation to 'ctrl_meas' (0xF4). Therefore, 'ctrl_hum' MUST be written BEFORE 'ctrl_meas' during initialization.

4. RAW DATA PARSING
Pressure and Temperature data are 20-bit values spread across 3 registers (MSB, LSB, XLSB).
They must be combined as follows:
    raw_value = (MSB << 12) | (LSB << 4) | (XLSB >> 4)

Humidity data is a 16-bit value spread across 2 registers (MSB, LSB).
    raw_hum = (MSB << 8) | LSB

5. CALIBRATION DATA
Data Type Definitions:
T1: unsigned 16-bit    T2: signed 16-bit      T3: signed 16-bit
P1: unsigned 16-bit    P2: signed 16-bit      P3: signed 16-bit
P4: signed 16-bit      P5: signed 16-bit      P6: signed 16-bit
P7: signed 16-bit      P8: signed 16-bit      P9: signed 16-bit
H1: unsigned 8-bit     H2: signed 16-bit      H3: unsigned 8-bit
H4: signed 16-bit      H5: signed 16-bit      H6: signed 8-bit
EOF

# ─────────────────────────────────────────────────────────────
# 2. bme280.h (BUG 3: dig_P2/P3 are uint16_t instead of int16_t)
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/inc/bme280.h" << 'EOF'
#ifndef BME280_H
#define BME280_H

#include <stdint.h>

struct bme280_calib_data {
    uint16_t dig_T1;
    int16_t  dig_T2;
    int16_t  dig_T3;

    uint16_t dig_P1;
    uint16_t dig_P2; /* BUG INJECTED */
    uint16_t dig_P3; /* BUG INJECTED */
    int16_t  dig_P4;
    int16_t  dig_P5;
    int16_t  dig_P6;
    int16_t  dig_P7;
    int16_t  dig_P8;
    int16_t  dig_P9;

    uint8_t  dig_H1;
    int16_t  dig_H2;
    uint8_t  dig_H3;
    int16_t  dig_H4;
    int16_t  dig_H5;
    int8_t   dig_H6;
};

int bme280_init(void);
int bme280_read_data(float *temp, float *press, float *hum);

#endif
EOF

# ─────────────────────────────────────────────────────────────
# 3. bme280.c (BUGS 1, 2, 4, 5)
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/src/bme280.c" << 'EOF'
#include "bme280.h"
#include "i2c_mock.h"

static struct bme280_calib_data calib;
static int32_t t_fine;

int bme280_init(void) {
    uint8_t id = 0;
    i2c_read_regs(0xD0, &id, 1);
    
    /* Check device ID */
    if (id != 0x58) return -1;

    /* Read calibration data */
    uint8_t buf[26];
    i2c_read_regs(0x88, buf, 26);
    calib.dig_T1 = (buf[1] << 8) | buf[0];
    calib.dig_T2 = (buf[3] << 8) | buf[2];
    calib.dig_T3 = (buf[5] << 8) | buf[4];
    calib.dig_P1 = (buf[7] << 8) | buf[6];
    calib.dig_P2 = (buf[9] << 8) | buf[8];
    calib.dig_P3 = (buf[11] << 8) | buf[10];
    calib.dig_P4 = (buf[13] << 8) | buf[12];
    calib.dig_P5 = (buf[15] << 8) | buf[14];
    calib.dig_P6 = (buf[17] << 8) | buf[16];
    calib.dig_P7 = (buf[19] << 8) | buf[18];
    calib.dig_P8 = (buf[21] << 8) | buf[20];
    calib.dig_P9 = (buf[23] << 8) | buf[22];

    uint8_t h1;
    i2c_read_regs(0xA1, &h1, 1);
    calib.dig_H1 = h1;

    uint8_t hbuf[7];
    i2c_read_regs(0xE1, hbuf, 7);
    calib.dig_H2 = (hbuf[1] << 8) | hbuf[0];
    calib.dig_H3 = hbuf[2];
    calib.dig_H4 = (hbuf[3] << 4) | (hbuf[4] & 0x0F);
    calib.dig_H5 = (hbuf[5] << 4) | (hbuf[4] >> 4);
    calib.dig_H6 = hbuf[6];

    /* Setup control registers */
    uint8_t ctrl_meas = 0x27; /* Temp x1, Press x1, Normal mode */
    uint8_t ctrl_hum = 0x01;  /* Hum x1 */

    /* Apply configuration */
    i2c_write_regs(0xF4, &ctrl_meas, 1);
    i2c_write_regs(0xF2, &ctrl_hum, 1);

    return 0;
}

int bme280_read_data(float *temp, float *press, float *hum) {
    uint8_t data[8];
    i2c_read_regs(0xF7, data, 8);

    /* Parse raw data */
    int32_t raw_press = data[0] << 12 + data[1] << 4 + data[2] >> 4;
    int32_t raw_temp  = data[3] << 12 + data[4] << 4 + data[5] >> 4;
    int32_t raw_hum   = (data[7] << 8) | data[6];

    /* Bosch Sensortec Compensation Formulas */
    int32_t var1, var2, T;
    var1 = ((((raw_temp >> 3) - ((int32_t)calib.dig_T1 << 1))) * ((int32_t)calib.dig_T2)) >> 11;
    var2 = (((((raw_temp >> 4) - ((int32_t)calib.dig_T1)) * ((raw_temp >> 4) - ((int32_t)calib.dig_T1))) >> 12) * ((int32_t)calib.dig_T3)) >> 14;
    t_fine = var1 + var2;
    T = (t_fine * 5 + 128) >> 8;
    *temp = T / 100.0f;

    int64_t p_var1, p_var2, p;
    p_var1 = ((int64_t)t_fine) - 128000;
    p_var2 = p_var1 * p_var1 * (int64_t)calib.dig_P6;
    p_var2 = p_var2 + ((p_var1 * (int64_t)calib.dig_P5) << 17);
    p_var2 = p_var2 + (((int64_t)calib.dig_P4) << 35);
    p_var1 = ((p_var1 * p_var1 * (int64_t)calib.dig_P3) >> 8) + ((p_var1 * (int64_t)calib.dig_P2) << 12);
    p_var1 = (((((int64_t)1) << 47) + p_var1)) * ((int64_t)calib.dig_P1) >> 33;
    if (p_var1 == 0) { *press = 0; }
    else {
        p = 1048576 - raw_press;
        p = (((p << 31) - p_var2) * 3125) / p_var1;
        p_var1 = (((int64_t)calib.dig_P9) * (p >> 13) * (p >> 13)) >> 25;
        p_var2 = (((int64_t)calib.dig_P8) * p) >> 19;
        p = ((p + p_var1 + p_var2) >> 8) + (((int64_t)calib.dig_P7) << 4);
        *press = (float)p / 256.0f / 100.0f;
    }

    int32_t v_x1_u32r;
    v_x1_u32r = (t_fine - ((int32_t)76800));
    v_x1_u32r = (((((raw_hum << 14) - (((int32_t)calib.dig_H4) << 20) - (((int32_t)calib.dig_H5) * v_x1_u32r)) + ((int32_t)16384)) >> 15) * (((((((v_x1_u32r * ((int32_t)calib.dig_H6)) >> 10) * (((v_x1_u32r * ((int32_t)calib.dig_H3)) >> 11) + ((int32_t)32768))) >> 10) + ((int32_t)2097152)) * ((int32_t)calib.dig_H2) + 8192) >> 14));
    v_x1_u32r = (v_x1_u32r - (((((v_x1_u32r >> 15) * (v_x1_u32r >> 15)) >> 7) * ((int32_t)calib.dig_H1)) >> 4));
    v_x1_u32r = (v_x1_u32r < 0 ? 0 : v_x1_u32r);
    v_x1_u32r = (v_x1_u32r > 419430400 ? 419430400 : v_x1_u32r);
    *hum = (float)(v_x1_u32r >> 12) / 1024.0f;

    return 0;
}
EOF

# ─────────────────────────────────────────────────────────────
# 4. i2c_mock.h & i2c_mock.c
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/inc/i2c_mock.h" << 'EOF'
#ifndef I2C_MOCK_H
#define I2C_MOCK_H

#include <stdint.h>

void i2c_read_regs(uint8_t reg, uint8_t *data, uint16_t len);
void i2c_write_regs(uint8_t reg, uint8_t *data, uint16_t len);
void i2c_mock_init(void);

#endif
EOF

sudo -u ga cat > "$WORKSPACE_DIR/src/i2c_mock.c" << 'EOF'
#include "i2c_mock.h"
#include <string.h>

static uint8_t virtual_regs[256];
static uint8_t ctrl_hum_written = 0;

void i2c_mock_init(void) {
    memset(virtual_regs, 0, 256);
    virtual_regs[0xD0] = 0x60; /* BME280 ID */

    /* Mock calibration data */
    virtual_regs[0x88] = 0x70; virtual_regs[0x89] = 0x6B;
    virtual_regs[0x8A] = 0x43; virtual_regs[0x8B] = 0x67;
    virtual_regs[0x8C] = 0x18; virtual_regs[0x8D] = 0xFC;
    virtual_regs[0x8E] = 0x7D; virtual_regs[0x8F] = 0x8E;
    virtual_regs[0x90] = 0x43; virtual_regs[0x91] = 0xD6;
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

    /* Raw data (Press, Temp, Hum) */
    virtual_regs[0xF7] = 0x4E; virtual_regs[0xF8] = 0x20; virtual_regs[0xF9] = 0x00;
    virtual_regs[0xFA] = 0x7D; virtual_regs[0xFB] = 0x00; virtual_regs[0xFC] = 0x00;
    virtual_regs[0xFD] = 0x00; virtual_regs[0xFE] = 0x00; /* Stale logic */
}

void i2c_read_regs(uint8_t reg, uint8_t *data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) {
        data[i] = virtual_regs[(reg + i) % 256];
    }
}

void i2c_write_regs(uint8_t reg, uint8_t *data, uint16_t len) {
    for (uint16_t i = 0; i < len; i++) {
        uint8_t addr = (reg + i) % 256;
        virtual_regs[addr] = data[i];

        if (addr == 0xF2) {
            ctrl_hum_written = 1;
        }
        if (addr == 0xF4) {
            /* Hardware constraint: ctrl_hum only updates if written BEFORE ctrl_meas */
            if (ctrl_hum_written) {
                virtual_regs[0xFD] = 0x61;
                virtual_regs[0xFE] = 0xA8;
            }
        }
    }
}
EOF

# ─────────────────────────────────────────────────────────────
# 5. main.c & Makefile
# ─────────────────────────────────────────────────────────────
sudo -u ga cat > "$WORKSPACE_DIR/src/main.c" << 'EOF'
#include "bme280.h"
#include "i2c_mock.h"
#include <stdio.h>

int main(void) {
    i2c_mock_init();

    if (bme280_init() != 0) {
        printf("{\"error\": \"Initialization failed (Device ID mismatch)\"}\n");
        return 1;
    }

    float t = 0, p = 0, h = 0;
    bme280_read_data(&t, &p, &h);

    printf("{\"temperature\": %.2f, \"pressure\": %.2f, \"humidity\": %.2f}\n", t, p, h);
    return 0;
}
EOF

sudo -u ga cat > "$WORKSPACE_DIR/Makefile" << 'EOF'
CC = gcc
CFLAGS = -Wall -Werror -Iinc -g
OBJ = src/main.o src/bme280.o src/i2c_mock.o
EXEC = bme280_test

all: $(EXEC)

$(EXEC): $(OBJ)
	$(CC) $(CFLAGS) -o $@ $^

%.o: %.c
	$(CC) $(CFLAGS) -c $< -o $@

test: $(EXEC)
	./$(EXEC)

clean:
	rm -f src/*.o $(EXEC)
EOF

# Ensure all permissions are correct
chown -R ga:ga "$WORKSPACE_DIR"

# Launch VSCode
pkill -f "code" 2>/dev/null || true
sleep 1
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR/datasheet/BST-BME280-DS002_Excerpt.txt $WORKSPACE_DIR/src/bme280.c &"
sleep 5

# Focus and maximize VSCode
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="