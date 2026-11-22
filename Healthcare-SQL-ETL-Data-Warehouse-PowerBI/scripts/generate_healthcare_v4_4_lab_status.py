"""Clinical-coherent synthetic healthcare generator. Python 3.9+, standard library only.
Run: python generate_healthcare_v3.py. Fixed seed, fictional patients and visits.
NDCs are 11-digit package identifiers; see NDC_REFERENCE.csv for product sources.
"""
import csv, random, zipfile
from bisect import bisect_right
from collections import Counter,defaultdict
from datetime import date,timedelta
from decimal import Decimal
from pathlib import Path

SEED=20261012
N_PATIENTS=5000
N_PROVIDERS=120
# Explicit yearly encounter targets for meaningful CY/PY comparisons.
ENCOUNTERS_BY_YEAR={2024:5500, 2025:6500}
N_ENCOUNTERS=sum(ENCOUNTERS_BY_YEAR.values())
# Registration cohorts; remaining patients registered before 2024.
REGISTRATIONS_BY_YEAR={2024:350, 2025:450}
OUTPUT=Path(__file__).resolve().parent/'healthcare_v4_4'
rng=random.Random(SEED)
# Separate random stream keeps the clinical generation reproducible.
billing_rng=random.Random(SEED + 42)
UNBILLED_RATE_BY_YEAR={2024:0.07, 2025:0.09}
unbilled_encounter_ids=set()
OUTPUT.mkdir(exist_ok=True)
COL={
'Patients':'patient_id first_name last_name dob age gender ethnicity insurance_type marital_status address city state zip phone email registration_date'.split(),
'Providers':'provider_id name department specialty npi inhouse location years_experience contact_info email'.split(),
'Encounters':'encounter_id patient_id provider_id visit_date visit_type department reason_for_visit diagnosis_code admission_type discharge_date length_of_stay status readmitted_flag'.split(),
'Diagnoses':'diagnosis_id encounter_id diagnosis_code diagnosis_description primary_flag chronic_flag'.split(),
'Lab_Tests':'lab_id encounter_id test_name test_code specimen_type test_result units normal_range test_date status'.split(),
'Medications':'medication_id encounter_id ndc drug_name dosage route frequency duration prescribed_date prescriber_id cost'.split(),
'Procedures':'procedure_id encounter_id procedure_code procedure_description procedure_date provider_id procedure_cost'.split(),
'Claims_and_Billing':'billing_id patient_id encounter_id insurance_provider payment_method claim_id claim_billing_date billed_amount paid_amount claim_status denial_reason'.split(),
'Denials':'claim_id denial_id denial_reason_code denial_reason_description denied_amount denial_date appeal_filed appeal_status appeal_resolution_date fina_outcome'.split()}
FIRST='Avery Jordan Morgan Taylor Alex Riley Casey Jamie Cameron Sam Devin Robin Quinn Parker Harper Dana'.split()
LAST='Miller Johnson Davis Wilson Brown Lee Patel Garcia Robinson Clark Young Allen King Wright Scott Hill'.split()
CITIES=[('Philadelphia','PA',19103),('Pittsburgh','PA',15222),('Harrisburg','PA',17101),('Allentown','PA',18101),('Lancaster','PA',17602),('Baltimore','MD',21201),('Wilmington','DE',19801)]
PAYERS=['Medicare','Medicaid','Aetna','Cigna','UnitedHealthcare','Humana','BCBS']
DEPTS={'Primary Care':'Family Medicine','Emergency Department':'Emergency Medicine','Cardiology':'Cardiology','Orthopedics':'Orthopedic Surgery','Endocrinology':'Endocrinology','Pulmonology':'Pulmonary Medicine','Neurology':'Neurology','Gastroenterology':'Gastroenterology','Urology':'Urology','General Surgery':'General Surgery','Obstetrics & Gynecology':'Obstetrics and Gynecology','Pediatrics':'Pediatrics'}
# Multiple clinically plausible specialties per organizational department.
# Keep DEPTS and its order unchanged: the existing encounter/provider generation
# uses it to assign departments and select appropriate clinical patterns.
DEPARTMENT_SPECIALTIES = {
    'Primary Care': ['Family Medicine', 'Internal Medicine', 'General Practice'],
    'Emergency Department': ['Emergency Medicine', 'Pediatric Emergency Medicine', 'Emergency Medicine - Critical Care'],
    'Cardiology': ['General Cardiology', 'Interventional Cardiology', 'Cardiac Electrophysiology'],
    'Orthopedics': ['Orthopedic Surgery', 'Sports Medicine', 'Hand Surgery'],
    'Endocrinology': ['Endocrinology', 'Diabetes & Metabolism', 'Reproductive Endocrinology'],
    'Pulmonology': ['Pulmonary Medicine', 'Critical Care Medicine', 'Sleep Medicine'],
    'Neurology': ['General Neurology', 'Vascular Neurology', 'Epilepsy'],
    'Gastroenterology': ['Gastroenterology', 'Hepatology', 'Advanced Endoscopy'],
    'Urology': ['General Urology', 'Urologic Oncology', 'Female Pelvic Medicine'],
    'General Surgery': ['General Surgery', 'Trauma Surgery', 'Surgical Oncology'],
    'Obstetrics & Gynecology': ['Obstetrics and Gynecology', 'Maternal-Fetal Medicine', 'Gynecologic Oncology'],
    'Pediatrics': ['General Pediatrics', 'Pediatric Cardiology', 'Pediatric Endocrinology'],
}
assert set(DEPARTMENT_SPECIALTIES) == set(DEPTS)
# Independent RNG ensures specialty diversity does not change other generated data.
specialty_rng = random.Random(SEED + 4300)

# Medication reference is package-level: (drug, strength/form, route, frequency, duration, cost, NDC, source URL)
DRUGS={
'acetaminophen':('Acetaminophen','500 mg tablet','Oral','As needed','5 days',8,'69618001101','https://ndclist.com/ndc/69618-011/package/69618-011-01'),
'ibuprofen':('Ibuprofen','400 mg tablet','Oral','As needed','5 days',11,'00904585340','https://ndclist.com/ndc/0904-5853/package/0904-5853-40'),
'lisinopril':('Lisinopril','10 mg tablet','Oral','Once daily','30 days',15,'51655099526','https://ndclist.com/ndc/51655-995/package/51655-995-26'),
'omeprazole':('Omeprazole','20 mg delayed-release capsule','Oral','Once daily','14 days',20,'71335960905','https://ndclist.com/ndc/71335-9609/package/71335-9609-5'),
'nitrofurantoin':('Nitrofurantoin','100 mg capsule','Oral','Twice daily','5 days',27,'71335225501','https://ndclist.com/ndc/71335-2255/package/71335-2255-1'),
'albuterol':('Albuterol sulfate','90 mcg/actuation inhaler','Inhalation','As needed','30 days',48,'70518207200','https://ndclist.com/ndc/70518-2072/package/70518-2072-0')}
# Only package codes with product-specific source references are emitted. No fabricated NDCs.
# Diagnosis: (ICD-10-CM, description, chronic, candidate labs, candidate meds, candidate procedures)
# These are illustrative correlations, not clinical treatment protocols.
DX={
'HTN':('I10','Essential (primary) hypertension',1,['bmp','lipid'],['lisinopril'],['office']),
'DM':('E11.9','Type 2 diabetes mellitus without complications',1,['a1c','bmp','lipid'],[],['office']),
'CHEST':('R07.9','Chest pain, unspecified',0,['cbc','bmp','troponin'],[],['ecg','chestx']),
'BACK':('M54.50','Low back pain, unspecified',0,[],['acetaminophen','ibuprofen'],['office']),
'KNEE':('M17.9','Osteoarthritis of knee, unspecified',1,[],['acetaminophen','ibuprofen'],['knee','office']),
'ASTHMA':('J45.909','Unspecified asthma, uncomplicated',1,[],['albuterol'],['spirometry','office']),
'UTI':('N39.0','Urinary tract infection, site not specified',0,['ua','culture'],['nitrofurantoin'],['office']),
'GERD':('K21.9','Gastro-esophageal reflux disease without esophagitis',1,[],['omeprazole'],['office']),
'MIGRAINE':('G43.909','Migraine, unspecified, not intractable',1,[],['acetaminophen','ibuprofen'],['office']),
'URI':('J06.9','Acute upper respiratory infection, unspecified',0,[],['acetaminophen'],['office']),
'PNEUMONIA':('J18.9','Pneumonia, unspecified organism',0,['cbc','bmp'],['acetaminophen'],['chestx']),
'ABD':('R10.9','Unspecified abdominal pain',0,['cbc','bmp','ua'],[],['office']),
'HF':('I50.9','Heart failure, unspecified',1,['bmp','cbc'],[],['ecg','echo']),
'HEAD':('S09.90XA','Unspecified injury of head, initial encounter',0,[],['acetaminophen'],['cthead']),
'PREVENT':('Z00.00','Encounter for general adult medical examination',0,['lipid'],[],['office']),
'THYROID':('E03.9','Hypothyroidism, unspecified',1,['tsh'],[],['office']),
'PREG':('Z34.90','Encounter for supervision of normal pregnancy, unspecified',0,['cbc','ua'],[],['office']),
'ANKLE':('S99.919A','Unspecified injury of unspecified ankle, initial encounter',0,[],['acetaminophen','ibuprofen'],['ankle']),
}
DEPT_DX={
'Primary Care':['HTN','DM','URI','BACK','GERD','PREVENT','THYROID','MIGRAINE'],
'Emergency Department':['CHEST','ABD','HEAD','ANKLE','PNEUMONIA','ASTHMA','UTI'],
'Cardiology':['CHEST','HTN','HF'],
'Orthopedics':['KNEE','BACK','ANKLE'],
'Endocrinology':['DM','THYROID','HTN'],
'Pulmonology':['ASTHMA','PNEUMONIA','URI'],
'Neurology':['MIGRAINE','HEAD','BACK'],
'Gastroenterology':['GERD','ABD'],
'Urology':['UTI','ABD'],
'General Surgery':['ABD','ANKLE','HEAD'],
'Obstetrics & Gynecology':['PREG','UTI','ABD'],
'Pediatrics':['URI','ASTHMA','PNEUMONIA','ANKLE']}
LAB={
'cbc':('Complete blood count with differential','85025','Blood','10^3/uL','4.0-11.0'),
'bmp':('Basic metabolic panel','80048','Blood','mg/dL','70-100 (glucose component)'),
'lipid':('Lipid panel','80061','Blood','mg/dL','<200 (total cholesterol)'),
'a1c':('Hemoglobin A1c','83036','Blood','%','4.0-5.6'),
'ua':('Urinalysis, automated with microscopy','81001','Urine','','Negative'),
'culture':('Urine culture','87086','Urine','','No growth'),
'troponin':('Troponin I','84484','Blood','ng/mL','<0.04'),
'tsh':('Thyroid stimulating hormone','84443','Blood','mIU/L','0.4-4.0')}
PROC={
'office':('99213','Established patient office evaluation',160),
'ecg':('93000','Electrocardiogram with interpretation',140),
'chestx':('71046','Chest radiography, two views',225),
'echo':('93306','Complete transthoracic echocardiography',1300),
'cthead':('70450','CT head without contrast',1150),
'knee':('73562','Knee radiography, three views',235),
'ankle':('73610','Ankle radiography, three views',245),
'spirometry':('94010','Spirometry',180)}
DENIAL=[('CO-16','Missing or incomplete claim information','Missing information'),('CO-18','Duplicate claim or service','Duplicate claim'),('CO-29','Timely filing limit expired','Timely filing'),('CO-50','Service not medically necessary','Medical necessity'),('CO-197','Precertification or authorization absent','Authorization'),('CO-96','Non-covered charge','Non-covered service')]

def choice(seq,weights=None): return rng.choices(seq,weights=weights,k=1)[0]
def dt(d): return d.isoformat() if d else ''
def dollars(x): return f'{x:.2f}'
def save(name,rows):
    with (OUTPUT/(name+'.csv')).open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.DictWriter(f,fieldnames=COL[name],extrasaction='raise');w.writeheader();w.writerows(rows)

# Assign each patient to a registration cohort, then randomize assignment.
assert sum(REGISTRATIONS_BY_YEAR.values()) < N_PATIENTS
registration_years = ([2023] * (N_PATIENTS - sum(REGISTRATIONS_BY_YEAR.values())))
for reg_year, count in REGISTRATIONS_BY_YEAR.items():
    registration_years.extend([reg_year] * count)
rng.shuffle(registration_years)

def random_registration_date(reg_year):
    if reg_year == 2023:
        return date(2020,1,1) + timedelta(days=rng.randrange((date(2024,1,1)-date(2020,1,1)).days))
    start=date(reg_year,1,1)
    return start + timedelta(days=rng.randrange((date(reg_year+1,1,1)-start).days))

patients=[]
for i in range(1,N_PATIENTS+1):
    dob=date(1935,1,1)+timedelta(days=rng.randrange(85*365)); age=2025-dob.year
    city,state,zipc=choice(CITIES);payer=choice(PAYERS,[14,16,14,14,16,11,15]);
    if age>=65 and rng.random()<.72:payer='Medicare'
    patients.append(dict(patient_id=f'PAT{i:06}',first_name=choice(FIRST),last_name=choice(LAST),dob=dt(dob),age=age,gender=choice(['Female','Male'],[51,49]),ethnicity=choice(['Not Hispanic or Latino','Hispanic or Latino','Unknown'],[65,25,10]),insurance_type=payer,marital_status=choice(['Single','Married','Divorced','Widowed']),address=f'{rng.randint(10,9999)} Maple St',city=city,state=state,zip=zipc,phone=f'555-01{rng.randrange(10)}-{rng.randrange(10000):04}',email=f'patient{i:06}@example.test',registration_date=dt(random_registration_date(registration_years[i-1]))))
providers=[]
for i in range(1,N_PROVIDERS+1):
    dept=list(DEPTS)[(i-1)%len(DEPTS)]
    providers.append(dict(provider_id=f'PRV{i:05}',name=f'Dr. {choice(FIRST)} {choice(LAST)}',department=dept,specialty=DEPARTMENT_SPECIALTIES[dept][(i - 1) // len(DEPTS) % len(DEPARTMENT_SPECIALTIES[dept])],npi=1000000000+i,inhouse='Yes',location=choice(['Main Campus','North Clinic','South Clinic']),years_experience=rng.randint(3,35),contact_info=f'555-600-{i:04}',email=f'provider{i:05}@example.test'))
bydept=defaultdict(list)
for p in providers:bydept[p['department']].append(p)
encounters=[]; diagnoses=[]; labs=[];meds=[];procedures=[]; claims=[];denials=[]
# Generate visit dates by year, then select only patients registered by each visit.
# Sorted registration dates and cumulative weights make weighted sampling efficient.
patient_weights=[rng.uniform(.3,2)**2 for _ in patients]
registered=sorted(zip((date.fromisoformat(p['registration_date']) for p in patients), patients, patient_weights), key=lambda x:x[0])
registration_dates=[item[0] for item in registered]
registered_patients=[item[1] for item in registered]
cumulative_weights=[]
running_weight=0.0
for _, _, weight in registered:
    running_weight += weight
    cumulative_weights.append(running_weight)

visit_days=[]
for year, count in ENCOUNTERS_BY_YEAR.items():
    start=date(year,1,1)
    days=(date(year+1,1,1)-start).days
    visit_days.extend(start+timedelta(days=rng.randrange(days)) for _ in range(count))
visit_days.sort()

last_visits=defaultdict(list)
for idx, visit in enumerate(visit_days,1):
    eligible_count=bisect_right(registration_dates, visit)
    if eligible_count == 0:
        raise ValueError(f'No registered patients eligible on {visit}')
    # Select a patient from eligible registrations using the original weighted sampling.
    draw=rng.random()*cumulative_weights[eligible_count-1]
    patient=registered_patients[bisect_right(cumulative_weights,draw)]
    dept=choice(list(DEPTS),[19,17,9,10,8,8,6,7,6,4,3,3])
    if dept=='Pediatrics' and date.fromisoformat(patient['dob']).year<2008:pass
    elif dept=='Pediatrics':dept='Primary Care'
    if dept=='Obstetrics & Gynecology' and patient['gender']!='Female':dept='Primary Care'
    provider=choice(bydept[dept]); candidates=DEPT_DX[dept]
    weights=[3.5 if x in ('URI','PNEUMONIA','ASTHMA') and visit.month in (12,1,2) else 1 for x in candidates]
    key=choice(candidates,weights);dx=DX[key]
    inpatient=dept in ('Emergency Department','Cardiology','General Surgery') and rng.random()<.13
    stay=rng.randint(1,5) if inpatient else 0
    discharge=visit+timedelta(days=stay)
    eid=f'ENC{idx:06}'
    readmit='Yes' if inpatient and any(0<(visit-prev).days<=30 for prev in last_visits[patient['patient_id']]) else 'No'
    last_visits[patient['patient_id']].append(visit)
    encounters.append(dict(encounter_id=eid,patient_id=patient['patient_id'],provider_id=provider['provider_id'],visit_date=dt(visit),visit_type='Inpatient' if inpatient else ('Emergency' if dept=='Emergency Department' else 'Outpatient'),department=dept,reason_for_visit=dx[1][:100],diagnosis_code=dx[0],admission_type='Urgent' if inpatient or dept=='Emergency Department' else 'Elective',discharge_date=dt(discharge),length_of_stay=stay,status='Discharged',readmitted_flag=readmit))
    diagnoses.append(dict(diagnosis_id=f'DX{len(diagnoses)+1:07}',encounter_id=eid,diagnosis_code=dx[0],diagnosis_description=dx[1],primary_flag='Yes',chronic_flag='Yes' if dx[2] else 'No'))
    if rng.random()<.26:
        secondary=choice([v for k,v in DX.items() if k!=key and k in ('HTN','DM','GERD','ASTHMA','THYROID')]);diagnoses.append(dict(diagnosis_id=f'DX{len(diagnoses)+1:07}',encounter_id=eid,diagnosis_code=secondary[0],diagnosis_description=secondary[1],primary_flag='No',chronic_flag='Yes' if secondary[2] else 'No'))
    service_charges=[]
    for labkey in dx[3]:
        if rng.random()>(.75 if labkey in ('a1c','troponin','ua') else .48):continue
        lab=LAB[labkey]; val={'cbc':f'{rng.uniform(4.1,12.7):.1f}','bmp':str(rng.randint(70,145)),'lipid':str(rng.randint(130,260)),'a1c':f'{rng.uniform(5.0,10.2):.1f}','ua':choice(['Negative','Positive'],[75,25]),'culture':choice(['No growth','Growth detected'],[65,35]),'troponin':f'{rng.uniform(.005,.12):.3f}','tsh':f'{rng.uniform(.5,7.0):.2f}'}[labkey]
        labs.append(dict(lab_id=f'LAB{len(labs)+1:07}',encounter_id=eid,test_name=lab[0],test_code=lab[1],specimen_type=lab[2],test_result=val,units=lab[3],normal_range=lab[4],test_date=dt(visit+timedelta(days=rng.randint(0,stay))),status='Completed'))
        service_charges.append(65+rng.randint(20,100))
    for drugkey in dx[4]:
        if rng.random()>.62:continue
        # This is an illustrative prescription event, not proof of dispensing.
        d=DRUGS[drugkey]
        meds.append(dict(medication_id=f'MED{len(meds)+1:07}',encounter_id=eid,ndc=d[6],drug_name=d[0],dosage=d[1],route=d[2],frequency=d[3],duration=d[4],prescribed_date=dt(visit),prescriber_id=provider['provider_id'],cost=dollars(d[5]*rng.uniform(.85,1.2))))
    for pkey in dx[5]:
        if rng.random()>(.9 if pkey=='office' else .72):continue
        p=PROC[pkey];cost=round(p[2]*rng.uniform(.8,1.35),2)
        procedures.append(dict(procedure_id=f'PROC{len(procedures)+1:07}',encounter_id=eid,procedure_code=p[0],procedure_description=p[1],procedure_date=dt(visit+timedelta(days=rng.randint(0,stay))),provider_id=provider['provider_id'],procedure_cost=dollars(cost)))
        service_charges.append(cost)
    if not service_charges:service_charges=[rng.randint(130,300)]
    # Claim-level charges derive from clinical activity; split selected encounters into facility/professional claims.
    if inpatient:service_charges.append(rng.randint(2500,12000))
    elif dept=='Emergency Department':service_charges.append(rng.randint(450,1600))
    # Completed clinical encounters can remain unbilled: e.g., documentation,
    # coding or submission pending. Do not create a claim or denial for them.
    # No fabricated zero-dollar claims: absence of billing means no claim row.
    if billing_rng.random() < UNBILLED_RATE_BY_YEAR[visit.year]:
        unbilled_encounter_ids.add(eid)
        continue
    groups=[service_charges]
    if len(service_charges)>1 and rng.random()<.25:
        groups=[service_charges[:1],service_charges[1:]]
    for grp in groups:
        claimid=f'CLM{len(claims)+1:07}'; billed=round(sum(grp)*rng.uniform(1.03,1.25),2)
        payer=patient['insurance_type']
        rate={'Medicare':.06,'Medicaid':.12,'Aetna':.07,'Cigna':.085,'UnitedHealthcare':.10,'Humana':.095,'BCBS':.065}[payer]
        rate+=.025 if dept=='Emergency Department' else 0
        billing=discharge+timedelta(days=rng.randint(2,48))
        denied=rng.random()<rate
        paid=0 if denied else round(billed*rng.uniform(.52,.88),2)
        reason=choice(DENIAL) if denied else None
        claims.append(dict(billing_id=f'BIL{len(claims)+1:07}',patient_id=patient['patient_id'],encounter_id=eid,insurance_provider=payer,payment_method='Insurance',claim_id=claimid,claim_billing_date=dt(billing),billed_amount=dollars(billed),paid_amount=dollars(paid),claim_status='Denied' if denied else 'Paid',denial_reason=reason[2] if denied else ''))
        if denied:
            denialdate=billing+timedelta(days=rng.randint(4,35));appealed=rng.random()<.32
            status=choice(['Approved','Denied','Pending'],[40,40,20]) if appealed else 'Not Appealed'
            resolved=denialdate+timedelta(days=rng.randint(15,80)) if appealed and status!='Pending' else None
            denials.append(dict(claim_id=claimid,denial_id=f'DEN{len(denials)+1:07}',denial_reason_code=reason[0],denial_reason_description=reason[1],denied_amount=dollars(billed),denial_date=dt(denialdate),appeal_filed='Yes' if appealed else 'No',appeal_status=status,appeal_resolution_date=dt(resolved),fina_outcome=status))

# V4.4: Lab orders may be incomplete. Use an independent RNG to preserve
# all pre-existing encounter, provider, diagnosis, medication and claim records.
# These are illustrative synthetic proportions, not clinical benchmarks.
lab_status_rng = random.Random(SEED + 4400)
LAB_STATUS_WEIGHTS = [
    ('Completed', 82),
    ('Pending', 9),
    ('In Progress', 5),
    ('Cancelled', 3),
    ('Rejected', 1),
]
lab_statuses = [x[0] for x in LAB_STATUS_WEIGHTS]
lab_weights = [x[1] for x in LAB_STATUS_WEIGHTS]
for lab_record in labs:
    status = lab_status_rng.choices(lab_statuses, weights=lab_weights, k=1)[0]
    lab_record['status'] = status
    if status != 'Completed':
        lab_record['test_result'] = ''
        # test_date is interpreted as result/completion date; no completed result yet.
        lab_record['test_date'] = ''

rows={'Patients':patients,'Providers':providers,'Encounters':encounters,'Diagnoses':diagnoses,'Lab_Tests':labs,'Medications':meds,'Procedures':procedures,'Claims_and_Billing':claims,'Denials':denials}
for name,data in rows.items():save(name,data)
# Validation
assert all(p['specialty'] in DEPARTMENT_SPECIALTIES[p['department']] for p in providers)
assert all(len({p['specialty'] for p in providers if p['department'] == d}) >= 2 for d in DEPTS)
assert len(encounters)==N_ENCOUNTERS
all_encounter_ids={e['encounter_id'] for e in encounters}
claimed_encounter_ids={c['encounter_id'] for c in claims}
assert unbilled_encounter_ids == all_encounter_ids - claimed_encounter_ids
assert not (unbilled_encounter_ids & claimed_encounter_ids)
assert all(float(c['billed_amount']) > 0 for c in claims)
assert Counter(date.fromisoformat(e['visit_date']).year for e in encounters)==Counter(ENCOUNTERS_BY_YEAR)
registration_lookup={p['patient_id']:date.fromisoformat(p['registration_date']) for p in patients}
assert all(registration_lookup[e['patient_id']] <= date.fromisoformat(e['visit_date']) for e in encounters)
assert Counter(date.fromisoformat(p['registration_date']).year for p in patients if date.fromisoformat(p['registration_date']).year in REGISTRATIONS_BY_YEAR)==Counter(REGISTRATIONS_BY_YEAR)
assert len({r['claim_id'] for r in claims})==len(claims)
assert len({r['medication_id'] for r in meds})==len(meds)
assert len({r['lab_id'] for r in labs})==len(labs)
assert len({r['procedure_id'] for r in procedures})==len(procedures)
# Exactly one primary diagnosis per encounter, including after CSV generation.
primary_counts = Counter(d['encounter_id'] for d in diagnoses if d['primary_flag'] == 'Yes')
encounter_ids = {e['encounter_id'] for e in encounters}
assert len({d['diagnosis_id'] for d in diagnoses}) == len(diagnoses), 'Duplicate diagnosis_id'
assert set(primary_counts) == encounter_ids, 'Encounter missing a primary diagnosis'
assert all(count == 1 for count in primary_counts.values()), 'Multiple primary diagnoses for encounter'
assert all(d['primary_flag'] in ('Yes', 'No') for d in diagnoses), 'Invalid primary_flag'
assert all(d['encounter_id'] in encounter_ids for d in diagnoses), 'Orphan diagnosis'
assert all(Counter(d['encounter_id'] for d in diagnoses)[eid] >= 1 for eid in encounter_ids)

assert len(denials)==sum(c['claim_status']=='Denied' for c in claims)
assert all(m['ndc'].isdigit() and len(m['ndc'])==11 for m in meds)
assert all(m['ndc']==DRUGS[next(k for k,v in DRUGS.items() if v[0]==m['drug_name'])][6] for m in meds)
assert all(c['paid_amount']=='0.00' for c in claims if c['claim_status']=='Denied')
with (OUTPUT/'NDC_REFERENCE.csv').open('w',newline='',encoding='utf-8') as f:
    w=csv.writer(f);w.writerow(['ndc_11','drug_name','strength_form','source_url'])
    for d in DRUGS.values():w.writerow([d[6],d[0],d[1],d[7]])
with (OUTPUT/'README.txt').open('w',encoding='utf-8') as f:
    f.write('HEALTHCARE SYNTHETIC V4.1 - ALL PATIENTS AND EVENTS FICTIONAL\n')
    f.write(f'Seed: {SEED}; annual encounter targets: {ENCOUNTERS_BY_YEAR}; registration cohorts: {REGISTRATIONS_BY_YEAR}; billing/appeals may continue into 2026.\n')
    for name,data in rows.items():f.write(f'{name}: {len(data):,}\n')
    for name,field in [('Billed','billed_amount'),('Paid','paid_amount')]:f.write(f'{name} amount: {sum(Decimal(c[field]) for c in claims):,.2f}\n')
    f.write(f'Denied amount: {sum(Decimal(d["denied_amount"]) for d in denials):,.2f}\n')
    f.write(f'Unbilled encounter counts by year: {dict(sorted(Counter(int(e["visit_date"][:4]) for e in encounters if e["encounter_id"] in unbilled_encounter_ids).items()))}\\n')
    f.write('Unbilled encounters have no claim row; do not equate denied claims with unbilled encounters.\\n')
    f.write('Drug NDC is 11-character TEXT (package-level). Use NDC_REFERENCE.csv for lookup provenance.\n')
    f.write('Providers retain their original IDs, NPIs, and departments; specialties vary within departments.\n')
    f.write('Prescriptions are not pharmacy dispensing claims. Medical claim billed amounts exclude prescribed drug costs.\n')
    f.write('Clinical patterns are illustrative synthetic associations, not treatment guidelines or validated utilization benchmarks.\n')
    f.write('NDC listing does not establish marketing status during each historical service date.\n')
    f.write('For staging/ODS/DW, add ndc VARCHAR(11) NULL to medication tables and map in load procedures.\n')
    f.write('V4.3 regenerates all files as one set. Reset/reconcile prior synthetic warehouse loads before reimport; reused IDs can conflict with old DW records.\n')
print('Unbilled encounters by visit year:',
      dict(sorted(Counter(int(e['visit_date'][:4]) for e in encounters
                          if e['encounter_id'] in unbilled_encounter_ids).items())))
print('Billed encounters:', len(claimed_encounter_ids))
print('Unbilled encounters:', len(unbilled_encounter_ids))
print('Generated',OUTPUT)
for k,v in rows.items():print(f'{k:22} {len(v):>7,}')

print('Encounter counts by visit year:',dict(sorted(Counter(date.fromisoformat(e['visit_date']).year for e in encounters).items())))
print('Patient registrations by year:',dict(sorted(Counter(date.fromisoformat(p['registration_date']).year for p in patients).items())))
print('Distinct patients seen by year:', {y:len({e['patient_id'] for e in encounters if date.fromisoformat(e['visit_date']).year==y}) for y in ENCOUNTERS_BY_YEAR})

print('Primary diagnoses validated:', len(primary_counts), 'of', len(encounters), 'encounters (exactly one each)')
