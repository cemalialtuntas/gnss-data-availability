# Script to check data availability in GNSS data archive (IGN ESP)
# Checks day by day and hour by hour if data exists for a specified station

# Define parameters (user-configurable section)
param(
    [Parameter(Mandatory=$true)]
    [string]$stationId,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$startDate,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$endDate
)

# Record start time
$startTime = Get-Date

# Base URL for the IGN ESP archive (hourly data)
$baseUrl = "https://datos-geodesia.ign.es/ERGNSS/horario_1s"

# Create output directory if it doesn't exist
$outputDir = ".\results\IGN_ESP\$stationId"
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "Output directory created: $outputDir"
}

# Generate filenames based on parameters
$dateRangeStr = "$($startDate.ToString('yyyyMMdd'))_$($endDate.ToString('yyyyMMdd'))"
$csvFileName = "$outputDir\${stationId}_hourly_$dateRangeStr.csv"
$reportFileName = "$outputDir\${stationId}_hourly_$dateRangeStr.txt"

# Prepare CSV header
$csvHeader = "year,doy,00,01,02,03,04,05,06,07,08,09,10,11,12,13,14,15,16,17,18,19,20,21,22,23,percentage"
$csvHeader | Out-File -FilePath $csvFileName -Encoding utf8

# Initialize results array and counters
$results = @()
$totalDays = ($endDate - $startDate).Days + 1
$totalHoursChecked = 0
$availableHoursCount = 0
$availableDaysCount = 0

# Function to convert date to day of year (DOY)
function Get-DayOfYear {
    param (
        [DateTime]$date
    )
    return $date.DayOfYear.ToString("000")
}

# Loop through each day in the date range
$currentDate = $startDate
while ($currentDate -le $endDate) {
    $year = $currentDate.Year
    $doy = Get-DayOfYear -date $currentDate
    $dateStr = $currentDate.ToString("yyyyMMdd")
    $foundDataToday = $false
    $hourlyAvailability = 0
    
    # Initialize row for this day
    $row = [ordered]@{
        "year" = $year
        "doy" = $doy
    }
    
    # Check each hour (00-23)
    for ($hour = 0; $hour -lt 24; $hour++) {
        $hourStr = "{0:D2}" -f $hour
        $totalHoursChecked++
        
        # Create the check URL
        $checkUrl = "$baseUrl/$dateStr/$hourStr/"
        $hourVal = 0 # Default to unavailable
        
        try {
            # Try to get directory listing
            $response = Invoke-WebRequest -Uri $checkUrl -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
            
            # Check if any files for this station exist
            # Assuming standard CRINEX file naming like BCL100ESP_R_YYYYDOYHHMM_01H_01S_MO.crx.gz
            # Adjust the pattern if the naming convention is different
            $stationPattern = $stationId.ToUpper().Substring(0, 4) + "*_MO.crx.gz" 
            $hasData = $response.Links | Where-Object { $_.href -like $stationPattern } | Measure-Object | Select-Object -ExpandProperty Count
            
            if ($hasData -gt 0) {
                # Data exists
                $hourVal = 1
                $foundDataToday = $true
                $availableHoursCount++
                $hourlyAvailability++
            }
        } catch {
            # Directory doesn't exist, couldn't be accessed, or timed out
            # Keep $hourVal = 0
        }
        
        $row[$hourStr] = $hourVal
    }
    
    # Calculate daily percentage
    $dailyPercentage = [math]::Round(($hourlyAvailability / 24) * 100, 2)
    $row["percentage"] = $dailyPercentage
    
    # Add the processed row to results
    $results += [PSCustomObject]$row
    
    # Increment available days count if any data was found
    if ($foundDataToday) {
        $availableDaysCount++
    }
    
    # Move to the next day
    $currentDate = $currentDate.AddDays(1)
}

# Sort results by year and DOY
$results = $results | Sort-Object -Property year, doy

# Calculate overall percentage
$overallPercentage = 0
if ($totalHoursChecked -gt 0) {
    $overallPercentage = [math]::Round(($availableHoursCount / $totalHoursChecked) * 100, 2)
}

# Export CSV results (removing quotes for consistency with CDDIS script output)
# Convert to CSV strings in memory
$csvContent = $results | ConvertTo-Csv -NoTypeInformation
# Remove quotes
$csvContentWithoutQuotes = $csvContent | ForEach-Object { $_ -replace '"', '' }
# Save to file
Set-Content -Path $csvFileName -Value $csvContentWithoutQuotes -Encoding utf8

# Generate report
$reportContent = @"
IGN ESP GNSS Data Availability Report
======================================
Station ID: $stationId
Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))
Data Type: hourly (1-second)

Summary Statistics:
------------------
Total Days Checked: $totalDays
Days with Some Data Available: $availableDaysCount
Total Hours Checked: $totalHoursChecked
Hours with Data Available: $availableHoursCount
Overall Data Availability: $overallPercentage%
"@

# Calculate and append total execution time
$endTime = Get-Date
$duration = $endTime - $startTime
$durationString = "{0:hh\:mm\:ss\.fff}" -f $duration
$reportContent += @"

Report Generated On: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))
Total Execution Time: $durationString
"@

$reportContent | Out-File -FilePath $reportFileName -Encoding utf8

# Display summary to console
Write-Host "IGN ESP GNSS Data Availability Check Completed" -ForegroundColor Green
Write-Host "Station: $stationId | Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "Data Type: hourly" -ForegroundColor Cyan
Write-Host "Overall Availability: $overallPercentage%" -ForegroundColor Yellow
Write-Host "Results saved to: $outputDir" -ForegroundColor Magenta
Write-Host "Total execution time: $durationString" -ForegroundColor Gray