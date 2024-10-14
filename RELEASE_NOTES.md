# Release Notes:

**Changes in : 2024.7.0**

- Fix to issue with scan types - BDIO was being counted as BINARY
- Fix number of versions in violation of policy where it is a RAPID scan only policy.  It reported all versions but should have been 'NA' or not applicable as these do not apply to full versions/scans.
- Added scan modes column to policy sheet (RAPID, FULL or RAPID;FULL)
- Added log file to zip to aid troubleshooting when the data is not all loaded.

**Changes in : 2024.7.0**

- Project groups are now collected and listing shown in the results including how many projects and which group is the parent group.
- Projects Summary specifies which project group the project is in.
- Bug fix for cell size limit being breached for very large policies.
  
**Changes in : 2024.4.0**

- Bug fix for binary scan type counts.

**Changes in : 2024.1.0**

- Bug fix for scan error rate percentage calculation.

**Changes in : 2023.12.1**

- Small change to ordering of observations.

**Changes in : 2023.12.0**

- Added automated 'observations' to summary sheet to highlight areas to focus on, including policy, scan rates, types and Sage results.
- Add more detail to description on certain SAGE sheets on what the measurements mean.
- Added error rate percentage by period in scan status worksheet.
- Introduced policy categories and number of project versions in violation of each policy including graphs
- Included statistics on policy categories and severities.
- Updated Apache POI to latest version to overcome bug.
- Updated blackduck-common library to latest.
- Fixed issue where Quick Links for worksheets with long titles was not working.