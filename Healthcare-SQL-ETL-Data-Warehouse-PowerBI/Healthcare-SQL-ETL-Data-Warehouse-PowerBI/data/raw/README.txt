HEALTHCARE SYNTHETIC V4.6 - ALL PATIENTS AND EVENTS FICTIONAL
Seed: 20261012; annual encounter targets: {2024: 5500, 2025: 6500}; registration cohorts: {2024: 350, 2025: 450}; billing/appeals may continue into 2026.
Patients: 5,000
Providers: 120
Encounters: 12,000
Diagnoses: 15,059
Lab_Tests: 7,604
Medications: 6,894
Procedures: 11,738
Claims_and_Billing: 12,453
Denials: 1,078
Billed amount: 9,379,315.20
Paid amount: 5,970,060.49
Denied amount: 828,186.29
Unbilled encounter counts by year: {2024: 357, 2025: 625}\nUnbilled encounters have no claim row; do not equate denied claims with unbilled encounters.\nDrug NDC is 11-character TEXT (package-level). Use NDC_REFERENCE.csv for lookup provenance.
Providers retain original IDs and NPIs; department staffing is redistributed and specialties remain department-compatible.
Prescriptions are not pharmacy dispensing claims. Medical claim billed amounts exclude prescribed drug costs.
Clinical patterns are illustrative synthetic associations, not treatment guidelines or validated utilization benchmarks.
NDC listing does not establish marketing status during each historical service date.
For staging/ODS/DW, add ndc VARCHAR(11) NULL to medication tables and map in load procedures.
V4.3 regenerates all files as one set. Reset/reconcile prior synthetic warehouse loads before reimport; reused IDs can conflict with old DW records.
