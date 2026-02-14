-- Export Snowflake Data to Azure Blob Storage via Private Link
-- Use this when your Azure storage account is behind Private Link / private endpoints
-- 
-- IMPORTANT: This approach requires ACCOUNTADMIN privileges for initial setup
-- Direct credential stages will NOT work with Private Link - you MUST use a Storage Integration

--------------------------------------------------------------------------------
-- STEP 1: Create Storage Integration with Private Link Enabled
-- (Requires ACCOUNTADMIN)
--------------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION azure_privatelink_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '<YOUR_AZURE_TENANT_ID>'
  STORAGE_ALLOWED_LOCATIONS = ('azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/')
  AZURE_ENABLE_PRIVATE_LINK = TRUE;

--------------------------------------------------------------------------------
-- STEP 2: Retrieve Integration Details
-- Note the following values from the output:
--   - AZURE_CONSENT_URL: Visit this URL to grant Snowflake access to your tenant
--   - AZURE_MULTI_TENANT_APP_NAME: The Snowflake app that needs permissions
--   - AZURE_PRIVATE_LINK_SERVICE_ID: The private endpoint resource ID
--------------------------------------------------------------------------------

DESC STORAGE INTEGRATION azure_privatelink_integration;

--------------------------------------------------------------------------------
-- STEP 3: Grant Consent in Azure (Manual Steps in Azure Portal)
--
-- 3a. Copy the AZURE_CONSENT_URL from Step 2 and open it in a browser
-- 3b. Sign in with an Azure AD admin account
-- 3c. Accept the permissions for the Snowflake application
--
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 4: Approve Private Endpoint in Azure Portal (Manual Steps)
--
-- 4a. Go to Azure Portal > Your Storage Account > Networking
-- 4b. Click "Private endpoint connections" tab
-- 4c. Find the pending connection from Snowflake (status: Pending)
-- 4d. Select it and click "Approve"
-- 4e. Wait 5-10 minutes for the connection to become active
--
-- To verify the endpoint is approved, you can also check:
--   Azure Portal > Private Link Center > Private endpoints
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 5: Verify the Integration is Working
-- STATUS should show as "CONNECTED" after approval
--------------------------------------------------------------------------------

DESC STORAGE INTEGRATION azure_privatelink_integration;

-- Check the private link connection status
SELECT SYSTEM$GET_PRIVATELINK_CONFIG();

--------------------------------------------------------------------------------
-- STEP 6: Grant Usage on the Integration to Other Roles (Optional)
-- This allows non-ACCOUNTADMIN roles to use the integration
--------------------------------------------------------------------------------

GRANT USAGE ON INTEGRATION azure_privatelink_integration TO ROLE SYSADMIN;
-- Add additional roles as needed:
-- GRANT USAGE ON INTEGRATION azure_privatelink_integration TO ROLE DATA_ENGINEER;

--------------------------------------------------------------------------------
-- STEP 7: Create External Stage Using the Storage Integration
-- (Can be done by any role with USAGE on the integration and CREATE STAGE privilege)
--------------------------------------------------------------------------------

USE ROLE SYSADMIN; -- Or your preferred role

    CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE
    URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
    STORAGE_INTEGRATION = azure_privatelink_integration
    FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);

--------------------------------------------------------------------------------
-- STEP 8: Export Data to Azure Blob Storage
--------------------------------------------------------------------------------

COPY INTO @AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE/consent_receipts_sample.csv
FROM (SELECT * FROM CONSENT_MANAGEMENT.STREAMING.CONSENT_RECEIPTS LIMIT 100)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;

--------------------------------------------------------------------------------
-- STEP 9: Verify the Export
--------------------------------------------------------------------------------

LIST @AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE;

--------------------------------------------------------------------------------
-- TROUBLESHOOTING
--------------------------------------------------------------------------------

-- Error: "Private link connection not approved"
-- Solution: Complete Step 4 and wait for the endpoint to become active

-- Error: "Access denied" or "Authorization failed"  
-- Solution: Complete Step 3 (Azure consent) and verify the storage account
--           has the Snowflake app granted "Storage Blob Data Contributor" role

-- Error: "Network connection failed"
-- Solution: Verify your Azure storage account allows private endpoint connections
--           Check: Storage Account > Networking > "Allow access from selected networks"

-- To check integration status:
SHOW STORAGE INTEGRATIONS;

-- To see detailed integration properties:
DESC STORAGE INTEGRATION azure_privatelink_integration;