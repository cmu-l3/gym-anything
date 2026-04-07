import binascii
import struct

hex_str = '47500001E61000000101000000295C8FC2F5A062405839B4C8769E41C0'
b = binascii.unhexlify(hex_str)

# GeoPackage header is: 
# magic (2): GP
# version (1): 00
# flags (1): 01
# srs_id (4): E6100000 (little endian 000010E6 -> 4326)
# envelope (depends on flags)

# For flag 01, envelope is empty. Header length is 8.
geom_type = struct.unpack('<I', b[8:12])[0]
x, y = struct.unpack('<dd', b[12:28])
print(f"X (Lon): {x}, Y (Lat): {y}")
