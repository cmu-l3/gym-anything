import sqlite3
import struct

conn = sqlite3.connect('/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/world_survey.gpkg')
cur = conn.cursor()
cur.execute("SELECT observer_name, hex(geom) FROM field_observations")
rows = cur.fetchall()

def decode_gpkg_geom(hex_str):
    import binascii
    b = binascii.unhexlify(hex_str)
    # GeoPackage binary header
    magic = b[0:2]
    version = b[2]
    flags = b[3]
    srs_id = struct.unpack('<i', b[4:8])[0]
    envelope_type = (flags & 0x0E) >> 1
    offset = 8
    if envelope_type == 1: offset += 32
    elif envelope_type == 2: offset += 48
    elif envelope_type == 3: offset += 48
    elif envelope_type == 4: offset += 64
    
    # WKB part
    byte_order = b[offset]
    endian = '<' if byte_order == 1 else '>'
    geom_type = struct.unpack(endian + 'I', b[offset+1:offset+5])[0]
    x, y = struct.unpack(endian + 'dd', b[offset+5:offset+21])
    return x, y

for name, hex_str in rows:
    x, y = decode_gpkg_geom(hex_str)
    print(f"{name}: Lon {x}, Lat {y}")
