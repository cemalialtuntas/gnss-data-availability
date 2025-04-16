# gnss-data-availability
A collection of PowerShell utilities for checking the presence or absence of GNSS data in online archives. Scripts support multiple protocols (HTTP/FTP) and generate structured reports to identify missing data periods across different stations and timeframes.

## Available Scripts

### CDDIS GNSS Data Availability Checker

The CDDIS GNSS Data Availability Checker is a PowerShell script that checks availability of GNSS observation data from NASA's CDDIS (Crustal Dynamics Data Information System) FTP archives. The script supports:

- Daily, hourly, or high-rate (15-minute) GNSS data checks
- RINEX versions 2 and 3 (including RINEX version 4)
- Parallel processing for improved performance
- CSV and text report outputs

#### Basic Usage

```powershell
.\script\CDDIS_GNSS_Data_Availability_Checker.ps1 -stationId "BRST" -startDate "2025-01-01" -endDate "2025-01-31" -dataType "daily" -rinexVersion 3
```

For more detailed information, parameter descriptions, and advanced usage examples, please refer to the [CDDIS GNSS Data Availability Checker documentation](script/README_for_CDDIS_GNSS_Data_Availability_Checker.md).

### IGN ESP GNSS Data Availability Checker

The IGN ESP GNSS Data Availability Checker is a PowerShell script designed to check the availability of hourly GNSS observation data from the Spanish National Geographic Institute (IGN) HTTPS archive. The script supports:

- Hourly (1-second) data checks
- HTTPS web requests for checking availability
- CSV and text report outputs

#### Basic Usage

```powershell
.\script\IGN_ESP_GNSS_Data_Availability_Checker.ps1 -stationId "BCL1" -startDate "2025-01-01" -endDate "2025-01-05"
```

For more detailed information, parameter descriptions, and usage examples, please refer to the [IGN ESP GNSS Data Availability Checker documentation](script/README_for_IGN_ESP_GNSS_Data_Availability_Checker.md).

### PGC CANADA GNSS Data Availability Checker

The PGC CANADA GNSS Data Availability Checker is a PowerShell script designed to check the availability of high-rate (15-minute interval) GNSS observation data from the Natural Resources Canada (NRCan) PGC (Pacific Geoscience Centre) anonymous FTP archive. The script supports:

- High-rate (15-minute) data checks (RINEX v3)
- Parallel processing for improved performance
- FTP directory caching
- CSV and text report outputs

#### Basic Usage

```powershell
.\script\PGC_CAN_GNSS_Data_Availability_Checker.ps1 -stationId "ALBH" -startDate "2024-01-01" -endDate "2024-01-10"
```

For more detailed information, parameter descriptions, and usage examples, please refer to the [PGC CANADA GNSS Data Availability Checker documentation](script/README_for_PGC_CAN_GNSS_Data_Availability_Checker.md).
