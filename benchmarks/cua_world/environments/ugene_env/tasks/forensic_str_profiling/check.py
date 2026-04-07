import json

metadata = {
    "data_source": "NCBI GenBank: D13S317 microsatellite (MH167239, 206bp), vWA/VWF gene (M25858.1, 5285bp), TH01/tyrosine hydroxylase (D00269, 2838bp) - real CODIS STR locus sequences",
    "occupation": "Forensic DNA Analyst",
    "industry": "Criminal Justice / Forensic Science",
    "difficulty": "very_hard",
    "target_loci": ["D13S317", "vWA", "TH01"],
    "expected_outputs": [
      "~/UGENE_Data/forensic/results/D13S317_annotated.gb",
      "~/UGENE_Data/forensic/results/vWA_annotated.gb",
      "~/UGENE_Data/forensic/results/TH01_annotated.gb",
      "~/UGENE_Data/forensic/results/str_profile_report.txt"
    ]
}
print(json.dumps(metadata, indent=2))
