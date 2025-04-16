# PGC CANADA GNSS Data Availability Checker

## Overview

The PGC CANADA GNSS Data Availability Checker is a PowerShell script designed to check the availability of high-rate (15-minute interval) GNSS observation data from the Natural Resources Canada (NRCan) PGC (Pacific Geoscience Centre) anonymous FTP archive. It helps users determine the availability of data for specific Canadian GNSS stations over a defined period.

## Features

- Checks availability of high-rate (15-minute) GNSS data (RINEX v3 format).
- Calculates the number of available 15-minute files per hour for each day.
- Supports parallel processing for faster checks (optimized for PowerShell 7+, fallback for PS 5.1).
- Caches FTP directory listings to reduce redundant requests.
- Generates detailed CSV and summary TXT reports.
- Configurable concurrency level for parallel operations.

## Requirements

- Windows operating system
- PowerShell 5.1 or later (PowerShell 7+ recommended for better performance)
- Internet connection with access to the PGC FTP server (`ftp://wcda.pgc.nrcan.gc.ca`)

## Parameters

| Parameter     | Type     | Required | Description                                                                 |
|---------------|----------|----------|-----------------------------------------------------------------------------|
| stationId     | string   | Yes      | The 4-character ID of the GNSS station (e.g., ALBH, CHUR). Case-insensitive. |
| startDate     | DateTime | Yes      | The start date for the check period (YYYY-MM-DD format).                   |
| endDate       | DateTime | Yes      | The end date for the check period (YYYY-MM-DD format).                     |
| maxConcurrent | int      | No       | Maximum number of parallel FTP checks (default: 10).                        |

## Usage

Run the script from a PowerShell terminal, providing the necessary parameters:

```powershell
.\script\PGC_CAN_GNSS_Data_Availability_Checker.ps1 -stationId "ALBH" -startDate "2024-01-01" -endDate "2024-01-10"
```

### Examples

1. Check data for station ALBH for the first 10 days of January 2024:
   ```powershell
   .\script\PGC_CAN_GNSS_Data_Availability_Checker.ps1 -stationId "ALBH" -startDate "2024-01-01" -endDate "2024-01-10"
   ```

2. Check data for station CHUR for February 2024 with increased concurrency:
   ```powershell
   .\script\PGC_CAN_GNSS_Data_Availability_Checker.ps1 -stationId "CHUR" -startDate "2024-02-01" -endDate "2024-02-29" -maxConcurrent 15
   ```

## Output

The script generates output files in a subdirectory structure: `.\results\PGC_CAN\<stationId>\`.

1.  **CSV file**: Contains detailed availability per hour for each day.
    -   Filename: `<stationId>_highrate_3_<startDateYYYYMMDD>_<endDateYYYYMMDD>.csv`
    -   Columns: `year,doy,00,01,02,...,22,23,percentage`
    -   Hourly columns (00-23) show the count of available 15-minute files found for that hour (0 to 4).
    -   `percentage` shows the percentage of available 15-minute slots for that day (out of 96).

2.  **Text report file**: Provides a summary of the check.
    -   Filename: `<stationId>_highrate_3_<startDateYYYYMMDD>_<endDateYYYYMMDD>.txt`
    -   Content: Includes station ID, date range, summary statistics (total days checked, days with data, total slots checked, slots available, overall percentage), report generation time, and total execution time.

## Performance Considerations

-   **Parallel Processing**: The script leverages parallel operations to speed up checks. PowerShell 7+ uses the more efficient `ForEach-Object -Parallel`, while PowerShell 5.1 uses Runspace Pools.
-   **FTP Caching**: Directory listings are cached in memory during the script run to avoid repeated requests for the same daily directory.
-   **Concurrency**: The `-maxConcurrent` parameter controls how many parallel FTP connections are attempted. Setting this too high might overload your network or the FTP server.

## FTP Directory Structure

The script accesses the following FTP path structure on the PGC server:

`ftp://wcda.pgc.nrcan.gc.ca/pub/gpsdata/rinexv3/<year>/<doy>/`

Where:
-   `<year>` is the 4-digit year.
-   `<doy>` is the 3-digit day of the year (001-366).

It looks for high-rate compressed RINEX v3 files matching the pattern:
`<STATIONID_UPPER>*<YYYY><DOY><HH>*_15M_01S_MO.crx.gz`

## Troubleshooting

-   **FTP Connection Errors**: Ensure your firewall allows passive FTP connections to `wcda.pgc.nrcan.gc.ca`. The PGC FTP server does not typically require authentication for public data access. Check if the server is online or undergoing maintenance.
-   **Slow Performance**: Checking long date ranges can be time-consuming. Ensure you have a stable internet connection. Adjusting `-maxConcurrent` might help, but excessively high values can be counterproductive. Using PowerShell 7+ is recommended for better performance.
-   **No Data Found**: Double-check the `stationId` and the date range. Verify that the station was operational and providing high-rate data during that period. Data might sometimes be delayed in appearing on the archive.
-   **Incorrect File Counts**: The script relies on the specific file naming convention used by PGC for high-rate RINEX v3 data. If this convention changes, the script's file matching pattern might need updating.

## License

This script is provided as-is. Use at your own risk. No warranty is expressed or implied. 