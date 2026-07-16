# HelloID-Conn-Prov-Source-CAPP12

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.

<p align="center">
  <img src="https://github.com/Tools4everBV/HelloID-Conn-Prov-Source-CAPP12/blob/main/Logo.png">
</p>

## Table of contents

- [HelloID-Conn-Prov-Source-CAPP12](#helloid-conn-prov-source-capp12)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
    - [Supported features](#supported-features)
  - [Getting started](#getting-started)
    - [HelloID Icon URL](#helloid-icon-url)
    - [Requirements](#requirements)
    - [CAPP12 API Access](#capp12-api-access)
    - [Configuration settings](#configuration-settings)
    - [Mapping](#mapping)
  - [Remarks](#remarks)
    - [HelloID contract limit](#helloid-contract-limit)
    - [Business Rules limitations](#business-rules-limitations)
    - [Certificate filtering logic](#certificate-filtering-logic)
  - [Development resources](#development-resources)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Source-CAPP12_ is a _Source_ connector for CAPP12 Learning Management System. CAPP12 provides a set of REST API's that allow you to programmatically interact with its data.

This connector is designed to be used as an aggregation source in combination with a primary HR source system. The HR system provides the base persons, while this connector imports certificate compliance data as contracts. This contract data can then be used in HelloID Business Rules and Dynamic Permissions to manage access and entitlements in target systems.

### Supported features

The following features are available:

| Feature            | Supported | Description                                       | Notes                                               |
| ------------------ | --------- | ------------------------------------------------- | --------------------------------------------------- |
| Persons import     | ✅         | Import persons with certificate data as contracts | User code (employee number) used as aggregation key |
| Departments import | ❌         | -                                                 | Not available in CAPP12 API                         |

## Getting started

### HelloID Icon URL

URL of the icon used for the HelloID Provisioning source system.

```
https://raw.githubusercontent.com/Tools4everBV/HelloID-Conn-Prov-Source-CAPP12/refs/heads/main/Icon.png
```

### Requirements

**Primary HR source system:**
This connector requires a primary HR source system that imports persons into HelloID. The CAPP12 connector acts as an aggregation source that adds certificate data as contracts to existing persons.

**Person aggregation:**
- Person aggregation must be configured in HelloID (see [HelloID documentation](https://docs.helloid.com/en/provisioning/Source-systems/powershell-v2-Source-systems.html#person-aggregation))
- The aggregation key used for CAPP12 is the **user code** (employee number)
- **Important:** HelloID supports only one aggregation key across all source systems. If your primary HR system uses a different aggregation key than employee number, this connector cannot be used for person aggregation
- Ensure the user codes in CAPP12 match the employee numbers in your primary HR system

**CAPP12 API credentials:**
- CAPP12 instance with API access
- Client ID and Client Secret with appropriate scopes

### CAPP12 API Access

**Required from CAPP12:**
1. **Base URL** - Your CAPP12 instance URL (e.g., `https://yourcompany.capp12.nl`)
2. **Client ID** - OAuth2 client identifier
3. **Client Secret** - OAuth2 client secret  
4. **API Scope** - Ensure the client has `api/compliance` scope enabled

**How to obtain credentials:**
- Contact your CAPP12 application manager or support
- Request API access for HelloID integration
- Verify the client credentials have read access to:
  - `/api/v1/users` - User information
  - `/api/v3/compliance_status.csv` - Required certificate status
  - `/api/v3/achievement_status.csv` - Achieved certificate status

### Configuration settings

The following settings are required to connect to the API.

| Setting                   | Description                                                                                                                                                                                     | Example                         | Mandatory |
| ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------- | --------- |
| BaseUrl                   | The URL to your CAPP12 instance                                                                                                                                                                 | `https://yourcompany.capp12.nl` | Yes       |
| ClientId                  | The ClientId to connect to the API                                                                                                                                                              | `a1b2c3d4e5f6example`           | Yes       |
| ClientSecret              | The ClientSecret to connect to the API                                                                                                                                                          | `x9y8z7w6v5u4example`           | Yes       |
| HistoricalDays            | Number of days in the past from which expired certificates will be imported. Historical filtering applies only to required certificates.                                                        | `60`                            | Yes       |
| RequiredCertificatesOnly  | When enabled, only required certificates will be imported (filters out non-required achievements)                                                                                               | `true`/`false`                  | Yes       |
| CompliantCertificatesOnly | When enabled, only certificates that have been achieved will be imported. This filters out non-compliant required certificates. Automatically implies RequiredCertificatesOnly.                 | `true`/`false`                  | Yes       |
| IncludeCertificateCodes   | Comma-separated whitelist of certificate codes to import. When empty, all certificates (subject to other filters) are imported. When specified, ONLY these certificate codes will be processed. | `CE-0001,CE-0002,CE-0003`       | No        |

**Recommended initial settings:**

For most implementations, start with these settings:
- `HistoricalDays`: `60` (imports certificates expiring within last 60 days)
- `RequiredCertificatesOnly`: `true` (only import required certificates)
- `CompliantCertificatesOnly`: `false` (import both compliant and non-compliant)
- `IncludeCertificateCodes`: `` (empty - import all certificates)

Adjust these settings based on your specific requirements and the number of certificates per person. Monitor the average and maximum values to stay within HelloID's performance limits (average: 30, maximum: 100 contracts per person).

### Mapping

The mapping file (`mapping.json`) contains the mapping between the CAPP12 API response and HelloID person and contract attributes. The mapping file is included in this repository.

As there are no natural HelloID contract attributes for certificate compliance data, the mapping uses standard contract attributes to represent the information:

- **Title** = Certificate identification (which certificate)
- **Division** = Required status (is this certificate mandatory for the user?)
- **Team** = Compliance status (has the user achieved this required certificate?)
- **StartDate/EndDate** = Validity period (when achieved and when expires)

**Why StartDate = 9999-12-31 for non-achieved certificates:**

For non-compliant required certificates (required but not achieved), the `achieved_at` field is empty in CAPP12. HelloID treats contracts **without a StartDate as active**, which is incorrect for certificates that haven't been achieved yet. Setting the `StartDate` to a far future date (`9999-12-31`) ensures:
1. **The contract is NOT treated as active** - HelloID treats contracts with a future StartDate as future, correctly reflecting that the certificate hasn't been achieved
2. **Automatic update when achieved** - Once the certificate is achieved, the `StartDate` updates to the actual achievement date and the contract becomes active with the correct validity period

## Remarks

### HelloID contract limit

**Important:** HelloID has performance limits for contracts per person:
- **Maximum:** 100 contracts per person (hard limit)
- **Recommended average:** 30 contracts per person across all persons

For more information, see [Performance limits (Provisioning)](https://docs.helloid.com/en/provisioning/performance-limits--provisioning-.html).

If users have more than the recommended number of certificates, you must reduce the count using one or more of these strategies:

1. **Use `IncludeCertificateCodes`** - Whitelist only relevant certificate codes
2. **Enable `RequiredCertificatesOnly`** - Import only required certificates
3. **Enable `CompliantCertificatesOnly`** - Import only achieved required certificates
4. **Reduce `HistoricalDays`** - Import fewer expired certificates
5. **Combine multiple filters** - Stack filters to reduce counts further

**Monitor statistics after import:**
The connector logs statistics including `Max per person: X` and `Average per person: Y`. If the maximum exceeds 100 or the average exceeds 30, you must adjust your filters to reduce the number of certificates per person.

### Business Rules limitations

Business Rule conditions in HelloID can only compare attribute values within a **single contract**. Cross-contract comparisons are not supported in standard BR conditions.

**Example use case:**
You can create a Business Rule that grants access to a specific application when a user obtains a certain certificate. However, you cannot use standard BR conditions to further filter based on other contract attributes (such as function or department) in combination with the certificate. For such scenarios, use Dynamic Permissions with custom PowerShell logic.

### Certificate filtering logic

**Understanding certificate types:**

The connector distinguishes between three types of certificates:

1. **Required certificates** - Certificates that are mandatory for a user according to CAPP12 compliance rules
2. **Compliant certificates** - Required certificates that have been achieved by the user (even if the achievement has expired)
3. **Non-required achieved certificates** - Certificates obtained by the user that are not mandatory

**Default import behavior:**

By default, the connector imports **all required certificates** (both compliant and non-compliant) for all users. Use the configuration settings (see [Configuration settings](#configuration-settings)) to filter which certificates are imported.

**Best practice - Certificate code whitelist:**

> [!IMPORTANT]
> **Recommended:** Use the `IncludeCertificateCodes` filter to import only the certificates that are used in your Business Rules and Dynamic Permissions.

**Why this is important:**
- HelloID has a **100 contracts per person maximum** and a **recommended average of 30 contracts per person**
- Only a small subset of certificates typically determines access rights
- Filtering by specific codes prevents hitting the limits while maintaining all relevant access control data

**Technical implementation notes:**
- Certificates are deduplicated per user - each unique user+certificate combination appears only once
- Required certificates are retrieved from `/api/v3/compliance_status.csv`
- Achieved certificates are retrieved from `/api/v3/achievement_status.csv`
- Compliance status is determined by checking if a required certificate exists in the achievement data
- Achievement status is checked without historical filtering to ensure accurate compliance determination
- An expired achievement still counts as compliant if the required certificate falls within the historical period

## Development resources

### API endpoints

The following endpoints are used by the connector:

| Endpoint                           | Description                                          |
| ---------------------------------- | ---------------------------------------------------- |
| POST /oauth2/token                 | OAuth2 authentication endpoint                       |
| GET /api/v1/users                  | Retrieve user identifying information of all users   |
| GET /api/v3/compliance_status.csv  | Retrieve compliance status information of all users  |
| GET /api/v3/achievement_status.csv | Retrieve achievement status information of all users |

### API documentation

The official CAPP12 API documentation can be found at:

- [CAPP12 API Documentation](https://documenter.getpostman.com/view/17909805/UV5f6tSy#intro) - Complete API reference and usage guides

## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/Source-systems/powershell-v2-Source-systems.html) pages_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
