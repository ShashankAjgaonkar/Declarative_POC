CREATE OR REPLACE PROCEDURE {{environment}}_INGESTION_DB.INOVA_BASE.SP_MERGEGUARANTORS("BASEUPDATEDDATE" TIMESTAMP_NTZ(9), "ISHISTORICAL" NUMBER(38,0), "PARTNERSK" NUMBER(38,0))
RETURNS VARCHAR(16777216)
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
	CURRENTTIME TIMESTAMP DEFAULT :BASEUPDATEDDATE;
	NUMBEROFROWSINSERTED INTEGER;
	NUMBEROFROWSUPDATED INTEGER;
	QID VARCHAR;
	RUNTIME INTEGER;
BEGIN
	BEGIN TRANSACTION;
	
		IF (ISHISTORICAL = 1) THEN
				
				UPDATE {{environment}}_INGESTION_DB.GOHEALTH_DW.GUARANTORS SET BASEUPDATEDDATE=:CURRENTTIME,SNOWFLAKE_DELETED_FLAG = 1,SNOWFLAKE_UPDATED_AT = :CURRENTTIME 
				WHERE PartnerSK=:PARTNERSK;
				
				SELECT LAST_QUERY_ID() as last_qid INTO :QID;
				select execution_time/1000 into :RUNTIME
				from table({{environment}}_INGESTION_DB.information_schema.query_history()) WHERE QUERY_ID=:QID;
				SELECT  T.$1 AS NOOFROWSUPDATED INTO :NUMBEROFROWSUPDATED  FROM TABLE(RESULT_SCAN(:QID)) T;
				INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
				(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
				VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',:RUNTIME,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',0,:NUMBEROFROWSUPDATED,''SUCCESS'',''UPDATE FOR ISHISTORICAL=1 COMPLETED'');

				INSERT INTO {{environment}}_INGESTION_DB.GOHEALTH_DW.GUARANTORS(
				PartnerSK
				,GuarantorId
				,FirstName
				,LastName
				,MiddleInitial
				,AddressLine1
				,AddressLine2
				,City
				,StateSK
				,CountrySK
				,Zipcode
				,ActiveFlag
				,WorkPhone
				,HomePhone
				,TotalBalance
				,InsuranceBalance
				,PatientBalance
				,EmploymentStatusSK
				,DateOfBirth
				,SexSK
				,AccountTypeSK
				,UserType
				,GuarantorAccount
				,AccountName
				,BaseCreatedDate,BaseUpdatedDate,BaseDeletedFlag
				,SNOWFLAKE_CREATED_AT,SNOWFLAKE_UPDATED_AT,SNOWFLAKE_DELETED_FLAG 
				) 

				WITH StageTable AS (
				SELECT  
					psk.PartnerSK as PartnerSK
					  --,s.DWID  as GuarantorId
						,s.ACCOUNT_ID as GuarantorId
						,case when charindex('', '', s.ACCOUNT_NAME, 1)>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(left(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME)), len(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME))) - charindex('' '', reverse(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME))), 1)),1) 
						when charindex('','', s.ACCOUNT_NAME, 1)>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(left(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME)), len(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME))) - charindex('' '', reverse(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME))), 1)),1) 
						when charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1))>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, 1, charindex('' '', s.ACCOUNT_NAME, 1) - 1),1) 
						else NULL
						end AS FirstName --please don''t ask Austin to explain this one, it involves maths and Austin''s abilty to math is limited to once a day
					,case when charindex('','', s.ACCOUNT_NAME, 1)>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, 1, charindex('','', s.ACCOUNT_NAME, 1) - 1),1) 
						when charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1))>0 then
						 {{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1), charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1)) - 1),1) 
						else {{environment}}_INGESTION_DB.MASTER.PROPER(s.ACCOUNT_NAME,1)
					end AS LastName
					,CASE 
						WHEN (charindex('' '', s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2) > 0)
							THEN UPPER(substring(s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2) + 1, 1))
						ELSE NULL
						END AS MiddleInitial
					,{{environment}}_INGESTION_DB.MASTER.PROPER(s.BILLING_ADDRESS_1,1) AS AddressLine1
					,{{environment}}_INGESTION_DB.MASTER.PROPER(s.BILLING_ADDRESS_2,1) AS AddressLine2
					,{{environment}}_INGESTION_DB.MASTER.PROPER(s.CITY,1) AS City
					,mState.DestinationSk AS StateSK --MAP
					,mCountry.DestinationSk AS CountrySK --MAP
					,LEFT(s.ZIP,5) AS ZIPCODE --trim to 5? Ask Matt
					  ,CASE WHEN s.IS_ACTIVE=''Y'' THEN 1 ELSE 0 END as ActiveFlag
					  ,s.WORK_PHONE as WorkPhone
					  ,s.HOME_PHONE as HomePhone
					  ,s.TOTAL_BALANCE as TotalBalance
					  ,s.INSURANCE_BALANCE as InsuranceBalance
					  ,s.PATIENT_BALANCE as PatientBalance
					  ,mEmploymentStatus.DestinationSk AS EmploymentStatusSK --MAP
					  ,s.BIRTHDATE AS DateOfBirth
					  ,-1 AS SexSK --MAP
					  --,mAccountType.DestinationSK as AccountTypeSK
					  ,COALESCE(dat.AccountTypeSK,0) as AccountTypeSK
					  ,4 as UserType --All guarantor accounts are guarantors in Epic, eCW only
					  ,s.ACCOUNT_ID as GuarantorAccount
					  --,s.GuarantorAccount
					  ,s.ACCOUNT_NAME AS AccountName
					  ,s.BaseDeletedFlag
					  
				FROM {{environment}}_INGESTION_DB.INOVA_BASE.Guarantors s 
					LEFT JOIN {{environment}}_INGESTION_DB.DIMENSIONS.DIMPARTNERS psk ON PSK.PARTNERSK = :PARTNERSK
					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DIMSTATE mState  ON COALESCE(s.GUAR_STATE,'''') = mState.SourceColumnValue
					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DimCountry mCountry  ON COALESCE(s.Country,'''') = mCountry.SourceColumnValue

					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DimEmploymentStatus mEmploymentStatus  ON COALESCE(s.EMPY_STATUS,'''') = mEmploymentStatus.SourceColumnValue

					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.DIMACCOUNTTYPE dat  ON COALESCE(s.ACCT_TYPE,''No Data'') = dat.AccountType
					

				WHERE
				--s.CM_LOG_OWNER_ID <> 1208 --do not get old orphaned STL records.  They will now be 130
				--AND (
					:ISHISTORICAL = 1 -- full load
					OR (:ISHISTORICAL = 0 AND s.SNOWFLAKE_UPDATED_AT >= CAST(CAST(:BASEUPDATEDDATE as DATE) as TIMESTAMP))  
					
				--)--the cast sets it to midnight to make sure all of that day''s visits go through
				)
				SELECT StageTable.PartnerSK
				,StageTable.GuarantorId
				,StageTable.FirstName
				,StageTable.LastName
				,StageTable.MiddleInitial
				,StageTable.AddressLine1
				,StageTable.AddressLine2
				,StageTable.City
				,StageTable.StateSK
				,StageTable.CountrySK
				,StageTable.Zipcode
				,StageTable.ActiveFlag
				,StageTable.WorkPhone
				,StageTable.HomePhone
				,StageTable.TotalBalance
				,StageTable.InsuranceBalance
				,StageTable.PatientBalance
				,StageTable.EmploymentStatusSK
				,StageTable.DateOfBirth
				,StageTable.SexSK
				,StageTable.AccountTypeSK
				,StageTable.UserType
				,StageTable.GuarantorAccount
				,StageTable.AccountName
				,:CURRENTTIME,:CURRENTTIME,StageTable.BaseDeletedFlag
				,:CURRENTTIME,:CURRENTTIME,0
				 FROM StageTable  
				 WHERE StageTable.PartnerSK=:PARTNERSK;

				SELECT LAST_QUERY_ID() as last_qid INTO :QID;
				select execution_time/1000 into :RUNTIME
				from table({{environment}}_INGESTION_DB.information_schema.query_history()) WHERE QUERY_ID=:QID;
				SELECT  T.$1 AS NOOFROWSINSERTED  INTO :NUMBEROFROWSINSERTED   FROM TABLE(RESULT_SCAN(:QID)) T;
				INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
				(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
				VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',:RUNTIME,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',:NUMBEROFROWSINSERTED,0,''SUCCESS'',''INSERT FOR ISHISTORICAL=1 COMPLETED'');


		ELSE 
				MERGE INTO {{environment}}_INGESTION_DB.GOHEALTH_DW.GUARANTORS AS D 
				USING (
				WITH StageTable AS (
				SELECT 
					psk.PartnerSK as PartnerSK
					  --,s.DWID  as GuarantorId
						,s.ACCOUNT_ID as GuarantorId
						,case when charindex('', '', s.ACCOUNT_NAME, 1)>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(left(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME)), len(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME))) - charindex('' '', reverse(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME))), 1)),1) 
						when charindex('','', s.ACCOUNT_NAME, 1)>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(left(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME)), len(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME))) - charindex('' '', reverse(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME))), 1)),1) 
						when charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1))>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, 1, charindex('' '', s.ACCOUNT_NAME, 1) - 1),1) 
						else NULL
						end AS FirstName --please don''t ask Austin to explain this one, it involves maths and Austin''s abilty to math is limited to once a day
					,case when charindex('','', s.ACCOUNT_NAME, 1)>0 then
						{{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, 1, charindex('','', s.ACCOUNT_NAME, 1) - 1),1) 
						when charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1))>0 then
						 {{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1), charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1)) - 1),1) 
						else {{environment}}_INGESTION_DB.MASTER.PROPER(s.ACCOUNT_NAME,1)
					end AS LastName
					,CASE 
						WHEN (charindex('' '', s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2) > 0)
							THEN UPPER(substring(s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2) + 1, 1))
						ELSE NULL
						END AS MiddleInitial
					,{{environment}}_INGESTION_DB.MASTER.PROPER(s.BILLING_ADDRESS_1,1) AS AddressLine1
					,{{environment}}_INGESTION_DB.MASTER.PROPER(s.BILLING_ADDRESS_2,1) AS AddressLine2
					,{{environment}}_INGESTION_DB.MASTER.PROPER(s.CITY,1) AS City
					,mState.DestinationSk AS StateSK --MAP
					,mCountry.DestinationSk AS CountrySK --MAP
					,LEFT(s.ZIP,5) AS ZIPCODE --trim to 5? Ask Matt
					  ,CASE WHEN s.IS_ACTIVE=''Y'' THEN 1 ELSE 0 END as ActiveFlag
					  ,s.WORK_PHONE as WorkPhone
					  ,s.HOME_PHONE as HomePhone
					  ,s.TOTAL_BALANCE as TotalBalance
					  ,s.INSURANCE_BALANCE as InsuranceBalance
					  ,s.PATIENT_BALANCE as PatientBalance
					  ,mEmploymentStatus.DestinationSk AS EmploymentStatusSK --MAP
					  ,s.BIRTHDATE AS DateOfBirth
					  ,-1 AS SexSK --MAP
					  --,mAccountType.DestinationSK as AccountTypeSK
					  ,COALESCE(dat.AccountTypeSK,0) as AccountTypeSK
					  ,4 as UserType --All guarantor accounts are guarantors in Epic, eCW only
					  ,s.ACCOUNT_ID as GuarantorAccount
					  --,s.GuarantorAccount
					  ,s.ACCOUNT_NAME AS AccountName
					  ,s.BaseDeletedFlag
					  
				FROM {{environment}}_INGESTION_DB.INOVA_BASE.Guarantors s 
					LEFT JOIN {{environment}}_INGESTION_DB.DIMENSIONS.DIMPARTNERS psk ON PSK.PARTNERSK = :PARTNERSK 
					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DIMSTATE mState  ON COALESCE(s.GUAR_STATE,'''') = mState.SourceColumnValue
					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DimCountry mCountry  ON COALESCE(s.Country,'''') = mCountry.SourceColumnValue

					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DimEmploymentStatus mEmploymentStatus  ON COALESCE(s.EMPY_STATUS,'''') = mEmploymentStatus.SourceColumnValue

					LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.DIMACCOUNTTYPE dat  ON COALESCE(s.ACCT_TYPE,''No Data'') = dat.AccountType
						
				WHERE
				--s.CM_LOG_OWNER_ID <> 1208 --do not get old orphaned STL records.  They will now be 130
				--AND (
					:ISHISTORICAL = 1 -- full load
					OR (:ISHISTORICAL = 0 AND s.SNOWFLAKE_UPDATED_AT >= CAST(CAST(:BASEUPDATEDDATE as DATE) as TIMESTAMP))  
					AND s.SNOWFLAKE_DELETED_FLAG = 0   
				--)--the cast sets it to midnight to make sure all of that day''s visits go through
				)
				SELECT StageTable.PartnerSK
				,StageTable.GuarantorId
				,StageTable.FirstName
				,StageTable.LastName
				,StageTable.MiddleInitial
				,StageTable.AddressLine1
				,StageTable.AddressLine2
				,StageTable.City
				,StageTable.StateSK
				,StageTable.CountrySK
				,StageTable.Zipcode
				,StageTable.ActiveFlag
				,StageTable.WorkPhone
				,StageTable.HomePhone
				,StageTable.TotalBalance
				,StageTable.InsuranceBalance
				,StageTable.PatientBalance
				,StageTable.EmploymentStatusSK
				,StageTable.DateOfBirth
				,StageTable.SexSK
				,StageTable.AccountTypeSK
				,StageTable.UserType
				,StageTable.GuarantorAccount
				,StageTable.AccountName
				,StageTable.BaseDeletedFlag
				 FROM StageTable  
				 WHERE StageTable.PartnerSK=:PARTNERSK
				 ) AS S ON 
				S.PartnerSK = D.PartnerSK
				AND S.GuarantorId::VARCHAR(100) = D.GuarantorId::VARCHAR(100)
				AND D.PARTNERSK = :PARTNERSK
				AND D.SNOWFLAKE_DELETED_FLAG=0
				
				WHEN MATCHED AND 
				 COALESCE(S.PartnerSK,0) <> COALESCE(D.PartnerSK,0)
				 OR COALESCE(S.GuarantorId,'''') <> COALESCE(D.GuarantorId,'''')
				 OR COALESCE(S.FirstName,'''') <> COALESCE(D.FirstName,'''')
				 OR COALESCE(S.LastName,'''') <> COALESCE(D.LastName,'''')
				 OR COALESCE(S.MiddleInitial,'''') <> COALESCE(D.MiddleInitial,'''')
				 OR COALESCE(S.AddressLine1,'''') <> COALESCE(D.AddressLine1,'''')
				 OR COALESCE(S.AddressLine2,'''') <> COALESCE(D.AddressLine2,'''')
				 OR COALESCE(S.City,'''') <> COALESCE(D.City,'''')
				 OR COALESCE(S.StateSK,0) <> COALESCE(D.StateSK,0)
				 OR COALESCE(S.CountrySK,0) <> COALESCE(D.CountrySK,0)
				 OR COALESCE(S.Zipcode,'''') <> COALESCE(D.Zipcode,'''')
				 OR COALESCE(S.ActiveFlag,0) <> COALESCE(D.ActiveFlag,0)
				 OR COALESCE(S.WorkPhone,'''') <> COALESCE(D.WorkPhone,'''')
				 OR COALESCE(S.HomePhone,'''') <> COALESCE(D.HomePhone,'''')
				 OR COALESCE(S.TotalBalance,0) <> COALESCE(D.TotalBalance,0)
				 OR COALESCE(S.InsuranceBalance,0) <> COALESCE(D.InsuranceBalance,0)
				 OR COALESCE(S.PatientBalance,0) <> COALESCE(D.PatientBalance,0)
				 OR COALESCE(S.EmploymentStatusSK,0) <> COALESCE(D.EmploymentStatusSK,0)
				 OR COALESCE(S.DateOfBirth,''1900-01-01'') <> COALESCE(D.DateOfBirth,''1900-01-01'')
				 OR COALESCE(S.SexSK,0) <> COALESCE(D.SexSK,0)
				 OR COALESCE(S.AccountTypeSK,0) <> COALESCE(D.AccountTypeSK,0)
				 OR COALESCE(S.UserType,0) <> COALESCE(D.UserType,0)
				 OR COALESCE(S.GuarantorAccount,'''') <> COALESCE(D.GuarantorAccount,'''')
				 OR COALESCE(S.AccountName,'''') <> COALESCE(D.AccountName,'''')

				OR D.SNOWFLAKE_DELETED_FLAG = 1
				THEN UPDATE SET 
				D.BaseUpdatedDate = :CurrentTime, 
				D.SNOWFLAKE_UPDATED_AT = :CurrentTime, D.SNOWFLAKE_DELETED_FLAG = 1
		
				WHEN NOT MATCHED THEN INSERT (
				PartnerSK
				,GuarantorId
				,FirstName
				,LastName
				,MiddleInitial
				,AddressLine1
				,AddressLine2
				,City
				,StateSK
				,CountrySK
				,Zipcode
				,ActiveFlag
				,WorkPhone
				,HomePhone
				,TotalBalance
				,InsuranceBalance
				,PatientBalance
				,EmploymentStatusSK
				,DateOfBirth
				,SexSK
				,AccountTypeSK
				,UserType
				,GuarantorAccount
				,AccountName
				,BaseCreatedDate,BaseUpdatedDate,BaseDeletedFlag
				,SNOWFLAKE_CREATED_AT,SNOWFLAKE_UPDATED_AT,SNOWFLAKE_DELETED_FLAG
				) VALUES (
				S.PartnerSK
				,S.GuarantorId
				,S.FirstName
				,S.LastName
				,S.MiddleInitial
				,S.AddressLine1
				,S.AddressLine2
				,S.City
				,S.StateSK
				,S.CountrySK
				,S.Zipcode
				,S.ActiveFlag
				,S.WorkPhone
				,S.HomePhone
				,S.TotalBalance
				,S.InsuranceBalance
				,S.PatientBalance
				,S.EmploymentStatusSK
				,S.DateOfBirth
				,S.SexSK
				,S.AccountTypeSK
				,S.UserType
				,S.GuarantorAccount
				,S.AccountName
				,:CurrentTime,:CurrentTime,S.BaseDeletedFlag
				,:CurrentTime,:CurrentTime,0
				);

			SELECT LAST_QUERY_ID() as last_qid INTO :QID;
			select execution_time/1000 into :RUNTIME
			from table({{environment}}_INGESTION_DB.information_schema.query_history()) WHERE QUERY_ID=:QID;
			SELECT  T.$1 AS NOOFROWSINSERTED, T.$2 AS NOOFROWSUPDATED INTO :NUMBEROFROWSINSERTED, :NUMBEROFROWSUPDATED   FROM TABLE(RESULT_SCAN(:QID)) T;
			INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
			(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
			VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',:RUNTIME,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',:NUMBEROFROWSINSERTED,:NUMBEROFROWSUPDATED,''SUCCESS'',''MERGE INTO HARMONIZED LAYER COMPLETED'');																			

		-------------------------------------------scd-------------------------------------

				INSERT INTO {{environment}}_INGESTION_DB.GOHEALTH_DW.GUARANTORS (  
					PartnerSK
					,GuarantorId
					,FirstName
					,LastName
					,MiddleInitial
					,AddressLine1
					,AddressLine2
					,City
					,StateSK
					,CountrySK
					,Zipcode
					,ActiveFlag
					,WorkPhone
					,HomePhone
					,TotalBalance
					,InsuranceBalance
					,PatientBalance
					,EmploymentStatusSK
					,DateOfBirth
					,SexSK
					,AccountTypeSK
					,UserType
					,GuarantorAccount
					,AccountName
					,BaseCreatedDate,BaseUpdatedDate,BaseDeletedFlag
					,SNOWFLAKE_CREATED_AT,SNOWFLAKE_UPDATED_AT,SNOWFLAKE_DELETED_FLAG 
					)
						WITH S AS( 

							SELECT  
								psk.PartnerSK as PartnerSK
								  --,s.DWID  as GuarantorId
									,s.ACCOUNT_ID as GuarantorId
									,case when charindex('', '', s.ACCOUNT_NAME, 1)>0 then
									{{environment}}_INGESTION_DB.MASTER.PROPER(left(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME)), len(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME))) - charindex('' '', reverse(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2, len(s.ACCOUNT_NAME))), 1)),1) 
									when charindex('','', s.ACCOUNT_NAME, 1)>0 then
									{{environment}}_INGESTION_DB.MASTER.PROPER(left(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME)), len(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME))) - charindex('' '', reverse(substring(s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 1, len(s.ACCOUNT_NAME))), 1)),1) 
									when charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1))>0 then
									{{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, 1, charindex('' '', s.ACCOUNT_NAME, 1) - 1),1) 
									else NULL
									end AS FirstName --please don''t ask Austin to explain this one, it involves maths and Austin''s abilty to math is limited to once a day
								,case when charindex('','', s.ACCOUNT_NAME, 1)>0 then
									{{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, 1, charindex('','', s.ACCOUNT_NAME, 1) - 1),1) 
									when charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1))>0 then
									 {{environment}}_INGESTION_DB.MASTER.PROPER(substring(s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1), charindex('' '', s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, 1)) - 1),1) 
									else {{environment}}_INGESTION_DB.MASTER.PROPER(s.ACCOUNT_NAME,1)
								end AS LastName
								,CASE 
									WHEN (charindex('' '', s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2) > 0)
										THEN UPPER(substring(s.ACCOUNT_NAME, charindex('' '', s.ACCOUNT_NAME, charindex('','', s.ACCOUNT_NAME, 1) + 2) + 1, 1))
									ELSE NULL
									END AS MiddleInitial
								,{{environment}}_INGESTION_DB.MASTER.PROPER(s.BILLING_ADDRESS_1,1) AS AddressLine1
								,{{environment}}_INGESTION_DB.MASTER.PROPER(s.BILLING_ADDRESS_2,1) AS AddressLine2
								,{{environment}}_INGESTION_DB.MASTER.PROPER(s.CITY,1) AS City
								,mState.DestinationSk AS StateSK --MAP
								,mCountry.DestinationSk AS CountrySK --MAP
								,LEFT(s.ZIP,5) AS ZIPCODE --trim to 5? Ask Matt
								  ,CASE WHEN s.IS_ACTIVE=''Y'' THEN 1 ELSE 0 END as ActiveFlag
								  ,s.WORK_PHONE as WorkPhone
								  ,s.HOME_PHONE as HomePhone
								  ,s.TOTAL_BALANCE as TotalBalance
								  ,s.INSURANCE_BALANCE as InsuranceBalance
								  ,s.PATIENT_BALANCE as PatientBalance
								  ,mEmploymentStatus.DestinationSk AS EmploymentStatusSK --MAP
								  ,s.BIRTHDATE AS DateOfBirth
								  ,-1 AS SexSK --MAP
								  --,mAccountType.DestinationSK as AccountTypeSK
								  ,COALESCE(dat.AccountTypeSK,0) as AccountTypeSK
								  ,4 as UserType --All guarantor accounts are guarantors in Epic, eCW only
									,s.ACCOUNT_ID as GuarantorAccount
								  --,s.GuarantorAccount
								  ,s.ACCOUNT_NAME AS AccountName
								  ,s.BaseDeletedFlag
							FROM {{environment}}_INGESTION_DB.INOVA_BASE.Guarantors s 
								LEFT JOIN {{environment}}_INGESTION_DB.DIMENSIONS.DIMPARTNERS psk ON PSK.PARTNERSK = :PARTNERSK
								LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DIMSTATE mState  ON COALESCE(s.GUAR_STATE,'''') = mState.SourceColumnValue
								LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DimCountry mCountry  ON COALESCE(s.Country,'''') = mCountry.SourceColumnValue

								LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.MAP_DimEmploymentStatus mEmploymentStatus  ON COALESCE(s.EMPY_STATUS,'''') = mEmploymentStatus.SourceColumnValue

								LEFT OUTER JOIN {{environment}}_INGESTION_DB.DIMENSIONS.DIMACCOUNTTYPE dat  ON COALESCE(s.ACCT_TYPE,''No Data'') = dat.AccountType
									
							WHERE
							--s.CM_LOG_OWNER_ID <> 1208 --do not get old orphaned STL records.  They will now be 130
							--AND (
								:ISHISTORICAL = 1 -- full load
								OR (:ISHISTORICAL = 0 AND s.SNOWFLAKE_UPDATED_AT >= CAST(CAST(:BASEUPDATEDDATE as DATE) as TIMESTAMP))  
								AND s.SNOWFLAKE_DELETED_FLAG = 0
							--)--the cast sets it to midnight to make sure all of that day''s visits go through
						)
				SELECT * EXCLUDE(RN,updatedtime,delflag)
				FROM(	
					SELECT 
							 S.PartnerSK
							,S.GuarantorId
							,S.FirstName
							,S.LastName
							,S.MiddleInitial
							,S.AddressLine1
							,S.AddressLine2
							,S.City
							,S.StateSK
							,S.CountrySK
							,S.Zipcode
							,S.ActiveFlag
							,S.WorkPhone
							,S.HomePhone
							,S.TotalBalance
							,S.InsuranceBalance
							,S.PatientBalance
							,S.EmploymentStatusSK
							,S.DateOfBirth
							,S.SexSK
							,S.AccountTypeSK
							,S.UserType
							,S.GuarantorAccount
							,S.AccountName
							,D.BaseCreatedDate,:CURRENTTIME,S.BaseDeletedFlag
							,D.SNOWFLAKE_CREATED_AT,:CURRENTTIME,0
							,ROW_NUMBER() OVER(PARTITION BY S.GuarantorId ORDER BY D.SNOWFLAKE_UPDATED_AT DESC) as RN
							,D.SNOWFLAKE_UPDATED_AT as updatedtime
							,D.SNOWFLAKE_DELETED_FLAG as delflag
					FROM S inner join  {{environment}}_INGESTION_DB.GOHEALTH_DW.GUARANTORS D 
					ON S.GuarantorId::VARCHAR(100) = D.GuarantorId::VARCHAR(100) 
					and D.SNOWFLAKE_DELETED_FLAG = 1
					and D.partnersk=:PARTNERSK
					and EXISTS(
						SELECT 1 from  {{environment}}_INGESTION_DB.GOHEALTH_DW.GUARANTORS 
						where GuarantorId=S.GuarantorId 
						and SNOWFLAKE_DELETED_FLAG = 1 
						and snowflake_updated_at=:CURRENTTIME 
						and partnersk=:PARTNERSK
						)
					AND
					(
						 COALESCE(S.PartnerSK,0) <> COALESCE(D.PartnerSK,0)
						 OR COALESCE(S.GuarantorId,'''') <> COALESCE(D.GuarantorId,'''')
						 OR COALESCE(S.FirstName,'''') <> COALESCE(D.FirstName,'''')
						 OR COALESCE(S.LastName,'''') <> COALESCE(D.LastName,'''')
						 OR COALESCE(S.MiddleInitial,'''') <> COALESCE(D.MiddleInitial,'''')
						 OR COALESCE(S.AddressLine1,'''') <> COALESCE(D.AddressLine1,'''')
						 OR COALESCE(S.AddressLine2,'''') <> COALESCE(D.AddressLine2,'''')
						 OR COALESCE(S.City,'''') <> COALESCE(D.City,'''')
						 OR COALESCE(S.StateSK,0) <> COALESCE(D.StateSK,0)
						 OR COALESCE(S.CountrySK,0) <> COALESCE(D.CountrySK,0)
						 OR COALESCE(S.Zipcode,'''') <> COALESCE(D.Zipcode,'''')
						 OR COALESCE(S.ActiveFlag,0) <> COALESCE(D.ActiveFlag,0)
						 OR COALESCE(S.WorkPhone,'''') <> COALESCE(D.WorkPhone,'''')
						 OR COALESCE(S.HomePhone,'''') <> COALESCE(D.HomePhone,'''')
						 OR COALESCE(S.TotalBalance,0) <> COALESCE(D.TotalBalance,0)
						 OR COALESCE(S.InsuranceBalance,0) <> COALESCE(D.InsuranceBalance,0)
						 OR COALESCE(S.PatientBalance,0) <> COALESCE(D.PatientBalance,0)
						 OR COALESCE(S.EmploymentStatusSK,0) <> COALESCE(D.EmploymentStatusSK,0)
						 OR COALESCE(S.DateOfBirth,''1900-01-01'') <> COALESCE(D.DateOfBirth,''1900-01-01'')
						 OR COALESCE(S.SexSK,0) <> COALESCE(D.SexSK,0)
						 OR COALESCE(S.AccountTypeSK,0) <> COALESCE(D.AccountTypeSK,0)
						 OR COALESCE(S.UserType,0) <> COALESCE(D.UserType,0)
						 OR COALESCE(S.GuarantorAccount,'''') <> COALESCE(D.GuarantorAccount,'''')
						 OR COALESCE(S.AccountName,'''') <> COALESCE(D.AccountName,'''')
					) 
				) WHERE RN=1 and updatedtime=:CURRENTTIME and delflag=1;
				
				SELECT LAST_QUERY_ID() as last_qid INTO :QID;
			select execution_time/1000 into :RUNTIME
			from table({{environment}}_INGESTION_DB.information_schema.query_history()) WHERE QUERY_ID=:QID;
			SELECT  T.$1 AS NOOFROWSINSERTED  INTO :NUMBEROFROWSINSERTED   FROM TABLE(RESULT_SCAN(:QID)) T;
			INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
			(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
			VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',:RUNTIME,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',:NUMBEROFROWSINSERTED,0,''SUCCESS'',''SCD OF HARMONIZED LAYER COMPLETED'');	
		END IF;

	COMMIT;

EXCEPTION
WHEN STATEMENT_ERROR THEN
rollback;
LET ERR_MSG:=TRY_CAST(SQLERRM AS VARCHAR);
LET ERROR_MESSAGE VARCHAR := ''It seems we have encountered Statement Error in SP_MERGEGUARANTORS 

ERROR MESSAGE: '' || :ERR_MSG || ''

 For more details, look into {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE'';
CALL SYSTEM$SEND_EMAIL(''EMAIL_INT_INCREMENTAL'',''tanuj.rechintala@gohealthuc.com'',''STATEMENT ERROR IN SP_MERGEGUARANTORS - INOVA'',:ERROR_MESSAGE);
INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',0,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',0,0,''FAILURE'',:SQLERRM);
RAISE;
RETURN SQLERRM;


WHEN EXPRESSION_ERROR THEN 
rollback;
LET ERR_MSG:=TRY_CAST(SQLERRM AS VARCHAR);
LET ERROR_MESSAGE VARCHAR := ''It seems we have encountered Expression Error in SP_MERGEGUARANTORS 

ERROR MESSAGE: '' || :ERR_MSG || ''

 For more details, look into {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE'';
 CALL PROC('SP_NAME',6)';
CALL SYSTEM$SEND_EMAIL(''EMAIL_INT_INCREMENTAL'',''tanuj.rechintala@gohealthuc.com'',''EXPRESSION ERROR IN SP_MERGEGUARANTORS - INOVA'',:ERROR_MESSAGE);
INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',0,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',0,0,''FAILURE'',:SQLERRM);
RAISE;
RETURN SQLERRM;

WHEN OTHER THEN 
rollback;
LET ERR_MSG:=TRY_CAST(SQLERRM AS VARCHAR);
LET ERROR_MESSAGE VARCHAR := ''It seems we have encountered Unknown Error in SP_MERGEGUARANTORS 

ERROR MESSAGE: '' || :ERR_MSG || ''

 For more details, look into {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE'';
CALL SYSTEM$SEND_EMAIL(''EMAIL_INT_INCREMENTAL'',''tanuj.rechintala@gohealthuc.com'',''UNKNOWN ERROR IN SP_MERGEGUARANTORS - INOVA'',:ERROR_MESSAGE);
INSERT INTO {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE
(LOG_TIMESTAMP, PARTNERSK, FLOW_TYPE, RUN_TIME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, PROC_NAME, INSERTED_REC_CNT, UPDATED_REC_CNT, STATUS, MESSAGE)
VALUES(CURRENT_TIMESTAMP(),:PARTNERSK,''I'',0,''{{environment}}_INGESTION_DB'',''GOHEALTH_DW'',''GUARANTORS'',''SP_MERGEGUARANTORS'',0,0,''FAILURE'',:SQLERRM);
RAISE;
RETURN SQLERRM;


END;
';