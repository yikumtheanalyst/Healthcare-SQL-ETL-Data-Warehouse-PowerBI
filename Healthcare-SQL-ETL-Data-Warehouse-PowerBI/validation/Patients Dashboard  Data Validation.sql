use ETL_DB
go


/*
Patients - KPI Cards
*/

declare @maxPY date, @maxCY date

Select @maxPY = max(registration_date) from dw.Dim_Patients where Year(registration_date) <=2024;
Select @maxCY = max(registration_date) from dw.Dim_Patients where Year(registration_date) <=2025;

select '2024' as Yr,count(distinct patient_id) as 'Patients' from dw.Dim_Patients c where  c.active_flag=1 and c.registration_date <=@maxPY
union all
select '2025' as Yr,count(distinct patient_id) as 'Patients' from dw.Dim_Patients c where  c.active_flag=1 and c.registration_date <=@maxCY

select b.CalendarYear, count(a.patient_id) as 'Total Patients'
from dw.Dim_Encounters a inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
group by b.CalendarYear ;
select b.CalendarYear, count(distinct encounter_id) as 'Total Billed Encounters'
,count(distinct c.claim_id) as 'Total Claims'
,Format(sum(c.BilledAmount),'C') as 'Total Billed Amount'
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount'
,Format(sum(c.DeniedAmount),'C') as 'Total Denied Amount'
,Format(sum(c.PaidAmount)/sum(c.BilledAmount),'P') as 'Payment $ Rate'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
group by b.CalendarYear ;

/*
Patients Monthly Trend
*/
declare @Year INT=2024;
select b.CalendarYear, b.MonthNumberOfYear, count(distinct encounter_id) as 'Total Billed Encounters'
,count(distinct c.claim_id) as 'Total Claims'
,Format(sum(c.BilledAmount),'C') as 'Total Billed Amount'
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount'
,Format(sum(c.DeniedAmount),'C') as 'Total Denied Amount'
,Format(sum(c.PaidAmount)/sum(c.BilledAmount),'P') as 'Payment $ Rate'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear, b.MonthNumberOfYear
Order by b.CalendarYear, b.MonthNumberOfYear
;

/*
Patients Total Billed vs Paid by Year
*/

select b.CalendarYear, count(distinct encounter_id) as 'Total Billed Encounters'
,count(distinct c.claim_id) as 'Total Claims'
,Format(sum(c.BilledAmount),'C') as 'Total Billed Amount'
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount'
,Format(sum(c.DeniedAmount),'C') as 'Total Denied Amount'
,Format(sum(c.PaidAmount)/sum(c.BilledAmount),'P') as 'Payment $ Rate'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear
;

/*
Patients - Procedure Cost by Department
*/
select b.CalendarYear, a.department
,Format(sum(d.procedure_cost),'C') as 'Total Procedure Amount' 
,sum(d.procedure_cost) as 'Procedure_cost_Sort'
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Procedures d on a.EncounterKey=d.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear, a.department
order by Procedure_cost_Sort desc
;

/*
Patients - Total Paid Amount by Insurance Type
*/
select b.CalendarYear, d.Insurance_Type
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount' 
,sum(c.BilledAmount) as 'PaidAmount_Sort'
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Patients d on c.PatientKey=d.PatientKey
where b.CalendarYear=@Year
group by b.CalendarYear, d.insurance_type
order by PaidAmount_Sort desc
;

/*
Patients - Top 5 Total Paid Amount by Department
*/
select TOP 5 b.CalendarYear, a.department
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount' 
,sum(c.BilledAmount) as 'PaidAmount_Sort'
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear, a.department
order by PaidAmount_Sort desc
;

/*
Patients - Top 5 Total Paid Amount by Primary Diagnosis
*/
select TOP 5 b.CalendarYear, d.diagnosis_description
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount' 
,sum(c.BilledAmount) as 'PaidAmount_Sort'
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Diagnoses d on c.PrimaryDiagnosisKey=d.DiagnosisKey
where b.CalendarYear=@Year
group by b.CalendarYear, d.diagnosis_description
order by PaidAmount_Sort desc
;

/*
Patients - Denial Reasons by Claim Count
*/
select b.CalendarYear, d.DenialReasonDescription
,count(c.claim_id) as 'Total Claim Count'
,sum(c.BilledAmount) as 'Total Billed Amount'
,sum(c.DeniedAmount) as 'Total Denied Amount'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
where b.CalendarYear=@Year
group by b.CalendarYear, d.DenialReasonDescription
order by [Total Claim Count] desc
;


--Patients Key Insights = VAR s = SELECTEDVALUE(Key_Insights[Seq])
DECLARE @topAge Varchar(20) --MAXX(TOPN(1, ALLSELECTED(Dim_Patients[Age Group]), @TotalEncounters, DESC), Dim_Patients[Age Group])
DECLARE @topAgeShare Float-- = DIVIDE(CALCULATE(@TotalEncounters, Dim_Patients[Age Group] = topAge), @TotalEncounters)

DECLARE @s INT-- = SELECTEDVALUE(Key_Insights[Seq])
DECLARE @topReason NVARCHAR(max)
-- = MAXX(TOPN(1, ALLSELECTED(Dim_Denial_Reason[DenialReasonDescription]), [Total Denied Claims], DESC), Dim_Denial_Reason[DenialReasonDescription])
DECLARE @topDept NVARCHAR(max)-- = MAXX(TOPN(1, ALLSELECTED(Dim_Encounters[Department]), [Total Paid Amount], DESC), Dim_Encounters[Department])
DECLARE @topDeptPaid Float-- = CALCULATE([Total Paid Amount], Dim_Encounters[Department] = topDept)
DECLARE @topIns NVARCHAR(max)-- = MAXX(TOPN(1, ALLSELECTED(Dim_Patients[insurance_type]), [Total Paid Amount], DESC), Dim_Patients[insurance_type])
DECLARE @topInsPaid FLOAT-- = CALCULATE([Total Paid Amount], Dim_Patients[insurance_type] = topIns)
DECLARE @TotalEncounters INT
DECLARE @TotalPatients INT

DECLARE @TotalBilledAmount float=0.00,
		@TotalPaidAmount Float=0.00,
		@TotalClaims INT=0,
		@TotalDeniedAmount float=0.00,
		@TotalUnbilledEncounters INT=0,
		@PaymentRate float =0.00,
		@DenialAmountRate float=0.00,
		@UnbilledRate Float =0.00,
		@DenialAmount float=0.00,
		@TotalDeniedClaims INT=0

DECLARE @PatientsSeen INT
		,@EncountersperPatient INT
		,@AvgPatientAge Float
		,@OutpatientShare float
		,@InpatientShare Float
		,@EmergencyShare Float
		,@AvgInpatientLOS Float
		,@InpatientReadmissionRate Float
		,@GovernmentPayerShare Float
		,@ChronicPatientShare Float,
		@Inpatient_Encounters float

SELECT
	@TotalBilledAmount	=sum(billedamount),
	@TotalPaidAmount	=sum(PaidAmount)
	,@TotalClaims		=count(distinct claim_id)
	,@TotalEncounters = count(distinct a.encounter_id)
	,@TotalPatients = count(distinct a.patient_id)
	,@PatientsSeen = count(distinct c.PatientKey)
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
--LEFT join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
where b.CalendarYear=@Year;

--Seq 1
SELECT
	@TotalBilledAmount	=sum(billedamount)
	,@TotalPaidAmount	=sum(PaidAmount)
	,@PaymentRate = sum(PaidAmount)/sum(billedamount) 
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
order by COUNT(c.claim_id) desc
;

--Seq 2
SELECT
	@TotalDeniedClaims	=count(c.claim_id)
	,@TotalDeniedAmount	=sum(DeniedAmount)
	,@DenialAmountRate = sum(DeniedAmount)/@TotalBilledAmount
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
Inner join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
inner join dw.Dim_Claim_Status e on c.ClaimStatusKey=e.ClaimStatusKey and e.ClaimStatus='Denied'
where b.CalendarYear=@Year
order by count(c.claim_id) desc
;

SELECT TOP 1 @topReason=d.DenialReasonDescription
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
Inner join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
inner join dw.Dim_Claim_Status e on c.ClaimStatusKey=e.ClaimStatusKey and e.ClaimStatus='Denied'
where b.CalendarYear=@Year
Group by d.DenialReasonDescription
order by count(c.claim_id) desc
;
--Seq 3
SELECT TOP 1 
	@topDept=a.department
	,@topDeptPaid = sum(paidamount)
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Claim_Status e on c.ClaimStatusKey=e.ClaimStatusKey and e.ClaimStatus='Paid'
where b.CalendarYear=@Year
Group by a.department
order by sum(paidamount) desc
;
--Seq 4
SELECT
	@TotalEncounters= count(distinct a.encounter_id)
	,@PatientsSeen=count(distinct a.patient_id)
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
left join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
;

select @PatientsSeen as 'PatientsSeen';
--Seq 5
select
@TotalUnbilledEncounters=count(distinct a.encounter_id)
,@UnbilledRate =count(distinct a.encounter_id)/cast(@TotalEncounters as float)
from dw.dim_Encounters a
left join dw.Fact_Claims b on a.EncounterKey=b.EncounterKey
where b.EncounterKey is null
and Year(a.visit_date) = @Year
; 

Select @AvgPatientAge = AVG(age) from dw.Dim_Patients where Year(registration_date) <=@Year;
SET @EncountersperPatient = cast(@TotalEncounters as float) / cast(@TotalPatients as float)


drop table #Visits
SELECT
	a.visit_type
	,count(distinct a.encounter_id)	 as 'Visit Counts'
	,count(distinct a.encounter_id)	/ Cast(@TotalEncounters as float)  as 'Visit %'
	,CAST(AVG(length_of_stay) as float) as 'AvgInpatientLOS'
	,SUM(cast(readmitted_flag as int)) as 'InpatientReadmissionRate'
	,count(a.patient_id) as 'Inpatient_Encounters'

into #Visits
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
left join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
left join dw.Dim_Patients f on c.PatientKey=f.PatientKey
where b.CalendarYear=@Year
Group by a.visit_type
;

drop table #payers
select 
case when  insurance_type in('Medicare','Medicaid') then 'Government' else 'Commercial' end as 'insurance_type', 
count(a.encounter_id) as TotalEncounters
INTO #payers
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
left join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
left join dw.Dim_Patients f on c.PatientKey=f.PatientKey
where b.CalendarYear=@Year 
group by 
case when  insurance_type in('Medicare','Medicaid') then 'Government' else 'Commercial' end
;

select @GovernmentPayerShare=TotalEncounters/cast(@TotalEncounters as float) from #payers where insurance_type='Government';
select
@ChronicPatientShare=count(distinct a.patient_id)/cast(@PatientsSeen as float)
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
inner join dw.Dim_Diagnoses g on a.encounter_id=g.encounter_id
where b.CalendarYear=@Year
and chronic_flag=1
;

declare  @topAge_Encounters float;

SELECT TOP 1
@topAge=case
	when     age < 18 then '0-17'
	when	age < 35 then '18-34'
	when    age < 50 then '35-49'
	when    age < 65 then '50-64'
	when   age >= 65 then '65+'
	else ''
	end
,@topAge_Encounters=count(distinct a.encounter_id)
from dw.Dim_Encounters a
inner join dw.Dim_Date b on a.VisitDateKey=b.dateKey
left join dw.Dim_Patients f on a.patient_id=f.patient_id
left join dw.Dim_Diagnoses g on a.encounter_id=g.encounter_id
where b.CalendarYear=2024
Group by
case
	when     age < 18 then '0-17'
	when	age < 35 then '18-34'
	when    age < 50 then '35-49'
	when    age < 65 then '50-64'
	when   age >= 65 then '65+'
	else ''
	end
Order by count(distinct a.encounter_id) desc
;

SET @topAgeShare= @topAge_Encounters/cast(@TotalEncounters as float);

Select @InpatientShare = [Visit %] From #Visits where visit_type='Inpatient';
Select @OutpatientShare = [Visit %] From #Visits where visit_type='Outpatient';
Select @EmergencyShare = [Visit %] From #Visits where visit_type='Emergency';
Select @AvgInpatientLOS = round(AvgInpatientLOS, 2) From #Visits where visit_type='Inpatient';
Select @InpatientReadmissionRate = InpatientReadmissionRate From #Visits where visit_type='Inpatient';
Select @Inpatient_Encounters = Inpatient_Encounters From #Visits where visit_type='Inpatient';


Select 1, FORMAT(@PatientsSeen, 'N') + ' patients generated ' + FORMAT(@TotalEncounters, 'N') 
+ ' encounters (' + CAST(round(@EncountersperPatient,2) as  Varchar) + ' per patient); average age ' + FORMAT(@AvgPatientAge, 'N') + '.'  as 'Key Insight'
union all
Select 2, 'Visit mix: ' + FORMAT(isnull(@OutpatientShare,0), 'P') + ' outpatient, ' + FORMAT(isnull(@EmergencyShare,0), 'P') 
+ ' emergency, ' + FORMAT(isnull(@InpatientShare,0), 'P') + ' inpatient.'  as 'Key Insight'
union all
Select 3, 'Inpatient stays average ' + Cast(@AvgInpatientLOS as varchar) + ' days; readmission rate is ' 	
+ FORMAT((@InpatientReadmissionRate/cast(@Inpatient_Encounters as float)), 'P') + ' of inpatient encounters.'  as 'Key Insight'
union all
Select 4, Cast(@topAge as varchar) + ' is the busiest age group, driving ' + FORMAT(@topAgeShare, 'P') + ' of encounters.' as 'Key Insight'
union all
Select 5, FORMAT(@GovernmentPayerShare, 'P') + ' of encounters are Medicare/Medicaid; ' + FORMAT(@ChronicPatientShare, 'P') 
+ ' of patients seen carry a chronic diagnosis.'  as 'Key Insight'
;





select
b.CalendarYear ,d.diagnosis_description as 'Diagnosis'
,count(a.encounter_id) as 'Total Encounters'
,count(distinct a.encounter_id) as 'Unique Total Encounters'
,count(a.patient_id) as 'Patients Seen'
,count(distinct a.patient_id) as 'Unique Patients Seen'
from		dw.Dim_Encounters	a
inner join	dw.Dim_Date			b on a.VisitDateKey=b.dateKey
Left join	dw.Dim_Diagnoses	d on a.encounter_id=d.encounter_id and d.primary_flag='Yes'
group by b.CalendarYear ,d.diagnosis_description

order by  d.diagnosis_description ,b.CalendarYear
;


select * from dw.Dim_Diagnoses order by encounter_id
