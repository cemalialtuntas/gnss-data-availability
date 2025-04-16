# PGC CANADA GNSS Data Availability Checker
# This script checks the availability of high-rate GNSS observation data from the PGC Canada FTP archive.
# Checks day by day, counting available 15-minute files per hour for a specified station.

# Define parameters
param(
    [Parameter(Mandatory=$true)]
    [string]$stationId,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$startDate,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$endDate,
    
    [Parameter(Mandatory=$false)]
    [int]$maxConcurrent = 10 # Default concurrency for parallel operations
)

# Record start time
$startTime = Get-Date

# --- Constants ---
$ftpBaseUrl = "ftp://wcda.pgc.nrcan.gc.ca/pub/gpsdata/rinexv3"
$dataType = "highrate"
$rinexVersion = 3
$filesPerHour = 4 # Highrate data has 4 files per hour (00, 15, 30, 45 min)
$slotsPerDay = $filesPerHour * 24 # 96 slots per day

# --- Helper Functions ---

# Function to convert date to day of year (DOY)
function Get-DayOfYear {
    param (
        [DateTime]$date
    )
    return $date.DayOfYear.ToString("000")
}

# Create a thread-safe cache for FTP listings
$script:FtpCache = [hashtable]::Synchronized(@{})

# Function to get a directory listing from an FTP server with caching
function Get-FtpDirectoryListing {
    param (
        [string]$ftpUrl
    )
    
    # Check cache first
    if ($script:FtpCache.ContainsKey($ftpUrl)) {
        return $script:FtpCache[$ftpUrl]
    }
    
    $request = $null
    $response = $null
    $stream = $null
    $reader = $null
    $fileList = @()

    try {
        $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $request.EnableSsl = $false # PGC FTP might not use SSL
        $request.UsePassive = $true
        $request.UseBinary = $true
        $request.KeepAlive = $false
        $request.Timeout = 30000 # Increased timeout for potentially slower FTP

        try {
            $response = $request.GetResponse()
            $stream = $response.GetResponseStream()
            # Assuming ASCII encoding for directory listing
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII) 
            
            while (($line = $reader.ReadLine()) -ne $null) {
                $fileName = $line.Trim()
                if ($fileName -and $fileName -ne '.' -and $fileName -ne '..') {
                    $fileList += $fileName
                }
            }
            
            # Store in cache
            $script:FtpCache[$ftpUrl] = $fileList
            return $fileList
        }
        catch [System.Net.WebException] {
            $ftpResponse = $_.Exception.Response
            if ($ftpResponse -ne $null -and $ftpResponse -is [System.Net.FtpWebResponse]) {
                # Handle 'file unavailable' (directory not found) explicitly
                if ($ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable -or `
                    $ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailableOrBusy) {
                     # Cache empty results for not found directories
                     $script:FtpCache[$ftpUrl] = @()
                     return @()
                }
                Write-Warning "FTP Warning for $($ftpUrl): $($ftpResponse.StatusCode) - $($ftpResponse.StatusDescription)"
            } else {
                 Write-Warning "FTP Error for $($ftpUrl): $($_.Exception.Message)"
            }
            # Return null on other errors to indicate a problem
            return $null 
        }
        finally {
             if ($reader -ne $null) { try { $reader.Close() } catch {} }
             if ($stream -ne $null) { try { $stream.Close() } catch {} }
             if ($response -ne $null) { try { $response.Close() } catch {} }
        }
    }
    catch {
        Write-Warning "General Error accessing FTP URL $($ftpUrl): $($_.Exception.Message)"
        return $null # Return null on critical error
    }
}

# --- Main Logic ---

# Initialize results
$results = @()
$totalDays = ($endDate - $startDate).Days + 1

# Create output directory
$outputDir = ".\results\PGC_CAN\$stationId"
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "Output directory created: $outputDir"
}

# Prepare list of dates to process
$datesToProcess = @()
$currentDate = $startDate
while ($currentDate -le $endDate) {
    $datesToProcess += $currentDate
    $currentDate = $currentDate.AddDays(1)
}

# Check for PowerShell 7+ parallel processing capability
$canUseParallel = $PSVersionTable.PSVersion.Major -ge 7

if ($canUseParallel) {
    # Use PowerShell 7+ ForEach-Object -Parallel
    Write-Host "Using PowerShell 7+ parallel processing (Max Concurrent: $maxConcurrent)" -ForegroundColor Green
    $results = $datesToProcess | ForEach-Object -ThrottleLimit $maxConcurrent -Parallel {
        $date = $_
        $stationId = $using:stationId
        $ftpBaseUrl = $using:ftpBaseUrl
        $slotsPerDay = $using:slotsPerDay
        
        # Redefine needed functions and variables in the parallel runspace
        $ftpCache = $using:FtpCache 

        function Get-DayOfYear {
            param ([DateTime]$date)
            return $date.DayOfYear.ToString("000")
        }
        
        # --- FTP Function (copied for parallel scope) ---
        function Get-FtpDirectoryListing {
            param ([string]$ftpUrl)
            $threadSafeCache = $using:ftpCache # Access cache from parent scope
            if ($threadSafeCache.ContainsKey($ftpUrl)) { return $threadSafeCache[$ftpUrl] }
            
            $request = $null; $response = $null; $stream = $null; $reader = $null
            $fileList = @()
            try {
                $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
                $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
                $request.EnableSsl = $false; $request.UsePassive = $true; $request.UseBinary = $true
                $request.KeepAlive = $false; $request.Timeout = 30000
                try {
                    $response = $request.GetResponse()
                    $stream = $response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
                    while (($line = $reader.ReadLine()) -ne $null) {
                        $fileName = $line.Trim()
                        if ($fileName -and $fileName -ne '.' -and $fileName -ne '..') { $fileList += $fileName }
                    }
                    $threadSafeCache[$ftpUrl] = $fileList
                    return $fileList
                } catch [System.Net.WebException] {
                    $ftpResponse = $_.Exception.Response
                    if ($ftpResponse -ne $null -and $ftpResponse -is [System.Net.FtpWebResponse]) {
                        if ($ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable -or `
                            $ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailableOrBusy) {
                             $threadSafeCache[$ftpUrl] = @()
                             return @()
                        }
                    }
                    return $null # Indicate error
                } finally {
                     if ($reader -ne $null) { try { $reader.Close() } catch {} }
                     if ($stream -ne $null) { try { $stream.Close() } catch {} }
                     if ($response -ne $null) { try { $response.Close() } catch {} }
                }
            } catch { return $null } # Indicate error
        }
        # --- End FTP Function Copy ---

        # Process this date
        $year = $date.Year
        $doy = Get-DayOfYear -date $date
        $stationIdUpper = $stationId.ToUpper() # PGC uses uppercase station ID in filenames

        $row = [ordered]@{
            "year" = $year
            "doy" = $doy
        }
        
        $totalFilesFoundToday = 0
        
        # Construct the URL for the specific day
        $dailyUrl = "$ftpBaseUrl/$year/$doy/"
        
        # Get the listing for the entire day once
        $dailyFiles = Get-FtpDirectoryListing -ftpUrl $dailyUrl
        
        # Process each hour
        for ($hour = 0; $hour -lt 24; $hour++) {
            $hourStr = $hour.ToString("00")
            $filesInHour = 0
            
            if ($null -ne $dailyFiles) {
                # Define the pattern for files for this station and hour
                # Example: TFNO20250320000_015M_01S_MO.crx.gz (minute part is variable)
                # We need files starting with stationID + YYYY + DOY + HH
                # And ending with _015M_01S_MO.crx.gz
                $pattern = "$($stationIdUpper)*$($year)$($doy)$($hourStr)*_15M_01S_MO.crx.gz"
                
                # Count matching files in the daily listing
                $filesInHour = ($dailyFiles | Where-Object { $_ -like $pattern }).Count
            }
            
            $row[$hourStr] = $filesInHour
            $totalFilesFoundToday += $filesInHour
        }
        
        # Calculate daily percentage
        $dailyPercentage = 0
        if ($slotsPerDay -gt 0) { # Avoid division by zero if constants change
             $dailyPercentage = [math]::Round(($totalFilesFoundToday / $slotsPerDay) * 100, 2)
        }
        $row["percentage"] = $dailyPercentage
        
        # Return the processed row
        return [PSCustomObject]$row
    }
} 
else {
    # Legacy approach using Runspaces for PowerShell 5.1
    Write-Host "Using legacy parallel processing for PowerShell 5.1 (Max Concurrent: $maxConcurrent)" -ForegroundColor Yellow
    
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxConcurrent)
    $runspacePool.Open()
    
    # Define the script block to run in separate runspaces
    $scriptBlock = {
        param($date, $stationId, $ftpBaseUrl, $slotsPerDay, $ftpCache)
        
        # Define needed functions within the script block
        function Get-DayOfYear { param ([DateTime]$date) return $date.DayOfYear.ToString("000") }

        function Get-FtpDirectoryListing {
             param ([string]$ftpUrl)
             # Use the passed-in synchronized cache
             if ($ftpCache.ContainsKey($ftpUrl)) { return $ftpCache[$ftpUrl] }
             
             $request = $null; $response = $null; $stream = $null; $reader = $null
             $fileList = @()
             try {
                 $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
                 $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
                 $request.EnableSsl = $false; $request.UsePassive = $true; $request.UseBinary = $true
                 $request.KeepAlive = $false; $request.Timeout = 30000
                 try {
                     $response = $request.GetResponse()
                     $stream = $response.GetResponseStream()
                     $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::ASCII)
                     while (($line = $reader.ReadLine()) -ne $null) {
                         $fileName = $line.Trim()
                         if ($fileName -and $fileName -ne '.' -and $fileName -ne '..') { $fileList += $fileName }
                     }
                     $ftpCache[$ftpUrl] = $fileList # Add to shared cache
                     return $fileList
                 } catch [System.Net.WebException] {
                     $ftpResponse = $_.Exception.Response
                     if ($ftpResponse -ne $null -and $ftpResponse -is [System.Net.FtpWebResponse]) {
                         if ($ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable -or `
                             $ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailableOrBusy) {
                              $ftpCache[$ftpUrl] = @() # Cache empty result
                              return @()
                         }
                     }
                     return $null # Indicate error
                 } finally {
                      if ($reader -ne $null) { try { $reader.Close() } catch {} }
                      if ($stream -ne $null) { try { $stream.Close() } catch {} }
                      if ($response -ne $null) { try { $response.Close() } catch {} }
                 }
             } catch { return $null } # Indicate error
        }

        # Process the date (same logic as in PS7+ block)
        $year = $date.Year
        $doy = Get-DayOfYear -date $date
        $stationIdUpper = $stationId.ToUpper()

        $row = [ordered]@{ "year" = $year; "doy" = $doy }
        $totalFilesFoundToday = 0
        $dailyUrl = "$ftpBaseUrl/$year/$doy/"
        $dailyFiles = Get-FtpDirectoryListing -ftpUrl $dailyUrl
        
        for ($hour = 0; $hour -lt 24; $hour++) {
            $hourStr = $hour.ToString("00")
            $filesInHour = 0
            if ($null -ne $dailyFiles) {
                $pattern = "$($stationIdUpper)*$($year)$($doy)$($hourStr)*_15M_01S_MO.crx.gz"
                $filesInHour = ($dailyFiles | Where-Object { $_ -like $pattern }).Count
            }
            $row[$hourStr] = $filesInHour
            $totalFilesFoundToday += $filesInHour
        }
        
        $dailyPercentage = 0
        if ($slotsPerDay -gt 0) {
             $dailyPercentage = [math]::Round(($totalFilesFoundToday / $slotsPerDay) * 100, 2)
        }
        $row["percentage"] = $dailyPercentage
        
        return [PSCustomObject]$row
    }
    
    # Submit jobs to the runspace pool
    $jobs = @()
    $jobCounter = 0
    foreach ($date in $datesToProcess) {
        $jobCounter++
        Write-Progress -Activity "Submitting Jobs" -Status "Queuing Date: $($date.ToString('yyyy-MM-dd')) ($jobCounter/$totalDays)" -PercentComplete (($jobCounter / $totalDays) * 100)
        
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($date).AddArgument($stationId).AddArgument($ftpBaseUrl).AddArgument($slotsPerDay).AddArgument($script:FtpCache)
        $powershell.RunspacePool = $runspacePool
        
        $job = @{
            Pipe = $powershell
            AsyncResult = $powershell.BeginInvoke()
        }
        $jobs += $job
    }
    Write-Progress -Activity "Submitting Jobs" -Completed
    
    # Collect results
    $jobCounter = 0
    foreach ($job in $jobs) {
        $jobCounter++
        Write-Progress -Activity "Collecting Results" -Status "Waiting for job ($jobCounter/$totalDays)" -PercentComplete (($jobCounter / $totalDays) * 100)
        try {
            $results += $job.Pipe.EndInvoke($job.AsyncResult)
        } catch {
             Write-Warning ("Error collecting result for job {0}: {1}" -f $jobCounter, $_.Exception.Message)
        } finally {
             $job.Pipe.Dispose()
        }
    }
     Write-Progress -Activity "Collecting Results" -Completed

    # Clean up runspace pool
    $runspacePool.Close()
    $runspacePool.Dispose()
}

# Sort results
$results = $results | Sort-Object -Property year, doy

# --- Calculate Overall Statistics ---
$availableDaysCount = 0
$availableHighrateSlots = 0
$totalHighrateSlotsChecked = $totalDays * $slotsPerDay

foreach ($row in $results) {
    $filesToday = 0
    for ($hour = 0; $hour -lt 24; $hour++) {
        $hourStr = $hour.ToString("00")
        # Ensure the property exists before accessing
        if ($row.PSObject.Properties.Name -contains $hourStr) {
             $filesToday += $row.$hourStr
        }
    }
    
    $availableHighrateSlots += $filesToday
    if ($filesToday -gt 0) {
        $availableDaysCount++
    }
}

# Calculate overall percentage
$overallPercentage = 0
if ($totalHighrateSlotsChecked -gt 0) {
    $overallPercentage = [math]::Round(($availableHighrateSlots / $totalHighrateSlotsChecked) * 100, 2)
}

# --- Generate Output Files ---

# Define output filenames
$dateRangeStr = "$($startDate.ToString('yyyyMMdd'))_$($endDate.ToString('yyyyMMdd'))"
$csvFileName = "$outputDir\${stationId}_${dataType}_${rinexVersion}_${dateRangeStr}.csv"
$reportFileName = "$outputDir\${stationId}_${dataType}_${rinexVersion}_${dateRangeStr}.txt"

# Export CSV (handle PS version differences for quoting)
try {
    if ($canUseParallel) { # PS 7+ has -UseQuotes
        $results | Export-Csv -Path $csvFileName -NoTypeInformation -UseQuotes Never -Encoding utf8 -ErrorAction Stop
    } else { # PS 5.1 workaround
        $csvHeader = ($results[0].PSObject.Properties | Select-Object -ExpandProperty Name) -join ','
        $csvContent = $results | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 # Skip default header
        # Manually remove quotes
        $csvContentWithoutQuotes = $csvContent | ForEach-Object { $_ -replace '"', '' } 
        # Prepend correct header and save
        Set-Content -Path $csvFileName -Value ($csvHeader, $csvContentWithoutQuotes) -Encoding utf8 -ErrorAction Stop
    }
    Write-Host "CSV results saved to: $csvFileName" -ForegroundColor Green
} catch {
     Write-Error "Failed to save CSV file '$csvFileName': $($_.Exception.Message)"
}


# Generate TXT report content
$reportContent = @"
PGC CANADA GNSS Data Availability Report
======================================
Station ID: $($stationId.ToUpper())
Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))
Data Type: $dataType
RINEX Version: $rinexVersion

Summary Statistics:
------------------
Total Days Checked: $totalDays
Days with Some Data Available: $availableDaysCount
Total 15-min Slots Checked: $totalHighrateSlotsChecked
15-min Slots with Data Available: $availableHighrateSlots
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

# Save TXT report
try {
    $reportContent | Out-File -FilePath $reportFileName -Encoding utf8 -ErrorAction Stop
    Write-Host "TXT report saved to: $reportFileName" -ForegroundColor Green
} catch {
    Write-Error "Failed to save TXT report file '$reportFileName': $($_.Exception.Message)"
}

# --- Display Summary ---
Write-Host "`nPGC CANADA GNSS Data Availability Check Completed" -ForegroundColor Green
Write-Host "Station: $($stationId.ToUpper()) | Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "Data Type: $dataType | RINEX Version: $rinexVersion" -ForegroundColor Cyan
Write-Host "Overall Availability: $overallPercentage%" -ForegroundColor Yellow
Write-Host "Results saved to: $outputDir" -ForegroundColor Magenta
Write-Host "Total execution time: $durationString" -ForegroundColor Gray
