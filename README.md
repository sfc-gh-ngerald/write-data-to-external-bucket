# Writing Snowflake Data to External Cloud Storage

This guide demonstrates how to export data from Snowflake to external cloud storage (AWS S3 or Azure Blob Storage) using an external stage with credentials.

## Overview

**Approach Used:** External Stage with Cloud Provider Credentials

We use `COPY INTO <stage>` to write data directly to cloud storage. This is the simplest approach when you have access credentials and don't want to set up a storage integration (which requires ACCOUNTADMIN privileges).

## What is a Storage Integration?

A **storage integration** is a Snowflake object that stores a trust relationship with an external cloud provider (AWS, Azure, GCP), eliminating the need to pass credentials directly.

**Key benefits:**
- **More secure** — no credentials stored in stage definitions or visible in query history
- **Centralized access control** — ACCOUNTADMIN creates it once, grants usage to other roles
- **Required for Private Link** — the only way to route traffic through private endpoints
- **Uses cloud-native auth** — IAM roles (AWS), Service Principals (Azure), Service Accounts (GCP)

| Without Integration | With Integration |
|---------------------|------------------|
| Credentials in stage definition | Credentials managed by Snowflake |
| Anyone who can DESC stage sees keys | Keys never exposed |
| Can't use Private Link | Supports Private Link |

## AWS S3

### Prerequisites

- AWS IAM user with S3 read/write access to the target bucket
- AWS Access Key ID and Secret Access Key
- Snowflake role with CREATE STAGE privilege

### 1. Create an External Stage

```sql
CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.S3_EXPORT_STAGE_DIRECT
  URL = 's3://ngerald-demo-aws-1/file_write/'
  CREDENTIALS = (
    AWS_KEY_ID = '<YOUR_AWS_ACCESS_KEY_ID>'
    AWS_SECRET_KEY = '<YOUR_AWS_SECRET_ACCESS_KEY>'
  )
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);
```

### 2. Export Data

```sql
COPY INTO @AICOLLEGE.PUBLIC.S3_EXPORT_STAGE_DIRECT/consent_receipts_sample.csv
FROM (SELECT * FROM CONSENT_MANAGEMENT.STREAMING.CONSENT_RECEIPTS LIMIT 100)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
```

### 3. Verify the Export

```sql
LIST @AICOLLEGE.PUBLIC.S3_EXPORT_STAGE_DIRECT;
```

## Azure Blob Storage

### Prerequisites

- Azure Storage Account with a container
- SAS Token with read/write permissions OR Service Principal credentials
- Snowflake role with CREATE STAGE privilege

### 1. Create an External Stage (SAS Token)

```sql
CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT
  URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
  CREDENTIALS = (
    AZURE_SAS_TOKEN = '<YOUR_SAS_TOKEN>'
  )
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);
```

### Alternative: Service Principal Authentication

```sql
CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT
  URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
  CREDENTIALS = (
    AZURE_TENANT_ID = '<YOUR_TENANT_ID>'
    AZURE_CLIENT_ID = '<YOUR_CLIENT_ID>'
    AZURE_CLIENT_SECRET = '<YOUR_CLIENT_SECRET>'
  )
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);
```

### 2. Export Data

```sql
COPY INTO @AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT/consent_receipts_sample.csv
FROM (SELECT * FROM CONSENT_MANAGEMENT.STREAMING.CONSENT_RECEIPTS LIMIT 100)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
```

### 3. Verify the Export

```sql
LIST @AICOLLEGE.PUBLIC.AZURE_EXPORT_STAGE_DIRECT;
```

## Azure Blob Storage with Private Link

When your Azure storage account is behind Private Link / private endpoints, direct credential stages **will not work**. You must use a Storage Integration with Private Link enabled.

### Prerequisites

- ACCOUNTADMIN role (for creating storage integration)
- Azure AD admin access (for granting consent)
- Azure Portal access (for approving private endpoint)

### Steps Overview

1. **Create Storage Integration** with `AZURE_ENABLE_PRIVATE_LINK = TRUE`
2. **Grant Azure AD consent** via the consent URL
3. **Approve private endpoint** in Azure Portal
4. **Create stage** using the integration
5. **Export data** as usual

### 1. Create Storage Integration (Requires ACCOUNTADMIN)

```sql
USE ROLE ACCOUNTADMIN;

CREATE STORAGE INTEGRATION azure_privatelink_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '<YOUR_AZURE_TENANT_ID>'
  STORAGE_ALLOWED_LOCATIONS = ('azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/')
  AZURE_ENABLE_PRIVATE_LINK = TRUE;
```

### 2. Get Integration Details

```sql
DESC STORAGE INTEGRATION azure_privatelink_integration;
```

Note these values from the output:
- `AZURE_CONSENT_URL` — Visit this URL to grant Snowflake access
- `AZURE_MULTI_TENANT_APP_NAME` — The Snowflake app needing permissions

### 3. Grant Azure AD Consent (Manual)

1. Copy the `AZURE_CONSENT_URL` and open it in a browser
2. Sign in with an Azure AD admin account
3. Accept the permissions for the Snowflake application

### 4. Approve Private Endpoint in Azure Portal (Manual)

1. Go to **Azure Portal > Your Storage Account > Networking**
2. Click **Private endpoint connections** tab
3. Find the pending connection from Snowflake (status: Pending)
4. Select it and click **Approve**
5. Wait 5-10 minutes for the connection to become active

### 5. Create Stage Using the Integration

```sql
CREATE OR REPLACE STAGE AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE
  URL = 'azure://<YOUR_STORAGE_ACCOUNT>.blob.core.windows.net/<YOUR_CONTAINER>/file_write/'
  STORAGE_INTEGRATION = azure_privatelink_integration
  FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE);
```

### 6. Export Data

```sql
COPY INTO @AICOLLEGE.PUBLIC.AZURE_PRIVATELINK_STAGE/consent_receipts_sample.csv
FROM (SELECT * FROM CONSENT_MANAGEMENT.STREAMING.CONSENT_RECEIPTS LIMIT 100)
FILE_FORMAT = (TYPE = CSV FIELD_OPTIONALLY_ENCLOSED_BY = '"' COMPRESSION = NONE)
HEADER = TRUE
SINGLE = TRUE
OVERWRITE = TRUE;
```

### Troubleshooting Private Link

| Error | Solution |
|-------|----------|
| "Private link connection not approved" | Complete Step 4 and wait for endpoint to become active |
| "Access denied" / "Authorization failed" | Complete Step 3 (Azure consent) and grant Storage Blob Data Contributor role |
| "Network connection failed" | Verify storage account allows private endpoint connections |

## Key Parameters

| Parameter | Description |
|-----------|-------------|
| `SINGLE = TRUE` | Outputs all data to a single file instead of multiple partitions |
| `HEADER = TRUE` | Includes column headers in the CSV |
| `OVERWRITE = TRUE` | Overwrites existing file if present |
| `COMPRESSION = NONE` | Outputs uncompressed CSV (use GZIP for large files) |

## Storage Integration (Production Recommended)

For production use without Private Link, a storage integration is still recommended for security:

### AWS S3 Storage Integration

```sql
CREATE STORAGE INTEGRATION s3_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'S3'
  ENABLED = TRUE
  STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<account>:role/<role>'
  STORAGE_ALLOWED_LOCATIONS = ('s3://bucket/path/');
```

### Azure Storage Integration

```sql
CREATE STORAGE INTEGRATION azure_integration
  TYPE = EXTERNAL_STAGE
  STORAGE_PROVIDER = 'AZURE'
  ENABLED = TRUE
  AZURE_TENANT_ID = '<YOUR_TENANT_ID>'
  STORAGE_ALLOWED_LOCATIONS = ('azure://<account>.blob.core.windows.net/<container>/');
```

## Files in This Demo

| File | Description |
|------|-------------|
| `export_to_s3.sql` | Export to AWS S3 with direct credentials |
| `export_to_azure.sql` | Export to Azure Blob Storage with direct credentials |
| `export_to_azure_privatelink.sql` | Export to Azure Blob Storage via Private Link (detailed steps) |
| `README.md` | This guide |
