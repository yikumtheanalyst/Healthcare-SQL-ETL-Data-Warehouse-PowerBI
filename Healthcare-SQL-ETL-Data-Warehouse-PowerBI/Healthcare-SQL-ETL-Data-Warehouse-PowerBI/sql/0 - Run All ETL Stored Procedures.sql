use ETL_DB
go

EXEC [dbo].[sp_drop_schema_tables];
EXECUTE [dbo].[sp_create_etl_tables]
EXECUTE sp_etl_file_configuration;
EXECUTE sp_dw_etl_file_configuration;
EXECUTE ETL_DB.[dbo].[sp_extract_files_to_stage];
EXECUTE ETL_DB.[dbo].sp_run_transform_from_stg_to_ods;

--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Patients';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Providers';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Encounters';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Diagnoses';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Lab_Tests';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Procedures';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='DIM_Medications';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Claim_Status';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Denial_Reason';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Dim_Appeal_Status';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Fact_Lab_Tests';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Fact_Medications';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Fact_Procedures';
--EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name='Fact_Claims';

declare @loop_counter int=1
declare @table_counter int=0
declare @var_table_name Varchar(50)
select @table_counter= count(*) from dw.ETL_Config_FileList where is_active=1;
while (@loop_counter <=@table_counter)
BEGIN
	select @var_table_name=table_name  from dw.ETL_Config_FileList where load_order=@loop_counter;
	print @var_table_name;

	EXEC	ETL_DB.dbo.sp_transform_odbs_for_production @table_name=@var_table_name;
SET @loop_counter = @loop_counter +1
END

BEGIN
	EXECUTE dbo.sp_export_data
END

--select distinct a.* from dw.Dim_Date a inner join dw.Dim_Encounters b on a.DateKey=b.VisitDateKey
--order by 2


--select * from dw.Dim_Patients order by patient_id
--select * from dw.Dim_Providers order by provider_id

--select * from ods.Providers