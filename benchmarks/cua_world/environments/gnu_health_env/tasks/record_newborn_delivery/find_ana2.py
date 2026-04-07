import gzip

dump_path = '/compute/babel-u5-24/pranjala/gym_anything_clean/Gym-Anything_for_cmu_super_clean/gnuhealth-50-demo.sql.gz'

party_cols = "id, create_date, write_date, create_uid, write_uid, code, code_length, active, name, photo, alternative_identification, is_healthprof, insurance_company_type, internal_user, activation_date, citizenship, is_patient, is_insurance_company, ref, lastname, ethnic_group, du, unidentified, dob, is_institution, marital_status, gender, is_pharmacy, residence, is_person, education, occupation, warehouse, death_certificate, birth_certificate, deceased, name_representation, replaced_by, federation_account, fed_country, fsync, est_dob, est_years, create_target, homeless, proclaimed_ethnicity".split(", ")

occupation_id = None
with gzip.open(dump_path, 'rt', errors='replace') as f:
    copy_party = False
    for line in f:
        if line.startswith('COPY public.party_party '):
            copy_party = True
            continue
        elif line.startswith('\\.'):
            copy_party = False
            
        if copy_party:
            if 'Ana Isabel' in line and 'Betz' in line:
                fields = line.strip().split('\t')
                print("Ana Isabel Betz party row found")
                for i, (col, val) in enumerate(zip(party_cols, fields)):
                    if col == 'occupation':
                        print(f"  {col}: {val}")
                        occupation_id = val

with gzip.open(dump_path, 'rt', errors='replace') as f:
    copy_occ = False
    for line in f:
        if line.startswith('COPY public.gnuhealth_occupation '):
            copy_occ = True
            continue
        elif line.startswith('\\.'):
            copy_occ = False
            
        if copy_occ:
            fields = line.strip().split('\t')
            if fields[0] == occupation_id:
                print("Occupation row:", fields)

with gzip.open(dump_path, 'rt', errors='replace') as f:
    copy_patient = False
    for line in f:
        if line.startswith('COPY public.gnuhealth_patient '):
            copy_patient = True
            continue
        elif line.startswith('\\.'):
            copy_patient = False
            
        if copy_patient:
            fields = line.strip().split('\t')
            if len(fields) > 12 and fields[12] == '2': # party id is 2
                print("Ana patient row found!")
                for i, val in enumerate(fields):
                    if 'GNU' in str(val):
                        print(f"found GNU in field {i}: {val}")
