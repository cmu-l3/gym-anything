#!/usr/bin/env python3
"""Convert patient CSV to Care2x care_person SQL INSERT statements.

Patient data sourced from:
- First names: US Social Security Administration (SSA) most popular baby names
- Last names: US Census Bureau 2010 most common surnames
- Cities/Zip codes: Real US cities with correct zip codes
- Area codes: Real US telephone area codes matching cities

CSV columns:
  FIRST, LAST, BIRTHDATE, GENDER, MARITAL, ADDRESS_NUM, ADDRESS_STREET,
  CITY, STATE, ZIP, PHONE, EMAIL

Care2x care_person key columns:
  pid (auto), date_reg, name_first, name_last, date_birth, sex, title,
  civil_status, addr_str, addr_str_nr, addr_zip, phone_1_nr, email,
  blood_group, status, modify_id, create_id
"""

import csv
import sys
import random
from datetime import datetime


def escape_sql(val):
    if val is None:
        return "NULL"
    val = str(val).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{val}'"


def gender_to_sex(gender):
    return 'm' if gender == 'M' else 'f'


def marital_to_civil(marital):
    return {'M': 'married', 'S': 'single', 'D': 'divorced', 'W': 'widowed'}.get(marital, 'single')


# Blood group distribution based on real US population frequencies
# Source: Stanford Blood Center / American Red Cross
BLOOD_GROUPS_WEIGHTED = [
    ('O+', 38), ('O-', 7), ('A+', 34), ('A-', 6),
    ('B+', 9), ('B-', 2), ('AB', 3), ('AB', 1)
]


def weighted_blood_group(rng):
    total = sum(w for _, w in BLOOD_GROUPS_WEIGHTED)
    r = rng.randint(1, total)
    cumulative = 0
    for bg, w in BLOOD_GROUPS_WEIGHTED:
        cumulative += w
        if r <= cumulative:
            return bg
    return 'O+'


def convert_to_care2x(csv_path, sql_path):
    rng = random.Random(42)
    now = datetime.now().strftime('%Y-%m-%d %H:%M:%S')

    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        patients = list(reader)

    with open(sql_path, 'w') as out:
        out.write("-- Care2x patient seed data\n")
        out.write(f"-- Source: US Census surnames, SSA baby names, real US cities/zips\n")
        out.write(f"-- Generated: {now}\n")
        out.write(f"-- Patients: {len(patients)}\n\n")

        for p in patients:
            first = p.get('FIRST', '').replace("'", "\\'")
            last = p.get('LAST', '').replace("'", "\\'")
            dob = p.get('BIRTHDATE', '1990-01-01')
            sex = gender_to_sex(p.get('GENDER', 'M'))
            civil = marital_to_civil(p.get('MARITAL', 'S'))
            addr_num = p.get('ADDRESS_NUM', '')
            addr_street = p.get('ADDRESS_STREET', '').replace("'", "\\'")
            zipcode = p.get('ZIP', '')
            phone = p.get('PHONE', '')
            email = p.get('EMAIL', '').replace("'", "\\'")
            blood = weighted_blood_group(rng)
            title = 'Mr' if sex == 'm' else 'Ms'

            out.write(
                f"INSERT INTO care_person "
                f"(date_reg, name_first, name_last, "
                f"date_birth, sex, title, civil_status, "
                f"addr_str, addr_str_nr, addr_zip, "
                f"phone_1_nr, email, blood_group, "
                f"status, modify_id, modify_time, create_id, create_time) "
                f"VALUES ("
                f"{escape_sql(now)}, "
                f"{escape_sql(first)}, "
                f"{escape_sql(last)}, "
                f"{escape_sql(dob)}, "
                f"{escape_sql(sex)}, "
                f"{escape_sql(title)}, "
                f"{escape_sql(civil)}, "
                f"{escape_sql(addr_street)}, "
                f"{escape_sql(addr_num)}, "
                f"{escape_sql(zipcode)}, "
                f"{escape_sql(phone)}, "
                f"{escape_sql(email)}, "
                f"{escape_sql(blood)}, "
                f"'normal', 'admin', {escape_sql(now)}, 'admin', {escape_sql(now)}"
                f");\n"
            )

        out.write(f"\n-- Seed data complete: {len(patients)} patients inserted\n")

    print(f"Generated {len(patients)} patient INSERT statements in {sql_path}")


if __name__ == '__main__':
    if len(sys.argv) < 3:
        print("Usage: seed_care2x.py <csv> <output_sql>")
        sys.exit(1)
    convert_to_care2x(sys.argv[1], sys.argv[2])
