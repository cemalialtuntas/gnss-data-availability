# CDDIS GNSS Data Availability Checker - Optimized Version
# This script checks availability of GNSS observation data from CDDIS FTP archives
# Parameters:
#   stationId - Station ID (e.g., BRST, MARS)
#   startDate - Start date in YYYY-MM-DD format
#   endDate - End date in YYYY-MM-DD format
#   dataType - Type of data (daily, hourly, highrate)
#   rinexVersion - RINEX version (2 or 3, where 3 also covers RINEX ver. 4)
#   maxConcurrent - Maximum number of concurrent operations (default: 10)

# Define parameters (user-configurable section)
param(
    [Parameter(Mandatory=$true)]
    [string]$stationId,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$startDate,
    
    [Parameter(Mandatory=$true)]
    [DateTime]$endDate,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet("daily", "hourly", "highrate")]
    [string]$dataType,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet(2, 3)]
    [int]$rinexVersion,
    
    [Parameter(Mandatory=$false)]
    [int]$maxConcurrent = 10
)

# Record start time
$startTime = Get-Date

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
    
    # Check if we already have this URL in cache
    if ($script:FtpCache.ContainsKey($ftpUrl)) {
        return $script:FtpCache[$ftpUrl]
    }
    
    $request = $null
    $response = $null
    $stream = $null
    $reader = $null
    $fileList = @()

    try {
        # Create FTP request
        $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
        $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $request.EnableSsl = $true
        $request.UsePassive = $true
        $request.UseBinary = $true
        $request.KeepAlive = $false
        $request.Timeout = 20000 # Reduced timeout for faster failure detection

        try {
            # Get response
            $response = $request.GetResponse()

            # Read directory listing
            $stream = $response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
            $directoryListing = $reader.ReadToEnd()

            # Parse the listing - optimized parsing
            $lines = $directoryListing -split "`n"
            foreach ($rawLine in $lines) {
                $line = $rawLine.Trim()
                if ($line) {
                    # Extract filename - the last word in the line
                    $parts = $line -split '\s+'
                    $fileName = $parts[-1]
                    if ($fileName -and $fileName -ne '.' -and $fileName -ne '..') {
                        $fileList += $fileName
                    }
                }
            }
            
            # Store in cache
            $script:FtpCache[$ftpUrl] = $fileList
            
            return $fileList
        }
        catch [System.Net.WebException] {
            $ftpResponse = $_.Exception.Response
            if ($ftpResponse -ne $null -and $ftpResponse -is [System.Net.FtpWebResponse]) {
                if ($ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable) {
                     # Cache empty results for not found directories
                     $script:FtpCache[$ftpUrl] = @()
                     return @()
                }
            }
            return $null
        }
        finally {
             if ($reader -ne $null) { try { $reader.Close() } catch {} }
             if ($stream -ne $null) { try { $stream.Close() } catch {} }
             if ($response -ne $null) { try { $response.Close() } catch {} }
        }
    }
    catch {
        return $null
    }
}

# Function to check file existence in listing (optimized)
function Test-FileExists {
    param (
        [array]$listing,
        [string]$pattern
    )
    
    if ($null -eq $listing) {
        return $false
    }
    
    foreach ($fileName in $listing) {
        if ($fileName -like $pattern) {
            return $true
        }
    }
    
    return $false
}

# Initialize results
$results = @()
$totalDays = ($endDate - $startDate).Days + 1

# Create output directory if it doesn't exist
$outputDir = ".\results\CDDIS\$stationId"
if (!(Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# Prepare list of dates to process
$datesToProcess = @()
$currentDate = $startDate
while ($currentDate -le $endDate) {
    $datesToProcess += $currentDate
    $currentDate = $currentDate.AddDays(1)
}

# Check if we can use PowerShell 7+ parallel processing
$canUseParallel = $PSVersionTable.PSVersion.Major -ge 7

if ($canUseParallel) {
    # Modern approach with PowerShell 7+ using ForEach-Object -Parallel
    Write-Host "Using PowerShell 7+ parallel processing" -ForegroundColor Green
    $results = $datesToProcess | ForEach-Object -ThrottleLimit $maxConcurrent -Parallel {
        $date = $_
        $stationId = $using:stationId
        $dataType = $using:dataType
        $rinexVersion = $using:rinexVersion
        
        # We need to redefine these functions in the parallel runspace
        function Get-DayOfYear {
            param (
                [DateTime]$date
            )
            return $date.DayOfYear.ToString("000")
        }
        
        function Test-FileExists {
            param (
                [array]$listing,
                [string]$pattern
            )
            
            if ($null -eq $listing) {
                return $false
            }
            
            foreach ($fileName in $listing) {
                if ($fileName -like $pattern) {
                    return $true
                }
            }
            
            return $false
        }
        
        function Get-FtpDirectoryListing {
            param (
                [string]$ftpUrl
            )
            
            # Access thread-safe dictionary from parent scope
            $ftpCache = $using:FtpCache
            
            # Check if we already have this URL in cache
            if ($ftpCache.ContainsKey($ftpUrl)) {
                return $ftpCache[$ftpUrl]
            }
            
            $request = $null
            $response = $null
            $stream = $null
            $reader = $null
            $fileList = @()

            try {
                # Create FTP request
                $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
                $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
                $request.EnableSsl = $true
                $request.UsePassive = $true
                $request.UseBinary = $true
                $request.KeepAlive = $false
                $request.Timeout = 20000

                try {
                    # Get response
                    $response = $request.GetResponse()
                    
                    # Read directory listing
                    $stream = $response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $directoryListing = $reader.ReadToEnd()

                    # Parse the listing
                    $lines = $directoryListing -split "`n"
                    foreach ($rawLine in $lines) {
                        $line = $rawLine.Trim()
                        if ($line) {
                            $parts = $line -split '\s+'
                            $fileName = $parts[-1]
                            if ($fileName -and $fileName -ne '.' -and $fileName -ne '..') {
                                $fileList += $fileName
                            }
                        }
                    }
                    
                    # Store in cache
                    $ftpCache[$ftpUrl] = $fileList
                    
                    return $fileList
                }
                catch [System.Net.WebException] {
                    $ftpResponse = $_.Exception.Response
                    if ($ftpResponse -ne $null -and $ftpResponse -is [System.Net.FtpWebResponse]) {
                        if ($ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable) {
                            # Cache empty results for not found directories
                            $ftpCache[$ftpUrl] = @()
                            return @()
                        }
                    }
                    return $null
                }
                finally {
                    if ($reader -ne $null) { try { $reader.Close() } catch {} }
                    if ($stream -ne $null) { try { $stream.Close() } catch {} }
                    if ($response -ne $null) { try { $response.Close() } catch {} }
                }
            }
            catch {
                return $null
            }
        }
        
        # Now process this date
        $year = $date.Year
        $shortYear = $date.ToString("yy")
        $doy = Get-DayOfYear -date $date
        
        $row = [ordered]@{
            "year" = $year
            "doy" = $doy
        }
        
        # Define file patterns based on RINEX version
        if ($rinexVersion -eq 2) {
            $fileNamePattern = $stationId.ToLower().Substring(0, 4) + "*$shortYear.d.gz"
        }
        else {
            $fileNamePattern = $stationId.ToUpper().Substring(0, 4) + "*crx.gz"
        }
        
        switch ($dataType) {
            "daily" {
                $baseUrl = "ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/daily/$year/$doy/${shortYear}d/"
                $listing = Get-FtpDirectoryListing -ftpUrl $baseUrl
                $isAvailable = Test-FileExists -listing $listing -pattern $fileNamePattern
                
                $row["dataAvailability"] = if ($isAvailable) { 1 } else { 0 }
            }
            
            "hourly" {
                $hourlyAvailability = 0
                
                # Try to get parent directory listing first
                $parentUrl = "ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/hourly/$year/$doy/"
                $hourDirs = Get-FtpDirectoryListing -ftpUrl $parentUrl
                
                # Process each hour
                for ($hour = 0; $hour -lt 24; $hour++) {
                    $hourStr = $hour.ToString("00")
                    
                    # Skip checking if hour directory doesn't exist
                    $hourExists = $hourDirs -contains $hourStr
                    $isAvailable = $false
                    
                    if ($hourExists) {
                        $baseUrl = "ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/hourly/$year/$doy/$hourStr/"
                        $listing = Get-FtpDirectoryListing -ftpUrl $baseUrl
                        $isAvailable = Test-FileExists -listing $listing -pattern $fileNamePattern
                    }
                    
                    $hourVal = if ($isAvailable) { 1 } else { 0 }
                    $row[$hourStr] = $hourVal
                    $hourlyAvailability += $hourVal
                }
                
                $row["percentage"] = [math]::Round(($hourlyAvailability / 24) * 100, 2)
            }
            
            "highrate" {
                $highrateAvailability = 0
                $maxPossibleFiles = 24 * 4 # 4 files per hour, 24 hours
                
                # Check if the parent day directory exists first
                $parentUrl = "ftp://gdc.cddis.eosdis.nasa.gov/highrate/$year/$doy/${shortYear}d/"
                $hourDirs = Get-FtpDirectoryListing -ftpUrl $parentUrl
                
                for ($hour = 0; $hour -lt 24; $hour++) {
                    $hourStr = $hour.ToString("00")
                    $filesInHour = 0
                    
                    # Skip checking if hour directory doesn't exist
                    $hourExists = $hourDirs -contains $hourStr
                    
                    if ($hourExists) {
                        $baseUrl = "ftp://gdc.cddis.eosdis.nasa.gov/highrate/$year/$doy/${shortYear}d/$hourStr/"
                        $listing = Get-FtpDirectoryListing -ftpUrl $baseUrl
                        
                        if ($listing -ne $null) {
                            foreach ($minute in @("00", "15", "30", "45")) {
                                if ($rinexVersion -eq 2) {
                                    $minutePattern = $stationId.ToLower().Substring(0, 4) + "*$minute*$shortYear.d.gz"
                                }
                                else {
                                    $minutePattern = $stationId.ToUpper().Substring(0, 4) + "*$minute*crx.gz"
                                }
                                
                                $isAvailable = Test-FileExists -listing $listing -pattern $minutePattern
                                
                                if ($isAvailable) {
                                    $filesInHour++
                                }
                            }
                        }
                    }
                    
                    $row[$hourStr] = $filesInHour
                    $highrateAvailability += $filesInHour
                }
                
                $row["percentage"] = [math]::Round(($highrateAvailability / $maxPossibleFiles) * 100, 2)
            }
        }
        
        return [PSCustomObject]$row
    }
} 
else {
    # Legacy approach using runspaces for PowerShell 5.1 and earlier
    Write-Host "Using legacy parallel processing for PowerShell 5.1" -ForegroundColor Yellow
    
    # Create runspace pool
    $runspacePool = [runspacefactory]::CreateRunspacePool(1, $maxConcurrent)
    $runspacePool.Open()
    
    # Create script block with all required functionality
    $scriptBlock = {
        param($date, $stationId, $dataType, $rinexVersion, $ftpCache)
        
        # Define required functions
        function Get-DayOfYear {
            param ( [DateTime]$date )
            return $date.DayOfYear.ToString("000")
        }
        
        function Test-FileExists {
            param ( [array]$listing, [string]$pattern )
            if ($null -eq $listing) { return $false }
            foreach ($fileName in $listing) {
                if ($fileName -like $pattern) { return $true }
            }
            return $false
        }
        
        function Get-FtpDirectoryListing {
            param ( [string]$ftpUrl )
            
            # Check if we already have this URL in cache
            if ($ftpCache.ContainsKey($ftpUrl)) {
                return $ftpCache[$ftpUrl]
            }
            
            try {
                $request = [System.Net.FtpWebRequest]::Create($ftpUrl)
                $request.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
                $request.EnableSsl = $true
                $request.UsePassive = $true
                $request.UseBinary = $true
                $request.KeepAlive = $false
                $request.Timeout = 20000
                
                try {
                    $response = $request.GetResponse()
                    $stream = $response.GetResponseStream()
                    $reader = New-Object System.IO.StreamReader($stream, [System.Text.Encoding]::UTF8)
                    $directoryListing = $reader.ReadToEnd()
                    
                    $fileList = @()
                    $lines = $directoryListing -split "`n"
                    foreach ($rawLine in $lines) {
                        $line = $rawLine.Trim()
                        if ($line) {
                            $parts = $line -split '\s+'
                            $fileName = $parts[-1]
                            if ($fileName -and $fileName -ne '.' -and $fileName -ne '..') {
                                $fileList += $fileName
                            }
                        }
                    }
                    
                    # Store in cache
                    $ftpCache[$ftpUrl] = $fileList
                    
                    return $fileList
                }
                catch [System.Net.WebException] {
                    $ftpResponse = $_.Exception.Response
                    if ($ftpResponse -ne $null -and $ftpResponse -is [System.Net.FtpWebResponse]) {
                        if ($ftpResponse.StatusCode -eq [System.Net.FtpStatusCode]::ActionNotTakenFileUnavailable) {
                            # Cache empty results for not found directories
                            $ftpCache[$ftpUrl] = @()
                            return @()
                        }
                    }
                    return $null
                }
                finally {
                    if ($reader -ne $null) { try { $reader.Close() } catch {} }
                    if ($stream -ne $null) { try { $stream.Close() } catch {} }
                    if ($response -ne $null) { try { $response.Close() } catch {} }
                }
            }
            catch {
                return $null
            }
        }
        
        # Process the date
        $year = $date.Year
        $shortYear = $date.ToString("yy")
        $doy = Get-DayOfYear -date $date
        
        $row = [ordered]@{
            "year" = $year
            "doy" = $doy
        }
        
        # Define file patterns based on RINEX version
        if ($rinexVersion -eq 2) {
            $fileNamePattern = $stationId.ToLower().Substring(0, 4) + "*$shortYear.d.gz"
        }
        else {
            $fileNamePattern = $stationId.ToUpper().Substring(0, 4) + "*crx.gz"
        }
        
        switch ($dataType) {
            "daily" {
                $baseUrl = "ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/daily/$year/$doy/${shortYear}d/"
                $listing = Get-FtpDirectoryListing -ftpUrl $baseUrl
                $isAvailable = Test-FileExists -listing $listing -pattern $fileNamePattern
                
                $row["dataAvailability"] = if ($isAvailable) { 1 } else { 0 }
            }
            
            "hourly" {
                $hourlyAvailability = 0
                
                # Try to get parent directory listing first
                $parentUrl = "ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/hourly/$year/$doy/"
                $hourDirs = Get-FtpDirectoryListing -ftpUrl $parentUrl
                
                for ($hour = 0; $hour -lt 24; $hour++) {
                    $hourStr = $hour.ToString("00")
                    
                    # Skip checking if hour directory doesn't exist
                    $hourExists = $hourDirs -contains $hourStr
                    $isAvailable = $false
                    
                    if ($hourExists) {
                        $baseUrl = "ftp://gdc.cddis.eosdis.nasa.gov/gnss/data/hourly/$year/$doy/$hourStr/"
                        $listing = Get-FtpDirectoryListing -ftpUrl $baseUrl
                        $isAvailable = Test-FileExists -listing $listing -pattern $fileNamePattern
                    }
                    
                    $hourVal = if ($isAvailable) { 1 } else { 0 }
                    $row[$hourStr] = $hourVal
                    $hourlyAvailability += $hourVal
                }
                
                $row["percentage"] = [math]::Round(($hourlyAvailability / 24) * 100, 2)
            }
            
            "highrate" {
                $highrateAvailability = 0
                $maxPossibleFiles = 24 * 4 # 4 files per hour, 24 hours
                
                # Check if the parent day directory exists first
                $parentUrl = "ftp://gdc.cddis.eosdis.nasa.gov/highrate/$year/$doy/${shortYear}d/"
                $hourDirs = Get-FtpDirectoryListing -ftpUrl $parentUrl
                
                for ($hour = 0; $hour -lt 24; $hour++) {
                    $hourStr = $hour.ToString("00")
                    $filesInHour = 0
                    
                    # Skip checking if hour directory doesn't exist
                    $hourExists = $hourDirs -contains $hourStr
                    
                    if ($hourExists) {
                        $baseUrl = "ftp://gdc.cddis.eosdis.nasa.gov/highrate/$year/$doy/${shortYear}d/$hourStr/"
                        $listing = Get-FtpDirectoryListing -ftpUrl $baseUrl
                        
                        if ($listing -ne $null) {
                            foreach ($minute in @("00", "15", "30", "45")) {
                                if ($rinexVersion -eq 2) {
                                    $minutePattern = $stationId.ToLower().Substring(0, 4) + "*$minute*$shortYear.d.gz"
                                }
                                else {
                                    $minutePattern = $stationId.ToUpper().Substring(0, 4) + "*$minute*crx.gz"
                                }
                                
                                $isAvailable = Test-FileExists -listing $listing -pattern $minutePattern
                                
                                if ($isAvailable) {
                                    $filesInHour++
                                }
                            }
                        }
                    }
                    
                    $row[$hourStr] = $filesInHour
                    $highrateAvailability += $filesInHour
                }
                
                $row["percentage"] = [math]::Round(($highrateAvailability / $maxPossibleFiles) * 100, 2)
            }
        }
        
        return [PSCustomObject]$row
    }
    
    # Start all jobs
    $jobs = @()
    $processedDays = 0
    
    foreach ($date in $datesToProcess) {
        $processedDays++
        $percentComplete = [math]::Round(($processedDays / $totalDays) * 100)
        Write-Progress -Activity "Starting Jobs" -Status "Queuing Date: $($date.ToString('yyyy-MM-dd')) ($processedDays/$totalDays)" -PercentComplete $percentComplete
        
        $powershell = [powershell]::Create().AddScript($scriptBlock).AddArgument($date).AddArgument($stationId).AddArgument($dataType).AddArgument($rinexVersion).AddArgument($script:FtpCache)
        $powershell.RunspacePool = $runspacePool
        
        $job = @{
            Pipe = $powershell
            Result = $powershell.BeginInvoke()
        }
        
        $jobs += $job
    }
    
    # Collect results
    $processedDays = 0
    foreach ($job in $jobs) {
        $processedDays++
        $percentComplete = [math]::Round(($processedDays / $totalDays) * 100)
        Write-Progress -Activity "Processing Results" -Status "Collecting Results: $processedDays/$totalDays" -PercentComplete $percentComplete
        
        $results += $job.Pipe.EndInvoke($job.Result)
        $job.Pipe.Dispose()
    }
    
    # Clean up
    $runspacePool.Close()
    $runspacePool.Dispose()
}

# Sort results by year and DOY
$results = $results | Sort-Object -Property year, doy

# Calculate overall statistics
$availableDaysCount = 0
$totalHoursChecked = 0
$availableHoursCount = 0
$totalHighrateSlots = 0
$availableHighrateSlots = 0

foreach ($row in $results) {
    switch ($dataType) {
        "daily" {
            if ($row.dataAvailability -eq 1) {
                $availableDaysCount++
            }
        }
        "hourly" {
            $hourlyAvailability = 0
            for ($hour = 0; $hour -lt 24; $hour++) {
                $hourStr = $hour.ToString("00")
                $hourlyAvailability += $row.$hourStr
                $totalHoursChecked++
                if ($row.$hourStr -eq 1) {
                    $availableHoursCount++
                }
            }
            if ($hourlyAvailability -gt 0) {
                $availableDaysCount++
            }
        }
        "highrate" {
            $highrateAvailability = 0
            for ($hour = 0; $hour -lt 24; $hour++) {
                $hourStr = $hour.ToString("00")
                $highrateAvailability += $row.$hourStr
                $totalHighrateSlots += 4 # 4 slots per hour
                $availableHighrateSlots += $row.$hourStr
            }
            if ($highrateAvailability -gt 0) {
                $availableDaysCount++
            }
        }
    }
}

# Calculate overall percentage
$overallPercentage = 0
switch ($dataType) {
    "daily" {
        $overallPercentage = [math]::Round(($availableDaysCount / $totalDays) * 100, 2)
    }
    "hourly" {
        $overallPercentage = [math]::Round(($availableHoursCount / $totalHoursChecked) * 100, 2)
    }
    "highrate" {
        $overallPercentage = [math]::Round(($availableHighrateSlots / $totalHighrateSlots) * 100, 2)
    }
}

# Export CSV results
$csvFileName = "$outputDir\${stationId}_${dataType}_${rinexVersion}_$($startDate.ToString('yyyyMMdd'))_$($endDate.ToString('yyyyMMdd')).csv"

if ($canUseParallel) { # PS 7+ has -UseQuotes
    $results | Export-Csv -Path $csvFileName -NoTypeInformation -UseQuotes Never
} else { # PS 5.1 workaround
    # Convert to CSV strings in memory
    $csvContent = $results | ConvertTo-Csv -NoTypeInformation
    # Remove quotes
    $csvContentWithoutQuotes = $csvContent | ForEach-Object { $_ -replace '"', '' }
    # Save to file
    $csvContentWithoutQuotes | Out-File -FilePath $csvFileName -Encoding utf8
}

# Generate report
$reportFileName = "$outputDir\${stationId}_${dataType}_${rinexVersion}_$($startDate.ToString('yyyyMMdd'))_$($endDate.ToString('yyyyMMdd')).txt"
$reportContent = @"
CDDIS GNSS Data Availability Report
==================================
Station ID: $stationId
Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))
Data Type: $dataType
RINEX Version: $rinexVersion

Summary Statistics:
------------------
Total Days Checked: $totalDays
Days with Some Data Available: $availableDaysCount
"@

switch ($dataType) {
    "daily" {
        $reportContent += @"

Overall Data Availability: $overallPercentage%
"@
    }
    "hourly" {
        $reportContent += @"

Total Hours Checked: $totalHoursChecked
Hours with Data Available: $availableHoursCount
Overall Data Availability: $overallPercentage%
"@
    }
    "highrate" {
        $reportContent += @"

Total 15-min Slots Checked: $totalHighrateSlots
15-min Slots with Data Available: $availableHighrateSlots
Overall Data Availability: $overallPercentage%
"@
    }
}

$reportContent | Out-File -FilePath $reportFileName -Encoding utf8

# Calculate and display total execution time
$endTime = Get-Date
$duration = $endTime - $startTime
$durationString = "{0:hh\:mm\:ss\.fff}" -f $duration

# Display summary to console
Write-Host "CDDIS GNSS Data Availability Check Completed" -ForegroundColor Green
Write-Host "Station: $stationId | Date Range: $($startDate.ToString('yyyy-MM-dd')) to $($endDate.ToString('yyyy-MM-dd'))" -ForegroundColor Cyan
Write-Host "Data Type: $dataType | RINEX Version: $rinexVersion" -ForegroundColor Cyan
Write-Host "Overall Availability: $overallPercentage%" -ForegroundColor Yellow
Write-Host "Results saved to: $outputDir" -ForegroundColor Magenta
Write-Host "Total execution time: $durationString" -ForegroundColor Gray