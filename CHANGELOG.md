# Change Log

All notable changes to this project will be documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [1.2.0] - 16-07-2026
### Added
- Added configuration option for BaseUrl to specify the CAPP12 API endpoint
- Added configuration option CompliantCertificatesOnly to filter certificates by compliance status
- Added configuration option IncludeCertificateCodes to include certificate codes in the output
- Enhanced compliance logic for contract and person mappings

### Changed
- Refactored persons.ps1 for improved logging and error handling
- Enhanced user data processing and compliance checks
- Modified validation requirements in mapping.json to improve data quality
- Updated HistoricalDays configuration placeholder for better clarity
- Updated RequiredCertificatesOnly default value in configuration
- Improved README.md with clearer usage instructions, requirements, and feature descriptions

## [1.1.0] - 15-06-2026
### Added
- Added the option to only import certificates that are required to be compliant.
- Added the option to only import certificates that were not expired X days ago.
### Changed  
-  fixed missing start and end date to the contract mapping
-  fixed contract external id to be globally unique by prefixing it with the user id
-  fix: removed users without any contracts from the output, per HelloID requirements

## [1.0.0] - 19-05-2026

This is the first official release of _HelloID-Conn-Prov-Target-CAPP12_.

### Added

### Changed

### Deprecated

### Removed