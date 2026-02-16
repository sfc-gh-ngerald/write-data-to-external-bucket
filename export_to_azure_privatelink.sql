-- Export Snowflake Data to Azure Blob Storage via Private Connectivity
-- Use this when your Azure storage account is behind Private Link / private endpoints
-- 
-- IMPORTANT: This approach requires:
--   - Business Critical Edition (or higher)
--   - ACCOUNTADMIN privileges for initial setup
--
-- This works for cross-cloud scenarios (e.g., Snowflake on AWS -> Azure storage)

--------------------------------------------------------------------------------
-- STEP 1: Gather Your Azure Resource Information
-- You will need:
--   - Azure Subscription ID
--   - Resource Group name
--   - Storage Account name
--   - Azure Tenant ID
--   - Container name
--------------------------------------------------------------------------------

-- Example values (replace with your own):
--   Subscription ID:   cc2909f2-ed22-4c89-8e5d-bdc40e5eac26
--   Resource Group:    my-resource-group
--   Storage Account:   mystorageaccount
--   Tenant ID:         d92985c5-3085-4d34-b39c-612d8234262d
--   Container:         my-container

--------------------------------------------------------------------------------
-- STEP 2: Provision a Private Endpoint from Snowflake to Azure Storage
-- (Requires ACCOUNTADMIN)
--
-- This creates a managed private endpoint in Snowflake's VNet that connects
-- to your Azure storage account over Azure Private Link.
--------------------------------------------------------------------------------

USE ROLE ACCOUNTADMIN;

SELECT SYSTEM$PROVISION_PRIVATELINK_ENDPOINT(
  '/subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/<YOUR_RESOURCE_GROUP>/providers/Microsoft.Storage/storageAccounts/<YOUR_STORAGE_ACCOUNT>',
  '<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net',
  'blob'
);

-- Example with actual values:
-- SELECT SYSTEM$PROVISION_PRIVATELINK_ENDPOINT(
--   '/subscriptions/cc2909f2-ed22-4c89-8e5d-bdc40e5eac26/resourceGroups/my-resource-group/providers/Microsoft.Storage/storageAccounts/mystorageaccount',
--   'mystorageaccount.blob.core.windows.net',
--   'blob'
-- );

--------------------------------------------------------------------------------
-- STEP 3: Approve the Private Endpoint in Azure Portal (Manual Steps)
--
-- 3a. Go to Azure Portal > Your Storage Account > Networking
-- 3b. Click "Private endpoint connections" tab
-- 3c. Find the pending connection from Snowflake (status: Pending)
-- 3d. Select it and click "Approve"
-- 3e. Wait 5-10 minutes for the connection to become active
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 4: Verify the Private Endpoint is Approved
-- Wait until status shows "APPROVED" before proceeding
--------------------------------------------------------------------------------

SELECT SYSTEM$GET_PRIVATELINK_ENDPOINTS_INFO();

--------------------------------------------------------------------------------
-- STEP 5: Create Storage Integration with USE_PRIVATELINK_ENDPOINT
-- (Requires ACCOUNTADMIN)
--------------------------------------------------------------------------------

CREATE OR REPLACE STORAGE INTEGRATION azure_privatelink_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  AZURE_TENANT_ID = '<YOUR_AZURE_TENANT_ID>'
  STORAGE_ALLOWED_LOCATIONS = ('azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/')
  USE_PRIVATELINK_ENDPOINT = TRUE
  ENABLED = TRUE;

-- Example with actual values:
-- CREATE OR REPLACE STORAGE INTEGRATION azure_privatelink_integration
--   TYPE = EXTERNAL_STAGE
--   STORAGE_PROVIDER = 'AZURE'
--   AZURE_TENANT_ID = 'd92985c5-3085-4d34-b39c-612d8234262d'
--   STORAGE_ALLOWED_LOCATIONS = ('azure://mystorageaccount.blob.core.windows.net/my-container/')
--   USE_PRIVATELINK_ENDPOINT = TRUE
--   ENABLED = TRUE;

--------------------------------------------------------------------------------
-- STEP 6: Get Integration Details for Azure AD Consent
-- Note the AZURE_CONSENT_URL and AZURE_MULTI_TENANT_APP_NAME
--------------------------------------------------------------------------------

DESC STORAGE INTEGRATION azure_privatelink_integration;

--------------------------------------------------------------------------------
-- STEP 7: Grant Azure AD Consent (Manual Steps)
--
-- 7a. Copy the AZURE_CONSENT_URL from Step 6 and open it in a browser
-- 7b. Sign in with an Azure AD admin account
-- 7c. Accept the permissions for the Snowflake application
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 8: Grant Storage Blob Data Contributor Role in Azure (Manual Steps)
--
-- 8a. Go to Azure Portal > Your Storage Account > Access Control (IAM)
-- 8b. Click "Add role assignment"
-- 8c. Select "Storage Blob Data Contributor" role
-- 8d. Assign to the Snowflake application (use AZURE_MULTI_TENANT_APP_NAME from Step 6)
-- 8e. Save
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------
-- STEP 9: Grant Usage on the Integration to Other Roles (Optional)
-- This allows non-ACCOUNTADMIN roles to use the integration
--------------------------------------------------------------------------------

GRANT USAGE ON INTEGRATION azure_privatelink_integration TO ROLE SYSADMIN;

--------------------------------------------------------------------------------
-- STEP 10: Create External Stage Using the Storage Integration
--------------------------------------------------------------------------------

USE ROLE SYSADMIN; -- Or your preferred role

CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE
  URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
  STORAGE_INTEGRATION = azure_privatelink_integration
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);

--------------------------------------------------------------------------------
-- STEP 11: Export Data to Azure Blob Storage
--------------------------------------------------------------------------------

COPY INTO @AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE/consent_receipts_sample.csv
FROM (SELECT * FROM CONSENT_MANAGEMENT.STREAMING.CONSENT_RECEIPTS LIMIT 100)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;

--------------------------------------------------------------------------------
-- STEP 12: Verify the Export
--------------------------------------------------------------------------------

LIST @AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE;

--------------------------------------------------------------------------------
-- TROUBLESHOOTING
--------------------------------------------------------------------------------

-- Check private endpoint status:
SELECT SYSTEM$GET_PRIVATELINK_ENDPOINTS_INFO();

-- Error: "Private link connection not approved"
-- Solution: Complete Step 3 and wait for the endpoint status to show "APPROVED"

-- Error: "Access denied" or "Authorization failed"  
-- Solution: Complete Steps 7-8 (Azure AD consent and IAM role assignment)

-- Error: "Network connection failed"
-- Solution: Verify your Azure storage account allows private endpoint connections
--           Check: Storage Account > Networking > "Allow access from selected networks"

-- To check integration status:
SHOW STORAGE INTEGRATIONS;

-- To see detailed integration properties:
DESC STORAGE INTEGRATION azure_privatelink_integration;

--------------------------------------------------------------------------------
-- CLEANUP (if needed)
--------------------------------------------------------------------------------

-- DROP STAGE AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE;
-- DROP STORAGE INTEGRATION azure_privatelink_integration;

-- To deprovision the private endpoint:
-- First unset USE_PRIVATELINK_ENDPOINT on all stages/integrations using it, then:
-- SELECT SYSTEM$DEPROVISION_PRIVATELINK_ENDPOINT(
--   '/subscriptions/<YOUR_SUBSCRIPTION_ID>/resourceGroups/<YOUR_RESOURCE_GROUP>/providers/Microsoft.Storage/storageAccounts/<YOUR_STORAGE_ACCOUNT>',
--   '<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net',
--   'blob'
-- );
