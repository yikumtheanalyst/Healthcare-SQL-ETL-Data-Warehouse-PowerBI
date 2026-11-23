USE ETL_DB;
GO

CREATE OR ALTER PROCEDURE sp_drop_schema_tables as
-- Drop foreign keys involving ODS tables

/*
exec sp_drop_schema_tables
*/
IF OBJECT_ID('tempdb..#temp_list') IS NOT NULL
    DROP TABLE #temp_list;

CREATE TABLE #temp_list (
    id INT,
    str_Source VARCHAR(50)
);

INSERT INTO #temp_list
VALUES
    (1, 'stg'),
    (2, 'ods'),
    (3, 'dw');

DECLARE @sql NVARCHAR(MAX)='';
DECLARE @SCHEMA_NAME VARCHAR(50)

declare @row int =1;
declare @counter int;

SELECT @counter=count(*) from #temp_list;

WHILE @row <=@counter
BEGIN
	SELECT @SCHEMA_NAME=str_Source from #temp_list where id =@row;

	SELECT @sql+=
		'ALTER TABLE '+QUOTENAME(OBJECT_SCHEMA_NAME(parent_object_id))+
		'.'+QUOTENAME(OBJECT_NAME(parent_object_id))+
		' DROP CONSTRAINT '+QUOTENAME(name)+';'+CHAR(13)
	FROM sys.foreign_keys
	WHERE OBJECT_SCHEMA_NAME(parent_object_id)=@SCHEMA_NAME
	   OR OBJECT_SCHEMA_NAME(referenced_object_id)=@SCHEMA_NAME;

	EXEC sp_executesql @sql;

	 --Drop all tables under ODS
	--SET @sql='';

	--SELECT @sql+=
	--	'DROP TABLE '+QUOTENAME(SCHEMA_NAME(schema_id))+
	--	'.'+QUOTENAME(name)+';'+CHAR(13)
	--FROM sys.tables
	--WHERE SCHEMA_NAME(schema_id)=@SCHEMA_NAME;

	--PRINT @sql;
	--EXEC sp_executesql @sql;


SET @row= @row+1
END

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'stg')
    EXEC('CREATE SCHEMA stg');  -- Extract layer

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'ods')
    EXEC('CREATE SCHEMA ods');  -- Transform layer

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'dw')
    EXEC('CREATE SCHEMA dw');   -- Warehouse layer

EXEC dw.usp_LoadDimDate @StartYear = 2020,  @EndYear = 2030;