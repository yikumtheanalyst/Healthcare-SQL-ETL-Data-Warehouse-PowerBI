declare @patient_id varchar(50)='PAT000066', --PAT000153
@Year INT =2025

select 
'Patient Profile' as 'Valdiatin Source',
a.patient_id
,a.last_name
,a.first_name
,a.registration_date
,a.active_flag 
from  dw.Dim_Patients a
where a.patient_id=@patient_id

select 
'Encounters History' as 'Valdiatin Source',
a.encounter_id
,a.patient_id
,a.diagnosis_code
,a.visit_date 
from  dw.Dim_Encounters a
where a.patient_id=@patient_id
and YEAR(a.visit_date)=@Year
order by a.encounter_id

select 
	'Diagnosis History' as 'Valdiatin Source',
	a.encounter_id
	,a.patient_id
	,a.diagnosis_code
	,a.visit_date	
	,primary_flag
from  dw.Dim_Encounters a
inner join dw.Dim_Diagnoses b on a.encounter_id=b.encounter_id
where a.patient_id=@patient_id
and YEAR(a.visit_date)=@Year
order by a.encounter_id

SELECT
	'Claims History' as 'Valdiatin Source',
    e.encounter_id,
    e.patient_id,
    e.PatientKey AS EncounterPatientKey,
    e.visit_date
	,clm.claim_id
FROM dw.Dim_Encounters e
inner join dw.Fact_Claims clm on e.EncounterKey=clm.EncounterKey
WHERE e.patient_id = @patient_id
and YEAR(e.visit_date)=@Year
ORDER BY
--e.visit_date;
clm.claim_id

;

SELECT
	'Medications History' as 'Valdiatin Source',
    e.encounter_id,
    e.patient_id,
    e.PatientKey AS EncounterPatientKey,
    e.visit_date
	,dr.drug_name
FROM dw.Dim_Encounters e
inner join dw.Fact_Medications md on e.EncounterKey=md.EncounterKey
inner join dw.Dim_Medications dr on md.MedicationKey=dr.MedicationKey
WHERE e.patient_id = @patient_id
and YEAR(e.visit_date)=@Year
ORDER BY e.encounter_id;

select 
	'Lab Test History' as 'Valdiatin Source',
	a.encounter_id
	,a.patient_id
	,a.diagnosis_code
	,a.visit_date	
	,b.test_code
from  dw.Dim_Encounters a
inner join dw.Dim_Lab_Tests b on a.encounter_id=b.encounter_id
where a.patient_id=@patient_id
and YEAR(a.visit_date)=@Year
order by a.encounter_id


select 
	'Procedure History' as 'Valdiatin Source',
	a.encounter_id
	,a.patient_id
	,a.diagnosis_code
	,a.visit_date	
	,b.procedure_date
from  dw.Dim_Encounters a
inner join dw.Dim_Procedures b on a.encounter_id=b.encounter_id
where a.patient_id=@patient_id
and YEAR(a.visit_date)=@Year
order by a.encounter_id