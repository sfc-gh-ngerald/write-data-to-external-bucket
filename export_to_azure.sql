-- Export Snowflake Data to External Azure Blob Storage
-- This script creates an external stage and exports data to Azure

-- Step 1: Create external stage with Azure credentials
CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT
  URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
  CREDENTIALS = (
    AZURE_SAS_TOKEN = '<YOUR_SAS_TOKEN>'
  )
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);

-- Alternative: Use Service Principal authentication instead of SAS token
-- CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT
--   URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
--   CREDENTIALS = (
--     AZURE_TENANT_ID = '<YOUR_TENANT_ID>'
--     AZURE_CLIENT_ID = '<YOUR_CLIENT_ID>'
--     AZURE_CLIENT_SECRET = '<YOUR_CLIENT_SECRET>'
--   )
--   FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);

-- Step 2: Export data to Azure Blob Storage
COPY INTO @AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT/consent_receipts_sample.csv
FROM (SELECT * FROM CONSENT_MANAGEMENT.STREAMING.CONSENT_RECEIPTS LIMIT 100)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;

-- Step 3: Verify the export
LIST @AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT;
