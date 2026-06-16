# HelloID-Conn-Prov-Source-CAPP12

<!--
** for extra information about alert syntax please refer to [Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
-->

> [!IMPORTANT]
> This repository contains the connector and configuration code only. The implementer is responsible to acquire the connection details such as username, password, certificate, etc. You might even need to sign a contract or agreement with the supplier before implementing this connector. Please contact the client's application manager to coordinate the connector requirements.
>
> [!WARNING]
> This connector has not been tested on a Capp12 environment in combination with HelloID. Therefore, changes may have to be made accordingly.

<p align="center">
  <img src="">
</p>

## Table of contents

- [HelloID-Conn-Prov-Source-CAPP12](#helloid-conn-prov-source-capp12)
  - [Table of contents](#table-of-contents)
  - [Introduction](#introduction)
  - [Getting started](#getting-started)
    - [Prerequisites](#prerequisites)
    - [Connection settings](#connection-settings)
    - [Mapping](#mapping)
  - [Remarks](#remarks)
    - [API endpoints](#api-endpoints)
    - [API documentation](#api-documentation)
  - [Getting help](#getting-help)
  - [HelloID docs](#helloid-docs)

## Introduction

_HelloID-Conn-Prov-Source-CAPP12_ is a _Source_ connector. _CAPP12_ provides a set of REST API's that allow you to programmatically interact with its data.

This connector does not import HR data, it only imports basic user identifying information and educational certificate compliance status information. The connector can be used in combination with a HR import to create accounts based on the user identifying information and assigns contracts to these accounts based on the compliance status information.

## Getting started

### Prerequisites

Configure person aggregation in HelloID. This can be done by following the steps in the [HelloID documentation](https://docs.helloid.com/en/provisioning/Source-systems/powershell-v2-Source-systems.html#person-aggregation).

### Connection settings

The following settings are required to connect to the API.

| Setting  | Description                        | Mandatory |
| -------- | ---------------------------------- | --------- |
| ClientId | The ClientId to connect to the API | Yes       |
| ClientSecret | The ClientSecret to connect to the API | Yes       |
| BaseUrl  | The URL to the API                 | Yes       |
| HistoricalDays | Only certificates that were not expired X days ago will be imported. | Yes  |
| RequiredCertificatesOnly| Only import certificates that are required to be compliant | Yes  |

### Mapping
The mapping file contains the mapping between the API response and the HelloID contract attributes. The mapping file is included in this repository as `mapping.json`.  As there are no natural HelloID contract attributes for the compliance status information, the mapping file maps the API responses to rather arbitrary contract attributes.  Change the mapping in helloid accordingly if you want to use other contract attributes.

Division.Code contains the Required status (true/false)
Type.code contains the Compliance status (compliant/non-compliant)
Title.code contains the certificate code
Title.name contains the certificate name


## Remarks

- This connector does not import HR data, it only imports basic user identifying information and educational certificate compliance status information. The connector can be used in combination with a HR import to create accounts based on the user identifying information and assigns contracts to these accounts based on the compliance status information.
- The Business Rule conditions in HelloID can only compare attribute values in a single contract. If you want to compare values across multiple contracts, you will need to use either user Dynamic permissions with custom PowerShell code, or use user attributes instead of contract attributes by changing the connector code accordingly.
  
- This means that in practice you can only create a BR on obtaining a specific certificate and that everyone within this BR gets the same authorizations. From HelloID you cannot subdivide rights, after obtaining certification, based on function or department additionally.
### API endpoints

The following endpoints are used by the connector

| Endpoint | Description               |
| -------- | ------------------------- |
| /api/v3/compliance_status.csv  | Retrieve the compliance status information of all users |
| /api/v3/achievement_status.csv  | Retrieve the achievement status information of all users |
| /api/v1/users  | Retrieve the user identifying information of all users |

### API documentation
https://documenter.getpostman.com/view/17909805/UV5f6tSy#intro


## Getting help

> [!TIP]
> _For more information on how to configure a HelloID PowerShell connector, please refer to our [documentation](https://docs.helloid.com/en/provisioning/Source-systems/powershell-v2-Source-systems.html) pages_.

> [!TIP]
>  _If you need help, feel free to ask questions on our [forum](https://forum.helloid.com)_.

## HelloID docs

The official HelloID documentation can be found at: https://docs.helloid.com/
