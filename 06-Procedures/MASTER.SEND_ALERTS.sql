
CREATE OR REPLACE PROCEDURE {{environment}}_INGESTION_DB.MASTER.SEND_ALERTS("SP_NAME" VARCHAR(16777216), "PARTNERSK" VARCHAR(16777216))
RETURNS VARCHAR(16777216)
LANGUAGE PYTHON
RUNTIME_VERSION = '3.8'
PACKAGES = ('snowflake-snowpark-python','tabulate')
HANDLER = 'send_alert'
EXECUTE AS CALLER
AS 
$$
import snowflake
from datetime import date

def send_alert(session, SP_NAME, PARTNERSK):
    try:
        email_query = 'SELECT email FROM {{environment}}_INGESTION_DB.MASTER.alert_info WHERE is_active = TRUE'
        email_data = session.sql(email_query).to_pandas()
        send_to_emails = ','.join(email_data['EMAIL'].tolist())
        query = f'''SELECT DATABASE_NAME, SCHEMA_NAME, TABLE_NAME, MESSAGE FROM {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE WHERE PROC_NAME='{SP_NAME}' AND PARTNERSK={PARTNERSK} ORDER BY LOG_TIMESTAMP DESC LIMIT 1'''
        query_data = session.sql(query).to_pandas()
        env = '{{environment}}'
        
        subject = f' Error in Loading Table - Stored Procedure Failure - {SP_NAME}'
        body = f'Hi All, <br> We encountered an error while executing the stored procedure {SP_NAME} for partnersk {PARTNERSK} in {env} environment. Kindly refer to the details below for further investigation:'
        body2 = f'''
                * Database Name :- {query_data['DATABASE_NAME'].iloc[0]} <br>* Schema Name :- {query_data['SCHEMA_NAME'].iloc[0]} <br>* Table Name :- {query_data['TABLE_NAME'].iloc[0]} <br>* Error Message :- {query_data['MESSAGE'].iloc[0]}
        '''
        footer = f'For additional information, kindly refer to the audit table {{environment}}_AUDIT_DB.AUDIT.AUDIT_TABLE for further insights into this issue.'
        
        
        mail_body = f'{body} <br> <br> {body2} <br> <br> {footer} <br> <br> Regards <br> GoHealth'
        session.call('system$send_email','EMAIL_INT_INCREMENTAL',send_to_emails,subject,mail_body,'text/html')
        
    except snowflake.snowpark.exceptions.SnowparkSQLException as e:
        body = '%s\\n\\n%s' % (type(e), e)

   
    return 'email sent:\\n%s' % mail_body
    ##return query_data['DATABASE_NAME'].iloc[0]

$$

;
