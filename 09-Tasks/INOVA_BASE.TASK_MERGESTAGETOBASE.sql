create or replace task {{environment}}_INGESTION_DB.INOVA_BASE.TASK_MERGESTAGETOBASE
	warehouse=DEVELOPER_WH
	schedule='USING CRON 00 11 * * * America/Los_Angeles'
	as CALL {{environment}}_INGESTION_DB.MASTER.MERGESTAGETOBASE(0,'{{environment}}',CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,10);