import sqlite3
import struct

def parse_gpkg_point(blob):
    try:
        flags = blob[3]
        envelope_indicator = (flags >> 1) & 0b111
        envelope_sizes = {0:0, 1:32, 2:48, 3:48, 4:64}
        offset = 8 + envelope_sizes.get(envelope_indicator, 0)
        wkb_bytes = blob[offset:]
        endian_char = '<' if wkb_bytes[0] == 1 else '>'
        x, y = struct.unpack(endian_char + 'dd', wkb_bytes[5:21])
        return y, x
    except:
        return None, None

db_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg"
conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT name FROM world_capitals WHERE name LIKE '%Sing%'")
for r in cursor.fetchall():
    print(f"Found: {r[0]}")
    
cursor.execute("SELECT name FROM world_capitals")
all_names = [r[0] for r in cursor.fetchall()]
print(f"All names count: {len(all_names)}")
if 'Singapore' in all_names: print("Singapore IS in the list")
