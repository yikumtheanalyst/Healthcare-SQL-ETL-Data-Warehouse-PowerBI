USE ETL_DB
Go

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
-- =============================================
-- Author:		Yikum Shiferaw
-- Create date: 2/28/2026
-- Description:	Loads ETL Configuration files
-- =============================================
/*

EXECUTE sp_dw_etl_file_configuration;

*/

CREATE OR ALTER PROCEDURE sp_dw_etl_file_configuration
AS
BEGIN


	SET NOCOUNT ON;
    
	/* ==============================
	   Load Production Configuration Source files
	   ============================== */

	IF NOT EXISTS (
    SELECT 1
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE t.name = 'ETL_Config_FileList'
    AND s.name = 'dw'
	)

	CREATE TABLE dw.ETL_Config_FileList
	(
		config_id INT IDENTITY(1,1) PRIMARY KEY,
		table_name NVARCHAR(100),		
		load_order INT,
		is_active BIT DEFAULT 1
	);

	declare @table_populated int;

	select @table_populated= count(*) from dw.ETL_Config_FileList;

	IF @table_populated=0
	BEGIN
		INSERT INTO dw.ETL_Config_FileList (table_name, load_order,is_active)
		VALUES
		('Dim_Patients' ,1,1)
		,('Dim_Providers' ,2,1)
		,('Dim_Encounters' ,3,1)
		,('Dim_Diagnoses' ,4,1)
		,('Dim_Lab_Tests' ,5,1)
		,('Dim_Procedures' ,6,1)
		,('Dim_Medications' ,7,1)
		,('Dim_Claim_Status' ,8,1)
		,('Dim_Denial_Reason' ,9,1)
		,('Dim_Appeal_Status' ,10,1)
		,('Fact_Lab_Tests' ,11,1)	
		,('Fact_Medications' ,12,1)
		,('Fact_Procedures' ,13,1)
		,('Fact_Claims' ,14,1)
	select * from dw.ETL_Config_FileList;
	END
	ELSE
	BEGIN
		select * from dw.ETL_Config_FileList;
	END

END

GO

/*

EXECUTE sp_dw_etl_file_configuration;

*/
