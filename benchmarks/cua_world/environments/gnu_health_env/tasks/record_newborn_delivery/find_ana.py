import gzip
import re

dump_path = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/gnuhealth-50-demo.sql.gz'

# Find party_party id for Ana Isabel Betz
party_id = None
patient_id = None
occupation_id = None
puid = None

with gzip.open(dump_path, 'rt', errors='replace') as f:
    copy_party = False
    copy_patient = False
    copy_occupation = False
    
    for line in f:
        if line.startswith('COPY public.party_party '):
            copy_party = True
            print(line.strip())
            continue
        elif line.startswith('\.'):
            copy_party = False
            copy_patient = False
            copy_occupation = False
        
        if copy_party:
            if 'Ana Isabel' in line and 'Betz' in line:
                fields = line.split('	')
                party_id = fields[0]
                print(f"Found party: {fields[0]} - {fields[15]} - {fields[16]}")
                
        if line.startswith('COPY public.gnuhealth_patient '):
            copy_patient = True
            print(line.strip())
            continue
            
        if copy_patient:
            fields = line.split('	')
            # party is usually one of the fields, let's just search the party_id if we have it
            if party_id and len(fields) > 5:
                # Need to find which column is party. Let's look at schema
                # (id, ..., name, party, dob)
                # I'll just check if party_id is in fields
                pass

with gzip.open(dump_path, 'rt', errors='replace') as f:
    for line in f:
        if line.startswith('COPY public.gnuhealth_patient '):
            schema = line.strip()
            print("patient schema:", schema)
            break

with gzip.open(dump_path, 'rt', errors='replace') as f:
    for line in f:
        if line.startswith('COPY public.gnuhealth_occupation '):
            schema = line.strip()
            print("occupation schema:", schema)
            break
