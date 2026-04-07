import sqlite3
import os

gpkg_path = "/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/examples/qfield_env/data/stream_crossing_aquatic_passage_audit.gpkg"
conn = sqlite3.connect(gpkg_path)
c = conn.cursor()
c.execute("SELECT COUNT(*) FROM stream_crossings")
count = c.fetchone()[0]
print(f"Total stream crossings: {count}")
c.execute("SELECT crossing_id, aop_status, outlet_drop_cm, outlet_width_m, bankfull_width_m, slope_pct, structure_type, substrate_type FROM stream_crossings LIMIT 15")
print("Sample rows:")
for r in c.fetchall():
    print(r)
conn.close()
