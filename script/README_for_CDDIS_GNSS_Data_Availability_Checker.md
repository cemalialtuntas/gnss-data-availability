# CDDIS GNSS Data Availability Checker

## Overview

The CDDIS GNSS Data Availability Checker is a PowerShell script that checks the availability of GNSS (Global Navigation Satellite System) observation data from NASA's CDDIS (Crustal Dynamics Data Information System) FTP archives. This tool is designed to help researchers and analysts quickly determine which GNSS data is available for specific stations and time periods.

## Features

- Check availability of daily, hourly, or high-rate (15-minute) GNSS data
- Support for both RINEX version 2 and 3 (including RINEX version 4)
- Parallel processing for improved performance
- Comprehensive reports and CSV output
- Configurable concurrency settings

## Requirements

- Windows operating system
- PowerShell 5.1 or later (optimized for PowerShell 7+)
- Internet connection with access to CDDIS FTP servers (ftp://gdc.cddis.eosdis.nasa.gov)

## Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| stationId | string | Yes | Station ID (e.g., BRST, MARS) |
| startDate | DateTime | Yes | Start date in YYYY-MM-DD format |
| endDate | DateTime | Yes | End date in YYYY-MM-DD format |
| dataType | string | Yes | Type of data to check: "daily", "hourly", or "highrate" |
| rinexVersion | int | Yes | RINEX version: 2 or 3 (where 3 also covers RINEX version 4) |
| maxConcurrent | int | No | Maximum number of concurrent operations (default: 10) |

## Usage

Run the script from PowerShell by providing the required parameters:

```powershell
.\script\CDDIS_GNSS_Data_Availability_Checker.ps1 -stationId "BRST" -startDate "2025-01-01" -endDate "2025-01-31" -dataType "daily" -rinexVersion 3
```

### Examples

1. Check daily data availability for station BRST during January 2025:
   ```powershell
   .\script\CDDIS_GNSS_Data_Availability_Checker.ps1 -stationId "BRST" -startDate "2025-01-01" -endDate "2025-01-31" -dataType "daily" -rinexVersion 3
   ```

2. Check hourly data availability for station MARS during February 2025:
   ```powershell
   .\script\CDDIS_GNSS_Data_Availability_Checker.ps1 -stationId "MARS" -startDate "2025-02-01" -endDate "2025-02-28" -dataType "hourly" -rinexVersion 2
   ```

3. Check high-rate data availability for station MOBS with increased concurrency:
   ```powershell
   .\script\CDDIS_GNSS_Data_Availability_Checker.ps1 -stationId "MOBS" -startDate "2025-03-01" -endDate "2025-03-07" -dataType "highrate" -rinexVersion 3 -maxConcurrent 15
   ```

## Output

The script creates output in a directory named `results/CDDIS/<stationId>` in the current working directory. Two types of files are generated:

1. **CSV file**: Contains detailed availability information
   - For daily data: Shows a binary indicator (1 or 0) for each day
   - For hourly data: Shows availability for each hour of each day
   - For high-rate data: Shows the number of available 15-minute files for each hour

2. **Text report**: Provides a summary of the results
   - Lists configuration parameters
   - Shows overall statistics (days checked, hours with data available, etc.)
   - Displays overall data availability percentage

The filenames follow this pattern:
```
<stationId>_<dataType>_<rinexVersion>_<startDate>_<endDate>.[csv|txt]
```

## Performance Considerations

- The script automatically detects PowerShell version and uses optimized parallel processing methods:
  - PowerShell 7+: Uses `ForEach-Object -Parallel` for optimal performance
  - PowerShell 5.1 or earlier: Uses runspace pools for parallelization
- Thread-safe caching of FTP directory listings improves performance when checking multiple dates
- The `maxConcurrent` parameter can be adjusted based on your system's capabilities and network bandwidth

## FTP Directory Structure

The script accesses the following FTP paths on the CDDIS server:

- Daily data: `ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/daily/<year>/<doy>/<yy>d/`
- Hourly data: `ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/hourly/<year>/<doy>/<hour>/`
- High-rate data: `ftp://gdc.cddis.eosdis.nasa.gov/highrate/<year>/<doy>/<yy>d/<hour>/`

Where:
- `<year>` is the 4-digit year
- `<yy>` is the 2-digit year
- `<doy>` is the 3-digit day of year
- `<hour>` is the 2-digit hour (00-23)

## Troubleshooting

Common issues and solutions:

1. **FTP Connection Failures**:
   - Ensure your network allows FTP connections to CDDIS servers
   - Check that you have proper authentication if required by your organization

2. **Long Execution Times**:
   - Reduce the date range being checked
   - Increase the `maxConcurrent` parameter (if your network supports it)
   - Use PowerShell 7+ for improved parallel processing

3. **Missing Data**:
   - Verify the station ID is correct and active during the date range
   - Check that you're using the correct RINEX version for the specific station
   - Some data might be delayed in posting to the CDDIS archives

## License

This script is provided as-is with no warranty. Use at your own risk. 