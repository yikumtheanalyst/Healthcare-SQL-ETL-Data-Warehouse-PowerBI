# Healthcare Claims & Clinical Data | End-to-End SQL Server ETL and Data Warehouse

> **Project status (November 22, 2026):** The SQL staging → ODS → dimensional warehouse ETL, BCP export workflow, and multi-page Power BI healthcare dashboard have been developed and published as a portfolio project. The Patient Detail model was subsequently corrected by removing obsolete `Dim_Patient_Bridge` and `Diagnosis_Detail` calculated tables and the problematic primary-diagnosis-key relationship. SQL-to-Power BI checks confirm patient history across 2024 and 2025 for tested cases. Full regression testing and production hardening remain separate tasks.

## Project overview

This project demonstrates the process of taking multiple related healthcare source files and building a structured, auditable SQL Server data pipeline suitable for analysis and reporting.

The project began with **exploratory investigation**, not with a prebuilt data model. I first reviewed the available tables and their fields, searched for common identifiers, investigated how the records were connected, and determined the order in which data should logically be processed. That investigation guided the design of staging, operational data store (ODS), dimensional data warehouse (DW), and eventual reporting layers.

The result is a practical ETL case study: not just loading data, but finding and resolving the data-quality, business-key, cardinality, and historical-dimension issues that emerge during development.

**Core technologies:** Microsoft SQL Server, T-SQL, stored procedures, SQL Server Management Studio (SSMS), Excel for source inspection and reconciliation, and Power BI for the implemented reporting and validation layer.

**Data provenance update (November 2026):** The project was traced to a publicly listed synthetic California hospital dataset: [CA Hospital Dataset Q1 2025](https://www.kaggle.com/datasets/rajkumarpadmanabhan/ca-hospital-dataset-q1-2025) by rajkumarpadmanabhan. The project subsequently modified/extended the data for 2024–2025 analysis. Verify the exact downloaded version, file licensing, and redistribution permissions before uploading data. No claim is made that these are real patients.

---

## 1. Project objectives

1. Investigate nine related healthcare source datasets and infer their relationships from the data itself.
2. Preserve raw input files and create reproducible transformations into SQL Server.
3. Separate source ingestion, standardization, and analytical modeling into **staging (`stg`)**, **ODS (`ods`)**, and **data warehouse (`dw`)** layers in `ETL_DB`.
4. Implement the appropriate loading behavior for each destination: SCD Type 2, Type 1 upsert, lookup maintenance, or incremental fact upsert.
5. Resolve source-data defects without silently losing valid records.
6. Validate counts, business-key uniqueness, join cardinality, referential integrity, and financial values.
7. Log ETL execution results and failures for troubleshooting.
8. Use the curated data to develop healthcare operational, clinical, provider, and financial analytics in Power BI.

## 2. How the project started: discovery and initial investigation

### 2.1 Finding the data

I came across a collection of healthcare-related tables while looking for a dataset suitable for a realistic SQL ETL/data-warehouse project. The dataset used in this project has been attributed to the Kaggle source credited in the provenance note above. The exact downloaded version and transformation history should still be verified from the original files and scripts.

Instead of immediately importing the files into a reporting tool, I began by asking: **What does each table represent? How are these tables connected? What must exist before another record can exist?**

### 2.2 Inspecting the source tables

The nine source subjects identified were:

| Source subject | Purpose in the project | Representative identifiers / fields |
|---|---|---|
| Patients | Patient demographic and enrollment-related attributes | `patient_id` |
| Providers | Healthcare providers and their attributes | `provider_id`, `prescriber_id` in medication records |
| Encounters | Patient visits and episodes of care | `encounter_id`, `patient_id`, `provider_id`, `visit_date` |
| Diagnoses | Conditions documented for encounters | `diagnosis_id`, `encounter_id`, `diagnosis_code` |
| Procedures | Services performed during encounters | `procedure_id`, `encounter_id`, `provider_id` |
| Lab tests | Clinical tests associated with encounters | `lab_id`, `encounter_id`, `test_code` |
| Medications | Medications associated with encounters and prescribers | `medication_id`, `encounter_id`, `prescriber_id`, `drug_name` |
| Claims and billing | Claim records and financial amounts | `claim_id`, `billing_id`, `patient_id`, `encounter_id` |
| Claim adjudication | Denial, appeal, and adjudication details | `claim_id`, denial/appeal fields |

Names vary slightly between original files and SQL tables; for example, the implementation uses `ods.Claims_and_Billing`, `ods.Claim_Adjudication`, `ods.Lab_Tests`, and `ods.Diagnoses`.

### 2.3 Investigating keys rather than assuming them

The initial relationship analysis was driven by actual values, not simply matching column names. The investigation included:

- Checking record counts and whether key fields were null or blank.
- Counting distinct values and grouping by candidate business keys.
- Identifying one-to-many relationships: one patient can have multiple encounters; an encounter can have multiple diagnoses, medications, procedures, and lab tests.
- Checking whether IDs that *looked* unique were actually reused across different encounters or drug records.
- Looking for orphaned child records before defining warehouse joins.
- Using Excel and SQL results to compare records and understand anomalies.

Illustrative profiling queries:

```sql
-- Volume and distinct candidate identifiers
SELECT COUNT(*) AS source_rows,
       COUNT(DISTINCT encounter_id) AS distinct_encounters
FROM ods.Encounters;

-- Test whether a supposed unique ID is reused
SELECT diagnosis_id,
       COUNT(*) AS rows_found,
       COUNT(DISTINCT encounter_id) AS encounter_count
FROM ods.Diagnoses
GROUP BY diagnosis_id
HAVING COUNT(*) > 1;

-- Identify missing source-to-parent relationships
SELECT COUNT(*) AS missing_encounter_matches
FROM ods.Claims_and_Billing c
LEFT JOIN ods.Encounters e
  ON c.encounter_id = e.encounter_id
WHERE e.encounter_id IS NULL;
```

### 2.4 Establishing the logical load order

I organized the tables according to their dependencies. Patients and providers are foundational; encounters reference them; clinical records and claims depend on encounters; adjudication enriches claims.

```text
Patients ───────────┐
                    ├── Encounters ──┬── Diagnoses
Providers ──────────┘                ├── Lab tests
                                     ├── Procedures
Providers / prescribers ─────────────┤── Medications
                                     └── Claims & Billing ── Claim Adjudication
```

This is a **logical dependency map**, not a claim that every relationship is implemented as a physical foreign-key constraint. The actual warehouse also includes lookup dimensions and a date dimension.

**Lesson:** Understand the source grain and dependencies *before* designing ETL joins or enforcing uniqueness.

---

## 3. Architecture and data flow

```text
Nine healthcare source files (CSV)
             │
             ▼
       SQL ingestion
             │
             ▼
      stg.*  (staging)
      Raw/landed data
             │
       Validate, clean,
       standardize, map
             │
             ▼
      ods.*  (ODS)
      Consistent business records
             │
      Stored procedure:
      dbo.sp_from_ods_to_production
             │
             ▼
      dw.*   (warehouse)
      SCD2 dimensions / Type 1 dimensions
      Lookup dimensions / fact tables
             │
             ▼
      BI / reporting layer
      Power BI analytics and validation

Cross-cutting: run logging, load logging, row-count
reconciliation, duplicate-key and join-cardinality checks
```

### Layer responsibilities

| Layer | Purpose | Examples |
|---|---|---|
| Raw files | Preserve original source extracts for traceability | Nine source CSVs |
| `stg` | Land source data prior to standardization | Source-shaped staging tables |
| `ods` | Cleaned, standardized operational records | `ods.Patients`, `ods.Encounters`, `ods.Medications`, `ods.Claims_and_Billing` |
| `dw` | Curated analytical entities and facts | `dw.Dim_Patients`, `dw.Dim_Encounters`, `dw.Fact_Claims` |
| BI | Validation, business measures, visualization | Multi-page Power BI report developed; further regression checks remain |

The implemented ODS-to-DW procedure is **`ETL_DB.dbo.sp_from_ods_to_production`**, parameterized by `@table_name`. Each branch is responsible for its own source validation, destination changes, reconciliation, and audit outcome.

---

## 4. Warehouse modeling and grain

### 4.1 SCD Type 2: patients and providers

`dw.Dim_Patients` and `dw.Dim_Providers` maintain historical versions when tracked attributes change. Each has a surrogate key (for example, `PatientKey` or `ProviderKey`) and business identifiers (`patient_id` or `provider_id`). Relevant history columns include:

- `start_date` — version start date.
- `end_date` — version end date, null for active version.
- `active_flag` — identifies the current version.
- `run_id`, `created_datetime`, `updated_datetime` — lineage/audit metadata where defined.

The SCD2 workflow is: identify changed active records → expire previous versions → insert replacement active versions → insert completely new business IDs.

**Important limitation discovered during fact loading:** Existing dimension `start_date` values reflected warehouse load timing, while historical claim billing dates were earlier. Historical as-of joins therefore failed to resolve patient/provider keys. For the initial load, the fact join was changed to the **current active dimension version** (`active_flag = 1`). This permits initial loading but **does not reconstruct historically correct dimension attribution**. A future design should use genuine business-effective dates or a documented fact-key reassignment strategy.

### 4.2 SCD Type 1: encounter and clinical detail tables

The Type 1 approach updates changed fields **in place** and inserts new business-key combinations. It does not expire rows or create new historical versions for attribute changes.

Tables addressed with Type 1/upsert logic:

- `dw.Dim_Encounters`
- `dw.Dim_Diagnoses`
- `dw.Dim_Lab_Tests`
- `dw.Dim_Procedures`
- `dw.Dim_Medications`

The original implementation contained insert-only branches and reconciliation messages copied from SCD2. These were revised so existing changed rows are updated and new rows are inserted.

**Grain matters:** The source data proved that `diagnosis_id` alone is **not unique**. A diagnosis can appear across many encounters. The corrected diagnosis business key is **(`diagnosis_id`, `encounter_id`)**, subject to source uniqueness validation.

For medications, the tested source combination **(`medication_id`, `encounter_id`, `prescriber_id`, `drug_name`, `prescribed_date`)** returned no duplicates in the observed dataset. This is a **dataset-validated candidate key**, not proof that it is a permanent, immutable medication-order identifier. A dedicated medication-order source ID would be preferable if available.

### 4.3 Lookup dimensions

The warehouse maintains small lookup tables for:

- `dw.Dim_Claim_Status`
- `dw.Dim_Denial_Reason`
- `dw.Dim_Appeal_Status`

These should use distinct lookup values or Type 1 lookup upserts, rather than SCD2 expiration logic. Missing appeal status values were normalized to an `Unknown` lookup value. Denial-reason codes and descriptions require careful matching to avoid ambiguous descriptions or duplicate codes.

### 4.4 Fact tables

- **`dw.Fact_Claims`:** claim-level financial and adjudication measures, with patient, encounter, provider, status, reason, appeal, and date keys.
- **`dw.Fact_Medications`:** medication-related cost, resolved to medication, encounter, and provider surrogate keys.
- **`dw.Fact_Procedures`:** procedure cost, resolved to procedure and encounter keys.

Facts are incrementally upserted. Existing rows are updated **only when tracked values change**; new rows are inserted. Facts are not managed by SCD2 row-expiration logic.

---

## 5. Detailed ETL execution design

### 5.1 Source validation

For each table, the procedure checks that source rows exist and validates the intended business key. Where a fact depends on dimensions, the resolved source must retain the correct number of rows.

A duplicate-ID check is only correct when the ID is actually unique at the source grain. During development, this distinction became essential for diagnoses and medications.

### 5.2 Change detection and updates

For Type 1 and incremental facts, changed records are identified using comparisons between the current source and destination attributes. The `EXCEPT` pattern is useful because it handles `NULL` values consistently:

```sql
-- Illustrative pattern; replace keys and attributes per table
UPDATE d
SET d.some_attribute = s.some_attribute,
    d.updated_datetime = SYSDATETIME()
FROM dw.SomeDimension d
JOIN ods.SomeSource s
  ON d.business_key = s.business_key
WHERE EXISTS (
    SELECT d.some_attribute
    EXCEPT
    SELECT s.some_attribute
);
```

New records are inserted with a `NOT EXISTS` check using the **same validated business key**. Update and insert joins must be aligned; otherwise, reruns may create duplicates or incorrectly classify changed rows as new.

### 5.3 Reconciliation

The correct Type 1/fact reconciliation is:

```sql
SET @records_unchanged =
    @records_read - @records_written - @records_updated;
```

The expected identity is:

```text
Source records = inserted + updated + unchanged
```

This formula should not be applied blindly to SCD2 as though newly inserted replacement versions and expired versions represent separate source rows. SCD2 metrics must distinguish **changed source business entities**, **expired destination versions**, and **inserted destination versions**.

### 5.4 Transactions and logging

The stored procedure uses `TRY...CATCH`, `BEGIN TRANSACTION`, `COMMIT`, and rollback on failure, with `SET XACT_ABORT ON`.

- `dw.ETL_Run`: execution ID, process, start/end times, status, loaded-row count, and errors.
- `dw.ETL_Load_Log`: per-table load audit including table name, rows loaded, time, and error message.

**Audit distinction:** `@run_id` assigned for the ETL execution is not necessarily the same as the source lineage `run_id` carried into ODS/DW rows. They serve different purposes and should remain distinguishable in documentation.

The existing audit tables primarily store inserted-row counts. Updated and unchanged counts are returned by the procedure; persisting them in audit tables is a recommended enhancement.

---

## 6. Issues encountered, investigation, root cause, and resolution

This section records the actual development problems, including cases where the first assumption was incorrect.

### Issue 1 — Treating Type 1 tables like SCD2

**Symptom:** Encounter and clinical detail branches contained SCD2-style reconciliation/error messages even though the implementation only inserted new rows and did not expire or update existing rows.

**Investigation:** Reviewed each destination's intended behavior and compared it to the stored procedure's UPDATE/INSERT logic.

**Root cause:** Reused ETL template logic across tables with different historical requirements.

**Fix:** Classified tables by load strategy; implemented changed-row updates and new-row inserts for Type 1 dimensions and incremental facts. Adjusted reconciliation to count inserted, updated, and unchanged rows separately.

**Lesson:** Reusing a stored-procedure template is helpful only when the target grain and change-management semantics are explicitly defined.

### Issue 2 — SCD2 reconciliation was applied to a fact table

**Symptom:** `Fact_Claims` raised a reconciliation error when loaded with dimension-style logic.

**Root cause:** Fact rows should be updated or inserted at their business grain; they should not be treated as SCD2 dimension versions.

**Fix:** Reworked claim loading into an incremental upsert with change detection and separate inserted/updated/unchanged counts.

### Issue 3 — Missing `Dim_Encounters` caused claim join-count failure

**Symptom:** `Fact_Claims` reported `Source claim count differs after dimension joins` (`Msg 50005`).

**Investigation:** Compared ODS source count with rows produced after warehouse dimension joins.

**Root cause:** `dw.Dim_Encounters` had not yet been populated, so the inner join removed source claims.

**Fix:** Loaded the encounter dimension before the claims fact and enforced dependency-aware execution order.

**Lesson:** Join-count checks can expose missing prerequisite loads, not just duplicate records.

### Issue 4 — Patient and provider surrogate keys could not be resolved

**Symptom:** `Msg 50007`, with **70,000 missing `PatientKey`** and **70,000 missing `ProviderKey`**, while encounter, claim status, billing-date, and run-ID checks were resolved.

**Investigation:** Inspected the patient/provider joins and compared historical billing dates with SCD2 version start dates.

**Root cause:** Using billing date against SCD2 load-effective dates yielded no valid historical version match.

**Fix for initial load:** Resolve `dw.Dim_Patients` and `dw.Dim_Providers` using the single active record for each business ID:

```sql
LEFT JOIN dw.Dim_Patients pt
  ON bl.patient_id = pt.patient_id
 AND pt.active_flag = 1
LEFT JOIN dw.Dim_Providers pr
  ON en.provider_id = pr.provider_id
 AND pr.active_flag = 1
```

**Caveat:** This is a pragmatic initial-load mapping, not historically accurate as-of SCD2 attribution. Check for multiple active versions per business ID.

### Issue 5 — Missing claim IDs

**Symptom:** Some claim records had blank or null `claim_id`, preventing unique claim-level upsert matching.

**Finding:** **10,362** claim rows had missing IDs. The dataset contained **70,000** claim/billing records; `billing_id` was found to be unique, and the missing-ID records were paid claims.

**Fix used:** Populate missing `claim_id` with the corresponding `billing_id` in ODS, while preserving existing IDs:

```sql
UPDATE ods.Claims_and_Billing
SET claim_id = billing_id,
    updated_datetime = SYSDATETIME()
WHERE NULLIF(LTRIM(RTRIM(claim_id)), '') IS NULL;
```

**Validation / limitation:** A unique `billing_id` does not automatically guarantee no collisions with *existing* claim IDs. Validate uniqueness of the resulting `claim_id` across the full source. Document this as a dataset-specific surrogate fallback, and apply it in the repeatable staging-to-ODS process rather than as a one-off repair.

### Issue 6 — Missing claim billing dates

**Symptom:** `Msg 50008: Invalid or missing claim billing date` after the claim-key issue was resolved.

**Investigation:** Identified claims with missing billing dates and checked for a matching encounter visit date.

**Fix used:** For missing billing dates, substitute the associated encounter `visit_date` where available:

```sql
UPDATE bl
SET bl.claim_billing_date = CAST(en.visit_date AS DATE),
    bl.updated_datetime = SYSDATETIME()
FROM ods.Claims_and_Billing bl
JOIN ods.Encounters en
  ON bl.encounter_id = en.encounter_id
WHERE bl.claim_billing_date IS NULL
  AND en.visit_date IS NOT NULL;
```

**Important:** Encounter date is not necessarily the true billing date. This is an **imputed value**, appropriate only under a documented dataset rule. A `BillingDateImputedFlag` is recommended for downstream trend interpretation. Invalid non-null dates, if stored as text, require separate validation.

**Date dimension safeguard:** Avoid masking unresolved dates with an arbitrary hardcoded `DateKey` such as `20200101`; reject or explicitly handle invalid date relationships.

### Issue 7 — Duplicate `diagnosis_id` values were legitimate

**Symptom:** Type 1 `Dim_Diagnoses` raised `Msg 50002: Duplicate source business keys` when checking uniqueness of `diagnosis_id` alone.

**Investigation:** Grouped diagnoses by ID and counted distinct encounters. Example: `DIA0009` appeared in **775 different encounters**; other diagnosis IDs were likewise reused. The records represented the same diagnosis definition attached to different encounters.

**Root cause:** `diagnosis_id` was incorrectly treated as a unique diagnosis-row identifier.

**Fix:** Validate and match by **(`diagnosis_id`, `encounter_id`)** for the existing destination design. Apply the composite key consistently in duplicate checks, UPDATE joins, and INSERT `NOT EXISTS`.

```sql
SELECT diagnosis_id, encounter_id, COUNT(*) AS rows_found
FROM ods.Diagnoses
GROUP BY diagnosis_id, encounter_id
HAVING COUNT(*) > 1;
```

**Modeling insight:** A future design could separate a diagnosis-code/reference dimension from an encounter-diagnosis association table. The present model intentionally preserves encounter-level associations.

### Issue 8 — Medication IDs did not uniquely identify medication orders

**Symptom:** Medication data showed repeated `medication_id` values, including distinct drugs associated with the **same encounter and prescriber**. For example:

| medication_id | encounter_id | prescriber_id | drug_name | dosage | cost |
|---|---|---|---|---|---:|
| `MED49362` | `ENC069659` | `PRO00066` | Furosemide | 40 mg | 9 |
| `MED49362` | `ENC069659` | `PRO00066` | Ipratropium | 0.5 mg | 10 |
| `MED49362` | `ENC069659` | `PRO00066` | Prednisone | 20 mg | 6 |

**Investigation:** Tested candidate business-key combinations rather than assuming `medication_id` or `medication_id + encounter_id + prescriber_id` was unique.

**Finding:** The five-column combination (`medication_id`, `encounter_id`, `prescriber_id`, `drug_name`, `prescribed_date`) returned no duplicates in the source during testing.

**Resolution:** Align medication dimension upsert keys and fact-key resolution with the actual source grain. The final fact join was reported working after including additional medication attributes (`drug_name`, `dosage`, `route`, `frequency`, `duration`) to distinguish matching records.

**Design caveat:** Dosage, route, frequency, and duration are potentially mutable attributes. Joining on them can fail after Type 1 corrections. A permanent immutable medication-order key would be more robust; any current composite key must be consistently applied and revalidated on new data.

### Issue 9 — `Fact_Medications` join-count reconciliation

**Symptom:** `Fact_Medications source joins changed record count.`

**Diagnostic method:** Count rows after each successive join, rather than adding `DISTINCT` to suppress symptoms.

| Diagnostic stage | Observed rows |
|---|---:|
| ODS Medications | 94,498 |
| After medication dimension join | 94,498 |
| After encounter dimension join | 94,498 |
| After active provider dimension join | 94,498 |

The validated diagnostic join did **not** multiply or drop rows. A separate check found no duplicate five-column composite keys in `dw.Dim_Medications`.

**Resolution:** Reconciled the actual temporary-table join conditions with the tested matching logic; the user confirmed the final implementation worked after adding medication attribute predicates. The precise final deployed join should be committed to this repository as the source of truth.

**Lesson:** When the standalone diagnostic query and stored procedure disagree, compare their exact JOIN predicates, filters, null handling, and key definitions. Do not conclude that a selected surrogate key itself causes duplicates.

### Issue 10 — Repeated ETL runs and idempotency

**Risk:** An ETL process may appear successful on first load but duplicate or rewrite data unnecessarily on subsequent runs.

**Control:** Use business-key-based `NOT EXISTS` insertion and update only when values actually differ. Test a second execution with unchanged ODS data.

**Expected second-run behavior:** Zero inserted, zero updated, all valid source rows unchanged. This is a recommended regression test; the conversation confirms the pipeline ultimately worked but does **not** independently establish a complete second-run audit for every branch.

---

## 7. Validation and reconciliation checklist

Use these checks after each stage and whenever business-key logic changes.

### 7.1 Source grain and duplicate checks

```sql
-- Diagnosis association grain
SELECT diagnosis_id, encounter_id, COUNT(*) AS n
FROM ods.Diagnoses
GROUP BY diagnosis_id, encounter_id
HAVING COUNT(*) > 1;

-- Candidate medication-order grain
SELECT medication_id, encounter_id, prescriber_id,
       drug_name, prescribed_date, COUNT(*) AS n
FROM ods.Medications
GROUP BY medication_id, encounter_id, prescriber_id,
         drug_name, prescribed_date
HAVING COUNT(*) > 1;

-- Claim upsert key
SELECT claim_id, COUNT(*) AS n
FROM ods.Claims_and_Billing
GROUP BY claim_id
HAVING COUNT(*) > 1;
```

### 7.2 Dimension current-version checks

```sql
SELECT patient_id, COUNT(*) AS active_versions
FROM dw.Dim_Patients
WHERE active_flag = 1
GROUP BY patient_id
HAVING COUNT(*) > 1;

SELECT provider_id, COUNT(*) AS active_versions
FROM dw.Dim_Providers
WHERE active_flag = 1
GROUP BY provider_id
HAVING COUNT(*) > 1;
```

### 7.3 Join-cardinality checks

For each fact, compare source row count to resolved dimension-key row count **before** performing inserts or updates. A count increase indicates duplicate matches; a decrease indicates missing matches or filtering. In addition, test `COUNT(DISTINCT <resolved business key>)` to ensure one resolved row per source business event.

### 7.4 Required-key and data-quality checks

- Missing claim IDs and duplicate resolved claim IDs.
- Missing or imputed claim billing dates.
- Missing patient/provider/encounter surrogate keys.
- Missing status, denial-reason, appeal-status, or date keys where required.
- Unexpected multiple active SCD2 dimension versions.
- Missing adjudication matches and duplicate adjudication rows per claim.
- Source-to-destination totals for billed, paid, denied, medication cost, and procedure cost, at the appropriate grain.

### 7.5 Incremental-load regression tests

1. **Initial load:** New records inserted; source count reconciles to target grain.
2. **No-change rerun:** `inserted = 0`, `updated = 0`.
3. **Single-attribute change:** Exactly one intended Type 1 record updates; no new dimension surrogate key.
4. **New source key:** Exactly one new record inserted.
5. **SCD2 tracked-attribute change:** Prior active version expires and one new active version is created.
6. **Missing parent key:** Load fails with a clear error rather than silently dropping rows.
7. **Duplicate source key:** Load fails when the validated *true business key* is duplicated.
8. **Fact amount change:** Existing fact is updated, not duplicated.
9. **Rollback:** Failed transaction leaves the destination consistent and records the failure.

---

## 8. Execution and reproducibility

> This README describes the architecture and observed fixes. The exact staging/ODS scripts, DDL, and final tested production procedure must be included in the repository for fully reproducible execution.

### Recommended sequence

1. Create the `ETL_DB` database, `stg`, `ods`, and `dw` schemas, tables, keys, and date dimension.
2. Ingest the nine original source files into staging.
3. Validate and standardize source values into ODS; include documented claim-ID and billing-date fallback rules.
4. Load SCD2 dimensions: patients, providers.
5. Load encounter and clinical dimensions: encounters, diagnoses, lab tests, procedures, medications.
6. Load claim-status, denial-reason, and appeal-status lookups and ensure `DimDate` coverage.
7. Load medication, procedure, and claims facts after their dependencies are present.
8. Review `dw.ETL_Run` and `dw.ETL_Load_Log`, then run SQL reconciliation checks.
9. Rerun with unchanged source data to test idempotency.
10. Publish validated warehouse views/tables to Power BI and document business-measure reconciliation.

### Stored-procedure invocation

```sql
USE ETL_DB;
GO

EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Patient';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Providers';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Encounters';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Diagnoses';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Lab_Tests';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Procedures';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Medications';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Claim_Status';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Denial_Reason';
EXEC dbo.sp_from_ods_to_production @table_name = 'Dim_Appeal_Status';
EXEC dbo.sp_from_ods_to_production @table_name = 'Fact_Medications';
EXEC dbo.sp_from_ods_to_production @table_name = 'Fact_Procedures';
EXEC dbo.sp_from_ods_to_production @table_name = 'Fact_Claims';
```

**Execution note:** This is a dependency-aware example, not an automatically verified deployment script. Check your actual lookup/date dependencies and final procedure parameter names before running the full sequence.

---

## 9. Power BI reporting plan (historical design notes; see Section 14 for implemented dashboard)

Power BI is intended to be both the **analytical consumption layer** and an additional **validation layer**, rather than a replacement for SQL-level data-quality controls.

Proposed report areas:

| Page / area | Example business questions |
|---|---|
| Executive overview | What are the total encounters, patients, claims, billed amounts, paid amounts, and trends? |
| Patient & encounter utilization | How do encounters vary over time, visit type, and patient attributes? |
| Diagnosis & clinical trends | Which diagnoses and chronic conditions occur most frequently? |
| Procedures, labs & medications | What services and medications are most common, and what costs are associated with them? |
| Claims & financial performance | What are billed, paid, and denied amounts; how do status and denial patterns change? |
| Provider performance | How do encounter volumes, procedures, and financial metrics vary by provider? |
| Drillthrough / detail | Can a user investigate an encounter, claim, or patient-level history where permitted? |
| ETL and data-quality monitoring | Which loads succeeded, failed, or produced unexpected row counts? |

The project has also considered **separate restricted administrative/validation pages**. These are planned design concepts, not claims of finished Power BI pages.

**Modeling caution:** Clinical detail tables can be one-to-many from encounters. Joining multiple details directly in a flat visual/query can multiply encounters and financial amounts. Measures must respect the intended grain, use appropriately designed relationships, and be reconciled to warehouse SQL totals.

---

## 10. Actual repository layout and how to navigate it

This section records the **existing repository hierarchy shown in the project screenshots**, rather than proposing directories that have not been created.

```text
project-root/
├── README.md
├── data/
│   ├── raw/                         # Original source data
│   └── etl clean/                   # Cleaned / prepared data
├── docs/                            # Power BI page screenshots and model relationship mappings
├── powerbi/
│   └── Hospital Operations & Financial Analytics.pbix
├── scripts/                         # Supporting scripts (contents not inventoried here)
├── sql/
│   ├── 0 - Run All ETL Stored Procedures.sql
│   ├── 1 - sp_drop_schema_tables.sql
│   ├── 2 - sp_create_etl_tables.sql
│   ├── 2.5 - sp_etl_file_configuration.sql
│   ├── 3 - sp_dw_etl_file_configuration.sql
│   ├── 4 - sp_extract_files_to_stage.sql
│   ├── 5 - sp_transform_stg_tables_for_ods.sql
│   ├── 6 - sp_run_transform_from_stg_to_ods.sql
│   ├── 7 - usp_LoadDimDate.sql
│   ├── 8 - sp_transform_ods_for_production.sql
│   └── 9 - sp_export_data.sql
└── validation/
    ├── Overview Dashboard Data Validation.sql
    ├── Patients Dashboard Data Validation.sql
    ├── Patients Details Validation.sql
    ├── Patients Dashboard Data Validation1.png
    └── Patients Dashboard Data Validation2.png
    └── Patients Detail Data Validation1.png
    └── Patients Detail Data Validation2.png
```

### Folder responsibilities

| Path | Contents and purpose |
|---|---|
| `data/raw/` | Original input datasets retained for source comparison and lineage. |
| `data/etl clean/` | Cleaned/prepared extracts used during ETL development. |
| `docs/` | Power BI screenshots for each report page and model relationship mapping screenshots. Exact image filenames are not inventoried in this README. |
| `powerbi/Hospital Operations & Financial Analytics.pbix` | Power BI report and semantic model. |
| `scripts/` | Supporting project scripts; contents should be documented after inventory. |
| `sql/` | Numbered T-SQL scripts covering setup, configuration, ingestion, transformations, date dimension, warehouse and export. |
| `validation/` | SQL checks and captured screenshots supporting dashboard-versus-SQL reconciliation. |
| `README.md` | Main documentation and development history at repository root. |

### SQL script index

| Script | Intended role inferred from filename |
|---|---|
| `0 - Run All ETL Stored Procedures.sql` | Entry point / orchestration for ETL stored procedures. |
| `1 - sp_drop_schema_tables.sql` | Drop/reset schema objects; **destructive, inspect before running**. |
| `2 - sp_create_etl_tables.sql` | Create ETL schemas and tables. |
| `2.5 - sp_etl_file_configuration.sql` | Configure input ETL file list. |
| `3 - sp_dw_etl_file_configuration.sql` | Configure DW/export file list. |
| `4 - sp_extract_files_to_stage.sql` | Extract/land files into staging. |
| `5 - sp_transform_stg_tables_for_ods.sql` | Define staging-to-ODS transformations. |
| `6 - sp_run_transform_from_stg_to_ods.sql` | Execute staging-to-ODS transformation. |
| `7 - usp_LoadDimDate.sql` | Load the date dimension. |
| `8 - sp_transform_ods_for_production.sql` | Define ODS-to-warehouse transformations. |
| `9 - sp_export_data.sql` | Export warehouse data. |

These descriptions are based on the visible filenames and prior development discussion; the exact execution order, stored-procedure parameters and dependency behavior must be checked against the committed SQL code. The `0` orchestration script should be reviewed before executing individual numbered scripts; the numbering is not a guarantee that every file should be run sequentially on an existing database.

### Validation evidence

The repository currently shows `Overview Dashboard Data Validation.sql`, `Patients Dashboard Data Validation.sql`, and two patient-validation PNG captures. These are evidence artifacts, not proof that every dashboard KPI or every filter combination has been fully regression-tested. Add subsequent validation scripts and screenshots as each page is verified.

**Publication caution:** Check the source dataset's redistribution terms and inspect screenshots/data for sensitive information before pushing to a public repository.

---

## 11. BCP data export: implementation and troubleshooting

### 11.1 Objective and scope

After the ODS-to-DW pipeline loaded successfully, I added an **outbound export stage** to produce clean, analysis-ready extracts of warehouse tables. The requirement was to run exports from **SQL Server Management Studio (SSMS)**, reuse the existing `dw.ETL_Config_FileList` table to control the export list and order, save each DW table to its own file, and include column headers.

This export is distinct from the earlier `BULK INSERT` ingestion process:

| Direction | Technology | Purpose |
|---|---|---|
| Source files → SQL Server | `BULK INSERT` / STG-to-ODS ETL | Ingest and standardize source data |
| SQL Server DW → files | BCP `queryout` | Publish curated warehouse extracts |

The export destination in examples below is a **placeholder**, not an actual developer-specific path: `C:\DataProjects\HealthcareETL\exports\`. The instance name `localhost\SQLINSTANCE` is also a placeholder. Replace both for your environment.

### 11.2 Why `sp_executesql` was insufficient

The initial dynamic loop used `sp_executesql` to run `SELECT * FROM dw.[TableName]`. That returned results to SSMS but **did not write a file**. SQL Server's query execution and operating-system file export are separate operations. BCP (`bcp.exe`) provides the `queryout` command to write query results to a file.

The configuration-driven design was retained, but the export command had to execute outside the SQL query engine. In this local development environment, `xp_cmdshell` was used to launch BCP from T-SQL. **Security note:** `xp_cmdshell` runs operating-system commands under a privileged execution context and is commonly disabled. It should not be enabled casually on shared or production systems; use an approved job runner, agent/proxy, or external script where appropriate.

### 11.3 Initial error: `bcp` not recognized

The first attempt to call `bcp` from `xp_cmdshell` failed with:

```text
'bcp' is not recognized as an internal or external command,
operable program or batch file.
```

**Investigation:** Running `where bcp` in the developer's Windows Command Prompt showed that BCP was installed, but the environment used by SQL Server did not resolve it through its `PATH` variable.

**Resolution approach:** Use the executable's full installed path in the command. The path below is a typical installation location, not a guaranteed location on every machine:

```text
C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\bcp.exe
```

### 11.4 Command-line quoting with paths containing spaces

The next error was:

```text
'C:\Program' is not recognized as an internal or external command.
```

The shell had interpreted the space in `Program Files` as a command boundary. BCP requires careful quotation of (1) its executable path, (2) the SQL query, and (3) the output filename. For `xp_cmdshell`, an additional outer pair of quotes is commonly required when the command begins with a quoted executable path.

Example for **one table** (adapt the instance and directory):

```sql
DECLARE @cmd VARCHAR(8000);

SET @cmd =
    '""C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\bcp.exe" ' +
    '"SELECT * FROM ETL_DB.dw.Dim_Encounters" ' +
    'queryout "C:\DataProjects\HealthcareETL\exports\Dim_Encounters.csv" ' +
    '-c -t, -T -S "localhost\SQLINSTANCE""';

EXEC master.dbo.xp_cmdshell @cmd;
```

Quoting fixes parsing only; it does not grant access to the executable or output directory.

### 11.5 Identifying the execution account and separating permissions

Even after the quoting was corrected, execution returned `Access is denied`. A key discovery was that commands launched through SSMS are **not necessarily executed under the interactive Windows user**. The Windows identity was determined with:

```sql
EXEC master.dbo.xp_cmdshell 'whoami';
```

The actual account name is intentionally omitted from this public documentation. On this development installation, it was a **SQL Server virtual service account**.

To isolate file-write permission from executable-read permission, the following test created a small file:

```sql
EXEC master.dbo.xp_cmdshell
    'cmd /C echo test > "C:\DataProjects\HealthcareETL\exports\permission_test.txt"';

EXEC master.dbo.xp_cmdshell
    'dir "C:\DataProjects\HealthcareETL\exports\permission_test.txt"';
```

The file was created successfully. A `NULL` row alone from `xp_cmdshell` was **not an error**; it simply meant the command had produced no standard output. The subsequent `dir` confirmed the file existed. This established that the service account **could write to the export directory**, so the remaining `Access is denied` error was not caused by the destination folder.

### 11.6 Finding the executable and parent-directory ACL problem

The next diagnostic attempts separated ordinary command execution from BCP access:

```sql
-- Operating-system commands worked under the service account.
EXEC master.dbo.xp_cmdshell 'C:\Windows\System32\whoami.exe';

-- Reading the BCP executable initially failed.
EXEC master.dbo.xp_cmdshell
    'dir "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\bcp.exe"';

-- BCP was also absent from SQL Server's command PATH.
EXEC master.dbo.xp_cmdshell 'cmd /C bcp -v';
```

Windows `icacls` showed that the BCP executable and its installation directories had permissions for the local user and administrative identities, but the SQL Server service identity did not have the necessary effective access. Granting **Read & Execute (`RX`)** to the executable alone was not sufficient: access to the relevant parent directories was also needed.

The permissions were corrected with narrowly scoped ACL changes performed by an administrator, using a placeholder service identity in the example below:

```cmd
icacls "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools" /grant "NT SERVICE\MSSQL$SQLINSTANCE:(RX)"
icacls "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn" /grant "NT SERVICE\MSSQL$SQLINSTANCE:(RX)"
icacls "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\bcp.exe" /grant "NT SERVICE\MSSQL$SQLINSTANCE:(RX)"
```

**Security guidance:** These commands are examples of what was investigated locally, not a universal instruction to modify SQL Server installation ACLs. Confirm the real account and effective permissions before changes; avoid granting `Everyone`, `Full Control`, or broad recursive access. A managed execution account or an external export runner is preferable for production use.

After directory permissions were adjusted, `dir` could finally list `bcp.exe` from `xp_cmdshell`.

### 11.7 BCP resource DLL failure

The next BCP version test produced a new error:

```text
Unable to load BCP resource DLL. BCP cannot continue.
```

This was meaningful progress: Windows could launch `bcp.exe`, but the process could not load required supporting resources. The relevant BCP `Binn` directory's files and subdirectories were then granted the minimum necessary **Read & Execute** access to the SQL Server execution identity, after which BCP worked.

An example of the *scoped* ACL operation used during troubleshooting is:

```cmd
icacls "C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn" /grant "NT SERVICE\MSSQL$SQLINSTANCE:(OI)(CI)RX" /T
```

`/T` changes permissions recursively; it should be used only after confirming the exact affected directory and reviewing organizational security requirements. If a DLL-loading error persists, inspect the failing module and its actual access path rather than granting permissions to unrelated directories.

**Verification:**

```sql
EXEC master.dbo.xp_cmdshell
    'cmd /S /C ""C:\Program Files\Microsoft SQL Server\Client SDK\ODBC\170\Tools\Binn\bcp.exe" -v"';
```

The version test eventually succeeded, confirming that the runtime could load its required components. Restarting SSMS was not necessary.

### 11.8 Verifying the export outside and inside SQL Server

BCP was first verified successfully in Windows Command Prompt, where it connected to the named SQL Server instance and exported `Dim_Encounters` in batches. This helped distinguish a working BCP installation from the separate execution-context issue encountered through `xp_cmdshell`.

```cmd
bcp "SELECT * FROM ETL_DB.dw.Dim_Encounters" queryout "C:\DataProjects\HealthcareETL\exports\Dim_Encounters.csv" -c -t, -T -S "localhost\SQLINSTANCE"
```

The same basic command was then made executable from SSMS after resolving permissions. BCP's `-T` option uses **Windows integrated authentication under the account running BCP**, which differs between interactive CMD and `xp_cmdshell`. The execution account therefore also needs the appropriate SQL Server login and `SELECT` permissions; file-system access alone is not sufficient.

### 11.9 Making exports configuration-driven

The export workflow reads active table names from `dw.ETL_Config_FileList` ordered by `load_order`, constructs a `SELECT` query against the corresponding `dw` table, and writes one file per table. The implementation uses a cursor (or equivalent ordered iteration), not a `WHILE` loop that assumes `load_order` values are consecutive.

The workflow performs the following checks:

1. Validate the configured table name before using it in SQL and file paths.
2. Confirm that the destination table exists in the `dw` schema.
3. Generate the BCP `queryout` command with correctly quoted arguments.
4. Capture and check the return status; stop and report a failed export rather than printing success unconditionally.
5. Verify that the output file exists and compare exported data-row counts with SQL counts.

**Operational limitation:** `xp_cmdshell` uses `varchar(8000)` or `nvarchar(4000)` command input limits. Large dynamically generated queries can exceed the command-line limit; external export scripts are more flexible for wide tables.

### 11.10 Adding column headers

Standard BCP `queryout` does **not** write column headers. The next requirement was to make each file self-describing. The implemented approach builds a header row from `sys.columns` and combines it with string-converted data rows using `UNION ALL`.

```sql
-- Illustrative metadata query used to build ordered header expressions
SELECT STRING_AGG(
           CAST(QUOTENAME(name, '''') AS NVARCHAR(MAX)), ','
       ) WITHIN GROUP (ORDER BY column_id) AS HeaderExpressions
FROM sys.columns
WHERE object_id = OBJECT_ID(N'dw.Dim_Encounters');
```

The actual export query also converts each data column to text before combining it with the header expressions. **Important correctness improvement:** `UNION ALL` alone does not guarantee the header appears first. A robust implementation should add a sort key (for example, `0` for the header and `1` for data), sort by it in the outer query, and omit that key from the exported projection. Validate the final output, not merely the SQL query's apparent row order.

**CSV correctness caveat:** `-c -t,` creates comma-delimited output but does not implement full RFC-style CSV quoting. Healthcare fields such as diagnosis descriptions may contain commas, quotation marks, or line breaks. The header technique addresses *headers only*; it does not solve field escaping. For files intended to be imported into Excel, Power BI, or another system as strict CSV, use a CSV-aware writer or implement and test escaping explicitly. Also verify character encoding, null handling, date formats, and row counts.

### 11.11 Troubleshooting chronology and reusable lessons

| Stage | Symptom | What the test established | Resolution / outcome |
|---|---|---|---|
| 1 | `bcp` not recognized | BCP was installed but not in the SQL Server process `PATH` | Used installed executable path |
| 2 | `'C:\Program' is not recognized` | Executable path contained spaces | Corrected command quoting |
| 3 | `Access is denied` | Export-folder write test succeeded | Investigated executable and directory ACLs |
| 4 | `dir` on `bcp.exe` denied | SQL Server service identity could not read the BCP path | Applied scoped `RX` permissions to required paths |
| 5 | BCP resource DLL could not load | Executable launched but supporting resources were inaccessible | Adjusted scoped resource access; version test succeeded |
| 6 | Export worked in CMD, not initially in SSMS | Interactive and SQL Server execution identities differed | Resolved `xp_cmdshell` environment and permissions |
| 7 | Export had no column headers | BCP has no native header switch | Generated headers from `sys.columns` |
| 8 | Export format needed additional validation | Headers do not imply RFC-compliant CSV | Documented ordering and escaping requirements |

### 11.12 Export validation and security checklist

- [ ] BCP version command runs in the **same execution context** as the automated export.
- [ ] The export identity has only the required database read and destination-folder write permissions.
- [ ] Export table names come from a validated configuration list.
- [ ] The output file exists and has the expected number of data records.
- [ ] The header is the **first** record and matches the table's actual column order.
- [ ] Commas, quotes, embedded newlines, nulls, Unicode, and dates are tested before claiming CSV compatibility.
- [ ] Exported files contain only synthetic, de-identified, or otherwise authorized data before any public publication.
- [ ] `xp_cmdshell` is disabled when no longer required, if it was enabled solely for local testing and policy permits disabling it.
- [ ] Commands and logs contain no passwords, private machine names, user profiles, or personal directory paths.

**Current milestone:** BCP executable access and DLL-loading problems were resolved; a successful BCP export was observed, and the SSMS export code was extended to generate headers. Full CSV-escaping and deterministic header-order validation remain recommended hardening steps.

---

## 12. Remaining improvements / technical debt

The pipeline's successful execution is an important milestone, but production-readiness requires additional safeguards:

- **Historical attribution:** Resolve the difference between SCD2 load dates and business-effective dates; document whether facts should retain original dimension surrogate keys.
- **Stable medication-order identity:** Prefer an immutable source order/line ID over matching mutable dosage and frequency attributes.
- **Business-key constraints:** Add validated unique indexes for each table at its actual grain, where schema and data allow.
- **Claim fallback provenance:** Flag claims whose IDs were derived from `billing_id`; ensure no collisions with original claim IDs.
- **Date imputation provenance:** Flag billing dates sourced from encounter dates.
- **Audit detail:** Persist inserted, updated, unchanged, rejected, and source counts in run-level metrics.
- **Incremental scope:** Clarify whether each branch reads a full ODS snapshot or only changed batches, and handle deletions/late-arriving records explicitly.
- **Null-safe medication matching:** Define behavior for null dosage, route, frequency, duration, and other matching attributes.
- **Financial integrity:** Reconcile paid/billed/denied amounts to the source at the correct claim grain and avoid duplicate adjudication joins.
- **Automated tests:** Add assertions for no-change reruns, controlled updates, dimension cardinality, and transaction rollback.
- **Reproducibility:** Commit final tested SQL DDL, STG-to-ODS transformations, and actual production procedure, rather than intermediate drafts.
- **Documentation:** Verify dataset provenance, publish a field-level data dictionary, and include dated screenshots/validation evidence.

---

## 13. Key takeaways

This project reinforced several lessons that apply to real-world analytics engineering:

1. **A field named `*_id` is not automatically unique.** Diagnose the true grain from the data.
2. **Join counts are a diagnostic tool.** A row-count mismatch can reveal missing prerequisites, missing keys, duplicate dimensions, or inconsistent predicates.
3. **Different tables require different change strategies.** SCD2, Type 1, lookup maintenance, and fact upserts solve different problems.
4. **Fix source-quality problems upstream.** Corrections such as missing claim IDs and dates should be documented and reproducible in STG-to-ODS logic.
5. **A successful load is not the same as a historically accurate model.** Current-version SCD2 joins are useful for an initial load but have important analytical limitations.
6. **Validate at each step.** Source profiling, ETL audits, warehouse checks, Excel reconciliation, and Power BI checks provide complementary evidence.
7. **Separate execution identities and permissions.** A command that works in an interactive shell may fail under a SQL Server service account; troubleshoot paths, ACLs, dependencies, and SQL authentication separately.
8. **Validate outbound extracts.** File creation and headers are not enough to guarantee CSV correctness.
9. **Document the investigation, not just the final SQL.** The errors and their resolutions explain why the finished data model looks the way it does.

---

## Project maintenance

**Focus:** SQL Server ETL, healthcare data modeling, dimensional warehousing, data quality, and business intelligence  
**Last documented milestone:** November 22, 2026 — final Power BI Patient Detail model corrected; 2024/2025 patient histories reconciled against SQL Server.

*This README is a living document. Update counts, screenshots, source references, and implementation notes as the committed code and reporting deliverables evolve.*


---

## 14. Power BI implementation: from warehouse to interactive healthcare analytics (October–November 2026)

> **Documentation convention:** Sections 1–13 preserve the original October engineering narrative, including historical descriptions of work that was then *planned*. This section records the later Power BI implementation and supersedes the older BI status descriptions. Exact final `.pbix` / `.pbip` and SQL scripts remain the definitive sources for column names and relationship settings.

### 14.1 Reporting objectives

The report extends the SQL engineering work into a portfolio-ready analytical product. It answers operational questions about encounters and patients; clinical questions about diagnoses, medications, procedures and labs; and revenue-cycle questions about billing, payments, claims, and denials. The dashboard is also a **second line of reconciliation**: numbers in visualizations are checked against warehouse SQL, rather than accepted simply because a chart renders.

The principal design choices were a common calendar-year filter, shared clinical/operational slicers, detail and drillthrough pages, and consistent KPI definitions. Visual styling uses a dark navy navigation/sidebar and header, light gray canvas, white KPI cards, and muted slate-blue chart accents.

### 14.2 Dashboard page inventory

| Report page | Purpose / content | Implementation notes |
|---|---|---|
| Executive Overview | Encounters, patients, claims, billed/paid values, annual trends, utilization | 2024/2025 comparison and KPI reconciliation |
| Patients & Utilization | Patient population, visits, returning patients, utilization by segment | Encounter count and distinct patient count must not be conflated |
| Patient Detail | Patient-level drillthrough with encounter, primary/secondary diagnosis, procedure, lab, medication, and claims history | Final model uses encounter-based filtering; obsolete bridge/detail tables and problematic primary-diagnosis-key relationship removed |
| Clinical Diagnoses | Primary-diagnosis trends, visit-type analysis, encounter-level diagnosis detail | Special solution to preserve secondary diagnoses |
| Medications | Medication utilization and clinical detail | Respect medication-order grain |
| Procedures | Procedure mix and utilization | Procedure slicer cross-filter behavior was adjusted |
| Lab Testing & Results | Lab volume and test/result analysis | Respect one-to-many encounter/test relationship |
| Claims & Revenue Cycle | Billed, paid, denied claims, statuses and financial trends | Use claim-grain counts and sums |
| Provider & Department Performance | Provider, specialty and department analysis | Avoid duplicating encounters via clinical detail joins |
| Encounter & Claim Explorer | Record-level exploration and reconciliation | Carefully distinguish claim IDs from encounter IDs |

The pages above describe the developed dashboard areas. They do not imply every possible visual or measure has been independently regression-tested.

### 14.3 Main slicers and business context

Common filters include calendar year, admission type, visit type, department, prescriber specialty, primary diagnosis and procedures. The distinction between **what a slicer selects** and **what detail rows must be displayed** is especially important: choosing encounters by *primary diagnosis* should not remove their secondary diagnosis records from a diagnosis-detail listing.

### 14.4 Date table and prior-year time intelligence

`Dim_Date` supplies `CalendarYear`, `DateKey` and the date-typed `FullDateAlternateKey`. A previous-year encounter measure initially returned blank even though 2024 and 2025 encounter totals were available. The issue was resolved by **Mark as date table** on `Dim_Date`, using the appropriate date column. This was a modeling configuration issue rather than missing prior-year encounters.

```dax
PY Total Encounters =
CALCULATE(
    [Total Encounters],
    SAMEPERIODLASTYEAR(Dim_Date[FullDateAlternateKey])
)

YoY Total Encounters =
[Total Encounters] - [PY Total Encounters]

YoY Total Encounters % =
DIVIDE([YoY Total Encounters], [PY Total Encounters])
```

For the full-year unfiltered comparison, 2024 encounters = **5,500** and 2025 encounters = **6,500**, so absolute growth = **1,000** and relative growth = **18.18%**. This calculation must be reevaluated under date-range, department, admission and other slicers. For measures that are already rates (e.g. denial rate), a difference in **percentage points** is different from a relative percentage change; label each appropriately.

### 14.5 Encounter vs diagnosis grain: the central model challenge

An encounter has one primary diagnosis for some reporting uses but can have **multiple diagnoses** overall. `Dim_Encounters[diagnosis_code]` identifies a single encounter diagnosis, while `Dim_Diagnoses` contains primary and secondary records. An earlier claims model used a relationship between `Fact_Claims[PrimaryDiagnosisKey]` and `Dim_Diagnoses[DiagnosisKey]` for claim-level primary-diagnosis reporting. **That problematic primary-diagnosis-key relationship was subsequently removed from the final Power BI model** (see Section 21). It is therefore unsafe to assume that selecting diagnosis fields from arbitrary tables will automatically produce every diagnosis per encounter.

The original dashboard primary-diagnosis slicer used `Dim_Diagnoses[diagnosis_description]`, which followed the claims relationship and did not consistently filter all encounter-based visuals. An attempt to introduce an additional active encounter/diagnosis relationship raised **ambiguous filter path** concerns. The solution for the main dashboard was to create a primary-diagnosis description on the encounter table:

```dax
Slicer Primary Diagnosis =
VAR DiagnosisCode = Dim_Encounters[diagnosis_code]
RETURN
    LOOKUPVALUE(
        Dim_Diagnoses[diagnosis_description],
        Dim_Diagnoses[encounter_id], Dim_Encounters[encounter_id],
        Dim_Diagnoses[diagnosis_code], DiagnosisCode,
        Dim_Diagnoses[primary_flag], "Yes"
    )
```

This was used as `Dim_Encounters[Slicer Primary Diagnosis]` for the general encounter-based dashboard. SQL checks confirmed, for example, **2024 acute upper respiratory infection: 388 encounters** and **2025: 433 encounters**; the 2024 selection corresponded to **360 distinct patients** and approximately **1.08 encounters per patient**. The distinct-patient measure and returning-patient logic were reviewed to avoid counting visits as people.

### 14.6 Why the first diagnosis detail visual appeared to repeat forever

When fields from `Dim_Encounters` and `Dim_Diagnoses` were combined without a suitable active filtering path, Power BI displayed unrelated encounter ID combinations, resembling an infinite loop. This was a **Cartesian-product / cross-join-like visual result**, not a DAX loop. Using only `Dim_Diagnoses` fields displayed the underlying primary and secondary rows correctly; adding encounter attributes exposed the relationship/filtering problem again. A measure with `REMOVEFILTERS(Fact_Claims)` could count two diagnoses for some encounters, but could not reliably restore rows already excluded by the visual's grouping/filter path. A `CONCATENATEX` measure was also unsuitable for a requirement of **one diagnosis per detail row**.

An **intermediate development solution (later removed)** was a dedicated calculated diagnosis-detail table, with the diagnosis row as its base grain and encounter/patient/provider attributes looked up by business keys:

```dax
Diagnosis_Detail =
ADDCOLUMNS(
    Dim_Diagnoses,
    "Patient",
        LOOKUPVALUE(
            Dim_Patients[Patient Display],
            Dim_Patients[patient_id],
            LOOKUPVALUE(
                Dim_Encounters[patient_id],
                Dim_Encounters[encounter_id],
                Dim_Diagnoses[encounter_id]
            )
        ),
    "Visit Date",
        LOOKUPVALUE(
            Dim_Encounters[visit_date],
            Dim_Encounters[encounter_id],
            Dim_Diagnoses[encounter_id]
        ),
    "Discharge Date",
        LOOKUPVALUE(
            Dim_Encounters[discharge_date],
            Dim_Encounters[encounter_id],
            Dim_Diagnoses[encounter_id]
        ),
    "Department",
        LOOKUPVALUE(
            Dim_Encounters[department],
            Dim_Encounters[encounter_id],
            Dim_Diagnoses[encounter_id]
        ),
    "NPI",
        LOOKUPVALUE(
            Dim_Providers[npi],
            Dim_Providers[provider_id],
            LOOKUPVALUE(
                Dim_Encounters[provider_id],
                Dim_Encounters[encounter_id],
                Dim_Diagnoses[encounter_id]
            )
        )
)
```

The first NPI lookup mistakenly matched an NPI against a `provider_id`; it was corrected to match `Dim_Providers[provider_id]` and return `Dim_Providers[npi]`. An extra trailing comma after the last `ADDCOLUMNS` expression also caused a syntax error. The resulting detail visual was inspected and confirmed to show both `primary_flag = Yes` and `No`, alongside patient, encounter, visit/discharge date, department and NPI.

To preserve secondary diagnoses when the user selects a **primary** diagnosis, a separate calculated column was added to the detail table:

```dax
Slicer Primary Diagnosis =
LOOKUPVALUE(
    Dim_Encounters[Slicer Primary Diagnosis],
    Dim_Encounters[encounter_id],
    Diagnosis_Detail[encounter_id]
)
```

During that intermediate design, `Diagnosis_Detail[Slicer Primary Diagnosis]` was used for the diagnosis detail page; **do not recreate this removed table in the final model**. Because this label repeats on every diagnosis row in the encounter, filtering by the encounter's primary diagnosis retains its secondary diagnoses. The existing `Dim_Encounters` primary-diagnosis slicer can remain for the other pages. **Historical scope warning (superseded design):** The detail-table slicer did not automatically filter unrelated report tables; verify all Diagnosis page visuals and slicer interactions. The calculated table materializes on model refresh, not at every visual interaction. Lookups assume unique keys or identical result values; confirm uniqueness in SQL.

### 14.7 Procedure filtering and ambiguous paths

The procedures slicer initially did not filter all relevant encounter visuals. A model relationship involving `Fact_Procedures[EncounterKey]` and `Dim_Encounters[EncounterKey]` was adjusted to support the required cross-filter behavior. This was a targeted fix, **not** a recommendation to enable bidirectional relationships throughout the model. The diagnosis work separately demonstrated that activating multiple paths can create ambiguity. Capture the final relationship diagram and document each relationship's cardinality, active status, and cross-filter direction in `docs/powerbi_model.md`.

### 14.8 Report interaction and navigation design

The dashboard uses consistent visual hierarchy, slicers, and dedicated detail pages to move from summary KPIs to specific encounters, patients and claims. Drillthrough should preserve the intended entity grain. When a summary chart uses a financial amount, drillthrough should pass identifying dimensions/keys rather than assume that an amount uniquely identifies a record. Test slicer interactions after each relationship change, particularly on pages with multiple clinical detail tables.

---

## 15. SQL and Power BI reconciliation: observed 2024–2025 checkpoints

These are **development checkpoints**, not a claim of a complete certified financial audit. Amounts are rounded for readability; retain the exact SQL outputs and measure definitions in the repository.

| Metric | 2024 | 2025 | Notes |
|---|---:|---:|---|
| Encounters | 5,500 | 6,500 | 2025 YoY +18.18% |
| Billed encounters | 5,143 | 5,875 | Distinct encounter-level billing classification |
| Unbilled encounters | 357 | 625 | 2024 and 2025 billed + unbilled reconcile to total encounters |
| Claims | 5,788 | 6,665 | Claim count differs from encounter count |
| Total billed | ~$4.405M | ~$4.974M | Rounded financial checkpoint |
| Total paid | ~$2.787M | ~$3.184M | Rounded financial checkpoint |
| Denied claims | 524 | 554 | Confirm claim-status business rule in SQL |

The billed-encounter counts and unbilled-encounter counts reconcile: 5,143 + 357 = 5,500 (2024), and 5,875 + 625 = 6,500 (2025). This **does not** mean every billed encounter has exactly one claim: claims exceed encounters in both years.

### 15.1 Example validation queries

```sql
-- Verify encounter totals by visit year.
SELECT YEAR(visit_date) AS visit_year,
       COUNT(*) AS encounter_rows,
       COUNT(DISTINCT encounter_id) AS unique_encounters
FROM dw.Dim_Encounters
WHERE visit_date >= '2024-01-01'
  AND visit_date < '2026-01-01'
GROUP BY YEAR(visit_date)
ORDER BY visit_year;

-- Verify how many diagnoses exist per encounter.
SELECT encounter_id,
       COUNT(*) AS diagnosis_rows,
       SUM(CASE WHEN primary_flag = 'Yes' THEN 1 ELSE 0 END) AS primary_rows
FROM dw.Dim_Diagnoses
GROUP BY encounter_id
HAVING COUNT(*) > 1;
```

Adjust physical schema/column names to the committed SQL DDL. Financial validation must separately check source-to-ODS, ODS-to-DW, and DW-to-Power-BI totals **at the correct fact grain**, not after a one-to-many clinical join. Use consistent date basis: visit year for encounter utilization versus billing/claim date for financial reporting where appropriate.

### 15.2 Diagnosis validation example

The acute upper respiratory infection primary-diagnosis selection was checked against SQL and Power BI: **388 encounters in 2024**, **433 in 2025**. For 2024, the same filtered set included **360 unique patients**. These are selected-filter checkpoints, not whole-population diagnosis totals. Document the exact diagnosis code, flag and date predicates in the final SQL validation script.

### 15.3 Measure definitions and denominator controls

| Measure | Intended grain / calculation principle |
|---|---|
| Total Encounters | Distinct encounter key or verified one-row-per-encounter dimension |
| Patients Seen | Distinct patient business key among selected encounters |
| Encounters per Patient | Encounter count / distinct patients seen |
| Total Claims | Claim key, not encounter key |
| Total Billed / Paid | Sum claim-level amounts after preventing fanout |
| Denial Rate | Denied claims / eligible claim denominator; explicitly define statuses |
| Returning Patients | Define visit-order/date logic and unique patient count; do not infer from multiple diagnosis rows |
| YoY % | `(CY − PY) / PY` with safe divide and appropriate date table |
| Rate PP change | `CY rate − PY rate` expressed as percentage points |

The exact DAX definitions for all KPIs should be exported to `powerbi/dax/` or captured from the final model. A documented business definition is not evidence that an identical measure exists in the final file.

---

## 16. End-to-end troubleshooting chronology and engineering decisions

| Stage | Symptom | Investigation / root cause | Resolution / takeaway |
|---|---|---|---|
| Source profiling | IDs reused or apparently duplicated | Identifier was not the actual business grain | Validate composite keys; do not blindly deduplicate |
| STG → ODS | Source date/text issues | Mixed date formats, whitespace, malformed values | Normalize, `TRY_CONVERT`, log rejections |
| ODS → DW | Type 1 tables behaved like inserts or SCD2 | Wrong change strategy | Update changed rows, insert new business keys |
| SCD2 dimensions | Historical facts failed to resolve patient/provider | Warehouse load-effective dates differed from event dates | Active-version workaround for initial load; document historical limitation |
| Claims | Missing IDs/dates, join mismatches | Incomplete source fields and missing parents | Explicit fallbacks, parent checks, reconciliation |
| Lookup dimensions | Duplicate `Unknown` statuses | Repeated seed/insert logic | Unique keys and controlled unknown-member handling |
| Fact procedures | Duplicate procedure identifier | Incorrect assumption about source grain | Review composite keys and duplicates |
| Date conversion | US/EU text dates | Locale-sensitive parsing | Explicit conversion and validation |
| Export | `bcp` not found / path errors / DLL | Executable discovery, quoting, account rights and dependencies | Validate command outside SQL and under actual execution context |
| Export | Data file produced without headers | BCP output behavior | Header generation and output validation |
| Power BI | Some diagnosis selections did not filter encounters | Claim-primary-diagnosis path did not represent encounter filtering | Encounter-level primary diagnosis slicer |
| Power BI | Activating another relationship caused ambiguity | Multiple active filter routes | Preserve intended model paths; avoid indiscriminate Both |
| Power BI | Detail table multiplied encounter IDs | Unrelated encounter/diagnosis fields in visual | Intermediate diagnosis-grain table, later removed in final model |
| Power BI | Only primary diagnoses remained after adding encounter attributes | Relationship/filtering path excluded secondary rows | Intermediate `Diagnosis_Detail` workaround; final fix removed it and the problematic primary-diagnosis-key relationship |
| Power BI | `LOOKUPVALUE` error for NPI | Matched NPI to provider ID; extra comma | Match provider IDs and correct syntax |
| Power BI | PY encounter KPI blank | `Dim_Date` not marked as date table | Mark date table and use date-typed key |

Each of these decisions illustrates a core engineering lesson: diagnose the **grain, filter path, key and execution context** before adding more complex DAX or SQL.

---

## 17. Repository structure, reproducibility and documentation assets

The actual project directory tree and SQL script index are documented in **Section 10**. This replaces the earlier suggested folder structures, which did not match the repository.

### Reproduction guidance

1. Review `data/raw/` and `data/etl clean/` to understand source-to-clean transformations and ensure permitted data sharing.
2. Inspect `sql/1 - sp_drop_schema_tables.sql` before running it; dropping objects is destructive.
3. Review the table-creation, configuration, staging, ODS, date, DW, and export scripts in `sql/`.
4. Use `sql/0 - Run All ETL Stored Procedures.sql` only after checking its actual invocation sequence and dependencies.
5. Check the ETL audit tables, then run the SQL validation files in `validation/`.
6. Open `powerbi/Hospital Operations & Financial Analytics.pbix` and compare its model relationships with the screenshots in `docs/`.
7. Validate the patient, encounter, diagnosis and claim pages under representative year, patient and primary-diagnosis selections.

The README is the historical narrative; the SQL and PBIX files are the implementation sources of truth. Keep model screenshots and validation results in their existing folders rather than creating undocumented replacement paths.

---

## 18. Limitations, verification still needed, and production-readiness backlog

**Known or documented limitations**

- **SCD2 history:** Fact foreign keys resolved against active patient/provider versions during initial historical loading; true event-time historical attribution needs an explicit redesign.
- **Historical calculated diagnosis detail:** `Diagnosis_Detail` was removed from the final Power BI model; its refresh-time materialization and duplicated attributes are no longer current-model limitations.
- **Page-specific slicers:** The former `Diagnosis_Detail` slicer is no longer part of the final model. Verify final encounter-based slicer interactions with other clinical charts and page/report-level filters.
- **BCP / `xp_cmdshell`:** Local export technique is not a blanket production deployment recommendation; prefer approved orchestration and least-privilege execution.
- **Financial reconciliation:** Rounded checkpoints are not a replacement for exact claim-level accounting controls, late-arriving adjustments and status definitions.
- **Synthetic provenance:** Original dataset version, generated 2024–2025 changes, row-generation logic, and redistribution terms should be recorded from source scripts before publication.

**Final publication checklist**

- [ ] Commit and test all final SQL scripts in clean execution order.
- [ ] Attach the final Power BI model or sanitized screenshots and a DAX measure inventory.
- [ ] Verify final relationship directions and date-key joins from the saved PBIX/PBIP.
- [ ] Confirm all KPI totals by year and selected slicers with reproducible SQL.
- [ ] Test no-change reruns, new rows, changes, rejection paths, and rollback behavior.
- [ ] Check all diagnosis-page visual interactions, especially primary versus secondary diagnoses.
- [ ] Document source generation/modifications and license compliance.
- [ ] Scrub credentials, personal identifiers, and environment-specific paths.
- [ ] Add screenshots, run instructions, environment versions, and a concise project demo.

---

## 19. Portfolio summary and lessons learned

This project began as an investigation of nine related healthcare source datasets and developed into a SQL Server staging/ODS/warehouse pipeline with validation and audit controls, an outbound export workflow, and a multi-page Power BI report. The most valuable outcomes were not only the final metrics but the modeling decisions that made them credible: discovering the true source grain, separating Type 1 from SCD2 updates, investigating failed joins and export execution identities, reconciling claim and encounter totals, and solving a Power BI diagnosis filter-path problem without discarding clinically meaningful secondary diagnoses.

**Skills demonstrated:** SQL Server/T-SQL, relational profiling, ETL orchestration, data quality and exception handling, dimensional modeling, SCD2, incremental/upsert design, SQL reconciliation, BCP export, Power BI relationships and filter context, DAX time intelligence, clinical and revenue-cycle KPI design, and iterative troubleshooting.

**Documentation updated:** November 22, 2026 (final patient drillthrough model correction and SQL validation added). The README intentionally records both completed development milestones and remaining publication/production-hardening tasks.

---

## 20. Latest model troubleshooting: SCD Type 2, diagnosis history and patient drillthrough (November 21, 2026)

This section documents an **earlier troubleshooting session, subsequently superseded by the final model simplification in Section 21**, after the initial diagnosis-detail implementation described in Section 14. It records the problem, tests, the relationship adjustment, and the observed result without assuming the model has been exhaustively regression-tested.

### 20.1 SCD Type 2 introduced repeated business IDs

After the patient and provider dimensions were updated using SCD Type 2, `Dim_Patients[patient_id]` contained multiple historical versions for the same business identifier. Power BI refresh raised an error similar to:

> Column `patient_id` in table `Dim_Patients` contains a duplicate value, which is not allowed for columns on the one side of a many-to-one relationship.

This is expected when a **business ID** is reused across SCD2 versions. A `patient_id` is not a unique dimension-row key; `PatientKey` identifies an individual version. The corresponding provider-version key is `ProviderKey`. A direct *:1 relationship from encounters to SCD2 patients on `patient_id` cannot assume unique patient IDs on the dimension side.

The warehouse encounter transformation was examined because the encounter table initially lacked `PatientKey` and `ProviderKey`. Simply writing `d.PatientKey = s.PatientKey` in an `UPDATE` against `ods.Encounters` is invalid unless the ODS source actually contains those columns. Keys must be resolved by joining the appropriate warehouse dimensions to the encounter's patient/provider business IDs, with an explicit version-selection rule. The observed model later showed active relationships `Dim_Encounters[PatientKey]` → `Dim_Patients[PatientKey]` and `Dim_Encounters[ProviderKey]` → `Dim_Providers[ProviderKey]`.

**Historical limitation:** Mapping encounters to the current active dimension version can make the model operational, but does not necessarily preserve event-time SCD2 attribution. Correct historical joins require meaningful effective-date ranges. Do not change SCD2 dimension relationships to many-to-many solely to suppress duplicate-key errors.

### 20.2 Diagnosis detail needed all encounter diagnoses

The Diagnosis page needed one row per diagnosis associated with an encounter, including both `primary_flag = Yes` and `primary_flag = No`. The original claim-primary-diagnosis relationship could not satisfy that requirement by itself. Section 14 describes the diagnosis-grain `Diagnosis_Detail` calculated table, the encounter primary-diagnosis label repeated on its rows, and the reason `REMOVEFILTERS` alone was not sufficient to repair an unrelated visual join.

The detail table was expanded with patient, visit/discharge dates, department and provider NPI. Once the patient dimension became SCD2, simple `LOOKUPVALUE` expressions by `patient_id` could encounter multiple matching historical versions. The correct long-term rule is to select the intended version explicitly or resolve a version-specific surrogate key; `LOOKUPVALUE` does not accept a table-valued `FILTER(...)` argument as a search value. Provider lookup must match `provider_id` to `provider_id`, not `provider_id` to NPI.

### 20.3 Patient drillthrough failure despite active relationships

**Symptom:** On the Patient Detail page, Patient Profile, Encounter History, Labs, Medications and Claims could display a selected patient's data, but Diagnosis History was blank or produced **“Can't determine relationships between the fields.”** Adding fields from `Diagnosis_Detail` together with fields from `Dim_Patients` could cause a relationship error or a visual that never finished loading. A diagnostic measure could return a nonzero diagnosis count even while the detail visual failed; counting rows did not prove the visual had a valid join path.

**Observed relationships during investigation:**

| Relationship | Status observed before fix | Direction / grain |
|---|---|---|
| `Dim_Patient_Bridge[patient_id]` → `Dim_Patients[patient_id]` | Active | Bridge 1 → Patients *; single direction |
| `Dim_Patient_Bridge[patient_id]` → `Diagnosis_Detail[Patient ID]` | Active | Bridge 1 → Diagnosis Detail *; single direction |
| `Dim_Patients[PatientKey]` → `Dim_Encounters[PatientKey]` | Active | Patient version 1 → Encounters *; single direction |
| `Dim_Encounters[encounter_id]` → `Diagnosis_Detail[encounter_id]` | Inactive | Encounter 1 → Diagnosis Detail * |

The model had **two patient-related branches** from the bridge. With single-direction filtering, these did not necessarily provide a usable common relationship path when a visual combined `Dim_Patients` and `Diagnosis_Detail` fields. Simply seeing two active relationships to the bridge did **not** guarantee that Power BI could combine those fields in a table. Activating the encounter-to-diagnosis relationship while keeping the direct bridge-to-diagnosis relationship active also risked introducing multiple competing paths.

**Confirmed change:** The direct relationship

`Diagnosis_Detail[Patient ID]` → `Dim_Patient_Bridge[patient_id]`

was changed from **Active** to **Inactive**. Immediately after this **first relationship change**, the user confirmed that the visuals worked. The fix was therefore a **model relationship change**, not another calculated table, calculated column, or `REMOVEFILTERS` measure. It is important not to state that activating `Diagnosis_Detail[encounter_id]` → `Dim_Encounters[encounter_id]` was also required or performed: that second step was not confirmed and was explicitly deferred once the visuals began working.

**Post-fix checks:** Verify patient drillthrough, Diagnosis History rows, primary and secondary flags, date/department filters, and diagnosis slicer interactions after refresh. The immediate relationship error was reported resolved; a complete post-change regression across every page and slicer combination was not separately documented.

### 20.4 Why the resolution matters

This case shows that **active relationship** does not mean **usable filter path for every visual**. Power BI visuals can fail when they combine tables connected through separate branches that do not provide the required filtering or row association. Before introducing more DAX or more tables, inspect relationship cardinality, filter direction, active status, and whether the intended entity grain is patient, encounter, diagnosis, or claim.

The intervention documented at that stage was to **deactivate the competing direct patient-bridge-to-diagnosis-detail relationship and retest**. **This was not the final model design:** both calculated tables and the problematic primary-diagnosis-key relationship were later removed (Section 21). This is distinct from the earlier diagnosis-page fix, which used `Diagnosis_Detail` to preserve all diagnosis rows per encounter.

### 20.5 Recommended screenshots and evidence

Store the existing relationship-mapping screenshots and page screenshots under `docs/`, and SQL reconciliation queries/results under `validation/`. For this issue, useful evidence includes the relationship list before/after the change, the Patient Detail page showing Diagnosis History, and a primary-diagnosis selection that retains secondary diagnosis rows where intended. Do not invent filenames or assert that these particular screenshots have already been committed.

---

## 21. Final Power BI model correction: complete patient history across 2024–2025 (November 22, 2026)

> **Current implementation — supersedes the temporary solutions in Sections 14.6 and 20.** The final Power BI model no longer contains `Dim_Patient_Bridge` or `Diagnosis_Detail`. The problematic primary-diagnosis-key relationship was also removed. The warehouse's original diagnosis records remain available through `Dim_Diagnoses`; the change was to Power BI modeling and filter paths, not deletion of clinical diagnoses from the warehouse.

### 21.1 Business requirement

The **Patient Encounter Details** drillthrough page must display the selected patient's complete history for the chosen year: Patient Profile, Encounter History, Diagnosis History (both primary and secondary), Procedure History, Lab History, Medication History, and Claims & Billing History. The date/year selection must work for **both 2024 and 2025**, and the displayed encounter/diagnosis rows must agree with SQL Server.

### 21.2 Symptoms and investigation

- The Patient Profile could populate while encounter-dependent visuals were blank for 2025, even when SQL confirmed the patient had 2025 encounters.
- At one point the Patient Detail page showed only 2024 records or only primary diagnoses. SQL confirmed the missing 2025 rows existed in the warehouse.
- Diagnostic cards and SQL checks distinguished **underlying row availability** from **filter-path behavior**. For patient `PAT000153`, the model contained **13 encounters** across 2024–2025 and **19 diagnosis records** when the interfering primary-diagnosis-key path was removed.
- Tests confirmed the date dimension had 2025 dates and that encounter visit dates and date keys matched SQL. The symptoms were therefore not explained simply by missing source rows or an absent 2025 calendar.
- The earlier `Dim_Patient_Bridge` and `Diagnosis_Detail` approach, together with the primary-diagnosis-key relationship, added competing or restrictive paths. The primary-diagnosis-key path was particularly incompatible with a detail visual that must retain **secondary** diagnosis rows.

### 21.3 Final implemented resolution

1. **Removed `Dim_Patient_Bridge`** from the Power BI semantic model.
2. **Removed `Diagnosis_Detail`**, the previously created calculated diagnosis reporting table. Diagnosis History now uses the underlying diagnosis data rather than that duplicated calculated table.
3. **Removed the problematic primary-diagnosis-key relationship** from the Power BI model. A primary-diagnosis relationship must not restrict the complete diagnosis history to only primary rows.
4. Retained the patient/encounter-based filtering needed for drillthrough and verified the related history visuals against SQL. The final relationship diagram in `docs/` and saved `.pbix` are the sources of truth for exact active relationships, cardinalities, and directions; no additional unverified relationship settings are asserted here.
5. Preserved `primary_flag` as a **displayed diagnosis attribute** so both `Yes` and `No` records remain visible. Do not reapply a report-wide `primary_flag = Yes` filter to the full diagnosis-history page.

**Important distinction:** `Dim_Encounters[diagnosis_code]` represents the encounter's recorded primary diagnosis for encounter-level reporting; it is **not** a replacement for all rows in `Dim_Diagnoses`. Use the appropriate diagnosis grain when showing a patient's complete history. The encounter-level primary-diagnosis slicer described in Section 14.5 is a separate reporting concept; verify its final usage against the saved PBIX rather than assuming the removed primary-diagnosis-key relationship still exists.

### 21.4 SQL-to-Power BI validation

**Patient `PAT000066` — Parker Clark:** The following counts were checked against the displayed 2024 and 2025 Patient Detail screenshots and SQL Server results.

| History section | 2024 | 2025 |
|---|---:|---:|
| Encounter History | 1 | 4 |
| Diagnosis History (primary + secondary) | 2 | 5 |
| Claims & Billing History | 1 | 2 |
| Medication History | 1 | 3 |
| Lab History | 0 | 3 |
| Procedure History | 1 | 2 |

The patient profile appeared for both years, and the 2024 and 2025 history rows matched the SQL validation samples. The 2024 diagnosis history included one primary and one secondary diagnosis for its encounter; the 2025 diagnosis history included both primary and secondary flags across four encounters. These are **tested patient-level results**, not a claim that every patient and every report interaction has been exhaustively regression-tested.

A second diagnostic example, **`PAT000153`**, confirmed that removing the restrictive primary-diagnosis-key path exposed **13 encounters and 19 diagnosis rows** across the two years. This helped isolate the issue to model filtering rather than missing warehouse data.

### 21.5 Final-model documentation and regression checks

- Replace obsolete relationship screenshots in `docs/` with a current model screenshot showing the removed tables/relationship are absent.
- Save the updated `powerbi/Hospital Operations & Financial Analytics.pbix` and commit it alongside this README.
- Store corresponding SQL checks and evidence captures in `validation/` using the existing repository organization.
- Recheck 2024/2025 year slicers, patient drillthrough, all-diagnosis history, claims, labs, procedures, medications, and other pages after model refresh.
- Validate that patient/provider SCD2 active-version filtering remains consistent and that no diagnosis, encounter, or financial measures multiply rows through ambiguous joins.

**Engineering takeaway:** When detail records disappear despite being present in SQL, validate the source grain and filter propagation before adding calculated tables or bidirectional relationships. In this case, **simplifying the model** restored the intended complete patient history more effectively than maintaining the temporary bridge and calculated diagnosis-detail workarounds.

---

## Project Author & Technical Skills

### Yikum Shiferaw
**Senior Data Analyst | SQL Developer | Data Engineering | Data Warehousing | Business Intelligence & Analytics**

### Project: Hospital Operations & Financial Analytics

**End-to-End Healthcare Data Engineering, SQL ETL, Data Warehousing, Data Modeling, and Power BI Analytics**

This project was independently designed and developed by **Yikum Shiferaw** to demonstrate practical, end-to-end data engineering and business intelligence capabilities using a synthetic healthcare dataset.

The project covers the complete data lifecycle, from source data exploration and ingestion to automated ETL processing, dimensional data warehouse development, data quality validation, and interactive Power BI dashboards.

### Technical Skills Demonstrated

| Engineering / Analytics Area | Skills & Technologies |
|---|---|
| **Data Engineering** | ETL pipeline development, automated data ingestion, data transformation, incremental processing |
| **SQL Development** | Microsoft SQL Server, T-SQL, stored procedures, dynamic SQL, CTEs, joins, transactions, error handling |
| **Data Warehousing** | Staging, ODS, dimensional modeling, fact and dimension tables, surrogate keys, SCD Type 1 and Type 2 |
| **Data Modeling** | Star schema design, table relationships, cardinality, filter direction, SCD2 surrogate keys, elimination of unnecessary bridge tables, referential integrity |
| **Data Quality Engineering** | Data profiling, cleansing, deduplication, validation, exception handling, reconciliation |
| **ETL Automation** | Configuration-driven execution, dynamic BULK INSERT, BCP exports, ETL logging, execution auditing |
| **Business Intelligence** | Power BI Desktop, interactive dashboards, KPI development, report navigation, drillthrough |
| **DAX & Analytics** | CALCULATE, LOOKUPVALUE, ADDCOLUMNS, time intelligence, year-over-year comparisons, filter context |
| **Healthcare Analytics** | Patient utilization, encounters, diagnoses, procedures, medications, laboratory testing, provider performance |
| **Financial Analytics** | Healthcare claims, billing, payments, denials, revenue-cycle metrics, financial reconciliation |
| **Performance & Troubleshooting** | SQL query debugging, relationship ambiguity resolution, SCD2 key management, Power BI filter-path troubleshooting |
| **Project Documentation** | GitHub repository organization, technical documentation, SQL validation scripts, dashboard screenshots |

### Completed Project Deliverables

- Developed a multi-layer SQL Server ETL architecture: **Raw Data → Staging → ODS → Data Warehouse → Power BI**.
- Built reusable, configuration-driven SQL stored procedures for automated data processing.
- Implemented SCD Type 1 and Type 2 dimension management and incremental fact loading.
- Developed data quality controls, ETL audit logging, error handling, and reconciliation processes.
- Implemented automated SQL Server BCP data exports.
- Designed a relational and dimensional healthcare data model with historical patient and provider records.
- Developed a multi-page interactive Power BI dashboard covering healthcare operations, clinical utilization, and financial performance.
- Implemented DAX measures, year-over-year comparisons, slicers, and patient-level drillthrough.
- Investigated and resolved complex Power BI relationship, filtering, and SCD2 modeling issues.
- Created SQL validation scripts and supporting documentation to reconcile warehouse results with Power BI metrics.

### Project Focus

**Data Engineering • SQL ETL Development • Data Warehousing • Dimensional Modeling • Healthcare Analytics • Financial Analytics • Power BI • DAX • Data Quality • Automation • Troubleshooting**

### Author

**Yikum Shiferaw**  
Senior Data Analyst  
Healthcare Data Analytics | Data Engineering | Business Intelligence

*This project was developed as an independent technical portfolio project to demonstrate real-world data engineering, analytical problem-solving, SQL development, and business intelligence skills.*

---
