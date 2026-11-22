use ETL_DB
go


/*
Overview - KPI Cards
*/

select b.CalendarYear, count(distinct encounter_id) as 'Total Encounters'
from dw.Dim_Encounters a inner join dw.DimDate b on a.VisitDateKey=b.dateKey group by b.CalendarYear ;
select b.CalendarYear, count(a.patient_id) as 'Total Patients'
from dw.Dim_Encounters a inner join dw.DimDate b on a.VisitDateKey=b.dateKey
group by b.CalendarYear ;
select b.CalendarYear, count(distinct encounter_id) as 'Total Billed Encounters'
,count(distinct c.claim_id) as 'Total Claims'
,Format(sum(c.BilledAmount),'C') as 'Total Billed Amount'
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount'
,Format(sum(c.DeniedAmount),'C') as 'Total Denied Amount'
,Format(sum(c.PaidAmount)/sum(c.BilledAmount),'P') as 'Payment $ Rate'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
group by b.CalendarYear ;

/*
Overview Monthly Trend
*/
declare @Year INT=2024;
select b.CalendarYear, b.MonthNumberOfYear, count(distinct encounter_id) as 'Total Billed Encounters'
,count(distinct c.claim_id) as 'Total Claims'
,Format(sum(c.BilledAmount),'C') as 'Total Billed Amount'
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount'
,Format(sum(c.DeniedAmount),'C') as 'Total Denied Amount'
,Format(sum(c.PaidAmount)/sum(c.BilledAmount),'P') as 'Payment $ Rate'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear, b.MonthNumberOfYear
Order by b.CalendarYear, b.MonthNumberOfYear
;

/*
Overview Total Billed vs Paid by Year
*/

select b.CalendarYear, count(distinct encounter_id) as 'Total Billed Encounters'
,count(distinct c.claim_id) as 'Total Claims'
,Format(sum(c.BilledAmount),'C') as 'Total Billed Amount'
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount'
,Format(sum(c.DeniedAmount),'C') as 'Total Denied Amount'
,Format(sum(c.PaidAmount)/sum(c.BilledAmount),'P') as 'Payment $ Rate'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear
;

/*
Overview - Procedure Cost by Department
*/
select b.CalendarYear, a.department
,Format(sum(d.procedure_cost),'C') as 'Total Procedure Amount' 
,sum(d.procedure_cost) as 'Procedure_cost_Sort'
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Procedures d on a.EncounterKey=d.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear, a.department
order by Procedure_cost_Sort desc
;

/*
Overview - Total Paid Amount by Insurance Type
*/
select b.CalendarYear, d.Insurance_Type
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount' 
,sum(c.BilledAmount) as 'PaidAmount_Sort'
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Patients d on c.PatientKey=d.PatientKey
where b.CalendarYear=@Year
group by b.CalendarYear, d.insurance_type
order by PaidAmount_Sort desc
;

/*
Overview - Top 5 Total Paid Amount by Department
*/
select TOP 5 b.CalendarYear, a.department
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount' 
,sum(c.BilledAmount) as 'PaidAmount_Sort'
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
where b.CalendarYear=@Year
group by b.CalendarYear, a.department
order by PaidAmount_Sort desc
;

/*
Overview - Top 5 Total Paid Amount by Primary Diagnosis
*/
select TOP 5 b.CalendarYear, d.diagnosis_description
,Format(sum(c.PaidAmount),'C') as 'Total Paid Amount' 
,sum(c.BilledAmount) as 'PaidAmount_Sort'
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Diagnoses d on c.PrimaryDiagnosisKey=d.DiagnosisKey
where b.CalendarYear=@Year
group by b.CalendarYear, d.diagnosis_description
order by PaidAmount_Sort desc
;

/*
Overview - Denial Reasons by Claim Count
*/
select b.CalendarYear, d.DenialReasonDescription
,count(c.claim_id) as 'Total Claim Count'
,sum(c.BilledAmount) as 'Total Billed Amount'
,sum(c.DeniedAmount) as 'Total Denied Amount'
,Format(sum(c.DeniedAmount)/sum(c.BilledAmount),'P') as 'Denied $ Rate'
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
where b.CalendarYear=@Year
group by b.CalendarYear, d.DenialReasonDescription
order by [Total Claim Count] desc
;


DECLARE @s INT-- = SELECTEDVALUE(Key_Insights[Seq])
DECLARE @topReason NVARCHAR(max)
-- = MAXX(TOPN(1, ALLSELECTED(Dim_Denial_Reason[DenialReasonDescription]), [Total Denied Claims], DESC), Dim_Denial_Reason[DenialReasonDescription])
DECLARE @topDept NVARCHAR(max)-- = MAXX(TOPN(1, ALLSELECTED(Dim_Encounters[Department]), [Total Paid Amount], DESC), Dim_Encounters[Department])
DECLARE @topDeptPaid Float-- = CALCULATE([Total Paid Amount], Dim_Encounters[Department] = topDept)
DECLARE @topIns NVARCHAR(max)-- = MAXX(TOPN(1, ALLSELECTED(Dim_Patients[insurance_type]), [Total Paid Amount], DESC), Dim_Patients[insurance_type])
DECLARE @topInsPaid FLOAT-- = CALCULATE([Total Paid Amount], Dim_Patients[insurance_type] = topIns)
DECLARE @TotalEncounters INT

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

SELECT
	@TotalBilledAmount	=sum(billedamount),
	@TotalPaidAmount	=sum(PaidAmount)
	,@TotalClaims		=count(distinct claim_id)
	,@TotalEncounters = count(distinct a.encounter_id)	
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
LEFT join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
where b.CalendarYear=@Year;

--Seq 1
SELECT
	@TotalBilledAmount	=sum(billedamount)
	,@TotalPaidAmount	=sum(PaidAmount)
	,@PaymentRate = sum(PaidAmount)/sum(billedamount) 
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
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
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
Inner join dw.Dim_Denial_Reason d on c.DenialReasonKey=d.DenialReasonKey
inner join dw.Dim_Claim_Status e on c.ClaimStatusKey=e.ClaimStatusKey and e.ClaimStatus='Denied'
where b.CalendarYear=@Year
order by count(c.claim_id) desc
;

SELECT TOP 1 @topReason=d.DenialReasonDescription
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
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
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Claim_Status e on c.ClaimStatusKey=e.ClaimStatusKey and e.ClaimStatus='Paid'
where b.CalendarYear=@Year
Group by a.department
order by sum(paidamount) desc
;
--Seq 4
SELECT TOP 1 
	@topIns=f.insurance_type
	,@topInsPaid = sum(paidamount)
from dw.Dim_Encounters a
inner join dw.DimDate b on a.VisitDateKey=b.dateKey
inner join dw.Fact_Claims c on a.EncounterKey=c.EncounterKey
inner join dw.Dim_Claim_Status e on c.ClaimStatusKey=e.ClaimStatusKey and e.ClaimStatus='Paid'
inner join dw.Dim_Patients f on c.PatientKey=f.PatientKey
where b.CalendarYear=@Year
Group by f.insurance_type
order by sum(paidamount) desc
;

--Seq 5
select
@TotalUnbilledEncounters=count(distinct a.encounter_id)
,@UnbilledRate =count(distinct a.encounter_id)/cast(@TotalEncounters as float)
from dw.dim_Encounters a
left join dw.Fact_Claims b on a.EncounterKey=b.EncounterKey
where b.EncounterKey is null
and Year(a.visit_date) = @Year
;

SELECT 
1 as 'Seq', 'Billed ' + Format(@TotalBilledAmount, 'C') + ' across ' +  Format(@TotalClaims, 'N')  + ' claims; collected ' + 
Format(@TotalPaidAmount, 'C')  + ' (' +  Format(@PaymentRate, 'P')  + ' of billed).' as 'Key Insight'
union all
Select 2 as 'Seq', 'Denials: ' + FORMAT(@TotalDeniedClaims, '#,0') + ' claims worth ' + FORMAT(@TotalDeniedAmount, '$#,0') + 
' (' + FORMAT(@DenialAmountRate, '0.0%') + ' of billed). Most frequent reason: ' + @topReason + '.' as 'Key Insight'
union all
Select 3 as 'Seq', @topDept + ' leads paid revenue at ' + FORMAT(@topDeptPaid, 'C') + 
' (' + FORMAT(@topDeptPaid/ @TotalPaidAmount, 'P') + ' of total).' as 'Key Insight'
union all
Select 4 as 'Seq', @topIns + ' is the largest payer at ' + FORMAT(@topInsPaid, '$#,0') + 
' (' + FORMAT((@topInsPaid/ @TotalPaidAmount), '0%') + ' of paid amount).' as 'Key Insight'
union all
Select 5 as 'Seq', FORMAT(@UnbilledRate, '0.0%') + 
' of encounters (' + FORMAT(@TotalUnbilledEncounters, '#,0') + ') have no claim on file - a potential revenue-capture gap.' as 'Key Insight'
;
