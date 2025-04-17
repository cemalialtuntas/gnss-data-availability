# IGN ESP GNSS Data Availability Checker

## Overview

The IGN ESP GNSS Data Availability Checker is a PowerShell script that checks the availability of GNSS (Global Navigation Satellite System) observation data from the Spanish National Geographic Institute (IGN) HTTPS archive. This tool helps determine the hourly availability of 1-second data for specific stations and time periods from the IGN ESP repository.

## Features

- Checks availability of hourly (1-second) GNSS data
- Uses HTTPS web requests to check directory listings
- Generates reports and CSV output detailing hourly availability
- Simple parameter-based execution

## Requirements

- Windows operating system
- PowerShell 5.1 or later
- Internet connection with access to IGN HTTPS server (https://datos-geodesia.ign.es)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| stationId | string | Yes | Station ID (e.g., BCL1, ACOR) |
| startDate | DateTime | Yes | Start date in YYYY-MM-dd format |
| endDate | DateTime | Yes | End date in YYYY-MM-dd format |

## Usage

Run the script from PowerShell by providing the required parameters:

```powershell
.\script\IGN_ESP_GNSS_Data_Availability_Checker.ps1 -stationId "BCL1" -startDate "2025-01-01" -endDate "2025-01-05"
```

### Examples

1. Check hourly data availability for station BCL1 during the first 5 days of January 2025:
   ```powershell
   .\script\IGN_ESP_GNSS_Data_Availability_Checker.ps1 -stationId "BCL1" -startDate "2025-01-01" -endDate "2025-01-05"
   ```

2. Check hourly data availability for station ACOR during February 2025:
   ```powershell
   .\script\IGN_ESP_GNSS_Data_Availability_Checker.ps1 -stationId "ACOR" -startDate "2025-02-01" -endDate "2025-02-28"
   ```

## Output

The script creates output in a directory named `results/IGN_ESP/<stationId>` in the current working directory. Two types of files are generated:

1.  **CSV file**: Contains detailed hourly availability information.
    - Columns: `year,doy,00,01,02,...,22,23,percentage`
    - Hourly columns (00-23) show a binary indicator (1 for available, 0 for unavailable).
    - `percentage` shows the percentage of available hours for that day.

2.  **Text report**: Provides a summary of the results.
    - Lists configuration parameters (station, date range).
    - Shows overall statistics (days checked, total hours checked, available hours, overall percentage).
    - Includes the total execution time.

The filenames follow this pattern:
```
<stationId>_hourly_<startDate>_<endDate>.[csv|txt]
```
Example: `BCL1_hourly_20250101_20250105.csv`

## Data Source URL Structure

The script checks for data availability by accessing URLs structured like this:

```
https://datos-geodesia.ign.es/ERGNSS/horario_1s/<YYYYMMDD>/<HH>/
```

Where:
- `<YYYYMMDD>` is the date (e.g., 20250101)
- `<HH>` is the 2-digit hour (00-23)

It then looks for compressed CRINEX files (`*_MO.crx.gz`) within the directory listing for the specified `stationId`.

## Troubleshooting

Common issues and solutions:

1.  **HTTPS Connection Failures**:
    - Ensure your network allows HTTPS connections to `datos-geodesia.ign.es`.
    - Check for firewall restrictions or proxy settings.

2.  **Long Execution Times**:
    - The script checks each hour for each day sequentially. Checking long date ranges can take time.
    - Network latency to the IGN server can affect speed.

3.  **Missing Data**:
    - Verify the `stationId` is correct and expected to have data in the IGN archive for the specified period.
    - Data availability might be delayed or incomplete on the server.
    - The file pattern (`*_MO.crx.gz`) might need adjustment if IGN changes its naming conventions.

## License

This script is provided as-is with no warranty. Use at your own risk. 