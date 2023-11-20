# Black Duck Metrics Powershell Script
# Recommended Invocation: powershell "irm https://github.com/blackducksoftware/blackduck-metrics/raw/main/blackduck-metrics.ps1?$(Get-Random) | iex; bd-metrics"
$ProgressPreference = 'SilentlyContinue'
function Get-EnvironmentVariable($Key, $DefaultValue) { if (-not (Test-Path Env:$Key)) { return $DefaultValue; }else { return (Get-ChildItem Env:$Key).Value; } }

# To override the default version key, specify a
# different METRICS_VERSION_KEY in your environment and
# *that* key will be used to get the download url from
# artifactory. These METRICS_VERSION_KEY values are
# properties that resolve to download
# urls for the metrics jar file.
#
# Every new version of metrics will have its own
# key.
$EnvMetricsVersionKey = Get-EnvironmentVariable -Key "METRICS_VERSION_KEY" -DefaultValue "LATEST";

# If you want to skip the test for java
# METRICS_SKIP_JAVA_TEST=1
$EnvMetricsSkipJavaTest = Get-EnvironmentVariable -Key "METRICS_SKIP_JAVA_TEST" -DefaultValue "";

# You can specify your own download url from
# artifactory which can bypass using the property keys
# (this is mainly for QA purposes only)
$EnvMetricsSource = Get-EnvironmentVariable -Key "METRICS_SOURCE" -DefaultValue "";

# To override the default location of /tmp, specify
# your own METRICS_JAR_DOWNLOAD_DIR in your environment and
# *that* location will be used.
# *NOTE* We currently do not support spaces in the
# METRICS_JAR_DOWNLOAD_DIR.
# Otherwise, if the environment temp folder is set,
# it will be used. Otherwise, a temporary folder will
# be created in your home directory
$EnvMetricsFolder = Get-EnvironmentVariable -Key "METRICS_JAR_DOWNLOAD_DIR" -DefaultValue "";
if ([string]::IsNullOrEmpty($EnvMetricsFolder)) {
	# Try again using old name for backward compatibility
	$EnvMetricsFolder = Get-EnvironmentVariable -Key "METRICS_JAR_PATH" -DefaultValue "";
}

$EnvTempFolder = Get-EnvironmentVariable -Key "TMP" -DefaultValue "";
$EnvHomeTempFolder = "$HOME/tmp"


# If you do not want to exit with the Metrics exit
# code, set METRICS_EXIT_CODE_PASSTHRU to 1 and this
# script won't exit, but simply return it (pass it thru).
$EnvMetricsExitCodePassthru = Get-EnvironmentVariable -Key "METRICS_EXIT_CODE_PASSTHRU" -DefaultValue "";

# To control which java Metrics will use to run, specify
# the path in in METRICS_JAVA_PATH or JAVA_HOME in your
# environment, or ensure that java is first on the path.
# METRICS_JAVA_PATH will take precedence over JAVA_HOME.
# JAVA_HOME will take precedence over the path.
# Note: METRICS_JAVA_PATH should point directly to the
# java executable. For JAVA_HOME the java executable is
# expected to be in JAVA_HOME/bin/java
$MetricsJavaPath = Get-EnvironmentVariable -Key "METRICS_JAVA_PATH" -DefaultValue "";
$JavaHome = Get-EnvironmentVariable -Key "JAVA_HOME" -DefaultValue "";

# If you only want to download the appropriate jar file set
# this to 1 in your environment. This can be useful if you
# want to invoke the jar yourself but do not want to also
# get and update the jar file when a new version releases.
$DownloadOnly = Get-EnvironmentVariable -Key "METRICS_DOWNLOAD_ONLY" -DefaultValue "";

# TODO: Mirror the functionality of the shell script
# and allow Java opts.

# If you want to pass any java options to the
# invocation, specify METRICS_JAVA_OPTS in your
# environment. For example, to specify a 6 gigabyte
# heap size, you would set METRICS_JAVA_OPTS=-Xmx6G.
# $MetricsJavaOpts = Get-EnvironmentVariable -Key "METRICS_JAVA_OPTS" -DefaultValue "";

$Version = "2"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 #Enable TLS2

function Metrics {
    Write-Host "Black Duck Metrics Powershell Script $Version"

    if ($EnvMetricsSkipJavaTest -ne "1") {
        if (Test-JavaNotAvailable) {
            #If java is not available, we abort early.
            $JavaExitCode = 127 #Command not found http://tldp.org/LDP/abs/html/exitcodes.html
            if ($EnvMetricsExitCodePassthru -eq "1") {
                return $JavaExitCode
            }
            else {
                exit $JavaExitCode
            }
        }
    }
    else {
        Write-Host "Skipping java test."
    }

    $LocalJar = Get-Local-Jar
    if ($LocalJar) {
        Write-Host "Using Local Black Duck Metrics Jar $LocalJar"
        $MetricsJarFile = $LocalJar
    } else {
        Write-Host "Initializing Black Duck Metrics folder."
        $MetricsFolder = Initialize-MetricsFolder -MetricsFolder $EnvMetricsFolder -TempFolder $EnvTempFolder -HomeTempFolder $EnvHomeTempFolder

        Write-Host "Checking for proxy."
        $ProxyInfo = Get-ProxyInfo

        Write-Host "Getting Black Duck Metrics."
        $MetricsJarFile = Get-MetricsJar -MetricsFolder $MetricsFolder -MetricsSource $EnvMetricsSource -MetricsVersionKey $EnvMetricsVersionKey -ProxyInfo $ProxyInfo

    }
    if ($DownloadOnly -ne "1") {
        Write-Host "Executing Black Duck Metrics."
        $MetricsArgs = $args;
        $MetricsExitCode = Invoke-Metrics -MetricsJar $MetricsJarFile -MetricsArgs $MetricsArgs

        if ($EnvMetricsExitCodePassthru -eq "1") {
            return $MetricsExitCode
        } else {
            exit $MetricsExitCode
        }
    }
}

function Get-Local-Jar() {
    $Values = Get-ChildItem blackduck-metrics-*-jar-with-dependencies.jar -Name
    Write-Host $Values
    foreach ($Value in $Values) {
        Write-Host $Value
        return $Value;
    }
    return $null;
}

function Get-FirstFromEnv($Names) {
    foreach ($Name in $Names) {
        $Value = Get-EnvironmentVariable -Key $Name -Default $null;
        if (-Not [string]::IsNullOrEmpty($Value)) {
            return $Value;
        }
    }
    return $null;
}

function Get-ProxyInfo () {
    $ProxyInfoProperties = @{
        'Uri'         = $null
        'Credentials' = $null
    }

    try {

        $ProxyHost = Get-FirstFromEnv @("blackduck.proxy.host", "BLACKDUCK_PROXY_HOST", "blackduck.hub.proxy.host", "BLACKDUCK_HUB_PROXY_HOST");

        if ([string]::IsNullOrEmpty($ProxyHost)) {
            Write-Host "Skipping proxy, no host found."
        }
        else {
            Write-Host "Found proxy host."
            $ProxyUrlBuilder = New-Object System.UriBuilder -ArgumentList $ProxyHost

            $ProxyPort = Get-FirstFromEnv @("blackduck.proxy.port", "BLACKDUCK_PROXY_PORT", "blackduck.hub.proxy.port", "BLACKDUCK_HUB_PROXY_PORT");

            if ([string]::IsNullOrEmpty($ProxyPort)) {
                Write-Host "No proxy port found."
            }
            else {
                Write-Host "Found proxy port."
                $ProxyUrlBuilder.Port = $ProxyPort
            }

            $ProxyInfoProperties.Uri = $ProxyUrlBuilder.Uri

            #Handle credentials
            $ProxyUsername = Get-FirstFromEnv @("blackduck.proxy.username", "BLACKDUCK_PROXY_USERNAME", "blackduck.hub.proxy.username", "BLACKDUCK_HUB_PROXY_USERNAME");
            $ProxyPassword = Get-FirstFromEnv @("blackduck.proxy.password", "BLACKDUCK_PROXY_PASSWORD", "blackduck.hub.proxy.password", "BLACKDUCK_HUB_PROXY_PASSWORD");

            if ([string]::IsNullOrEmpty($ProxyPassword) -or [string]::IsNullOrEmpty($ProxyUsername)) {
                Write-Host "No proxy credentials found."
            }
            else {
                Write-Host "Found proxy credentials."
                $ProxySecurePassword = ConvertTo-SecureString $ProxyPassword -AsPlainText -Force
                $ProxyCredentials = New-Object System.Management.Automation.PSCredential ($ProxyUsername, $ProxySecurePassword)

                $ProxyInfoProperties.Credentials = $ProxyCredentials;
            }

            Write-Host "Proxy has been configured."
        }

    }
    catch [Exception] {
        Write-Host ("An exception occurred setting up the proxy, will continue but will not use a proxy.")
        Write-Host ("  Reason: {0}" -f $_.Exception.GetType().FullName);
        Write-Host ("  Reason: {0}" -f $_.Exception.Message);
        Write-Host ("  Reason: {0}" -f $_.Exception.StackTrace);
    }

    $ProxyInfo = New-Object -TypeName PSObject -Prop $ProxyInfoProperties

    return $ProxyInfo;
}

function Invoke-WebRequestWrapper($Url, $ProxyInfo, $DownloadLocation = $null) {
    $parameters = @{}
    try {
        if ($DownloadLocation -ne $null) {
            $parameters.Add("OutFile", $DownloadLocation);
        }
        if ($ProxyInfo -ne $null) {
            if ($ProxyInfo.Uri -ne $null) {
                $parameters.Add("Proxy", $ProxyInfo.Uri);
            }
            if ($ProxyInfo.Credentials -ne $null) {
                $parameters.Add("ProxyCredential", $ProxyInfo.Credentials);
            }
        }
    }
    catch [Exception] {
        Write-Host ("An exception occurred setting additional properties on web request.")
        Write-Host ("  Reason: {0}" -f $_.Exception.GetType().FullName);
        Write-Host ("  Reason: {0}" -f $_.Exception.Message);
        Write-Host ("  Reason: {0}" -f $_.Exception.StackTrace);
    }

    return Invoke-WebRequest $Url -UseBasicParsing @parameters -UserAgent "PowerShell" # Workaround for https://www.jfrog.com/jira/si/jira.issueviews:issue-html/RTFACT-26216/RTFACT-26216.html
}

function Get-MetricsJar ($MetricsFolder, $MetricsSource, $MetricsVersionKey, $ProxyInfo) {
    $LastDownloadFile = "$MetricsFolder/blackduck-metrics-last-downloaded-jar.txt"

    $MetricsVersionUrl = "https://raw.githubusercontent.com/blackducksoftware/blackduck-metrics/main/blackduck-metrics-properties.txt"
    $MetricsSource = Receive-MetricsSource -ProxyInfo $ProxyInfo -MetricsVersionUrl $MetricsVersionUrl -MetricsVersionKey $MetricsVersionKey

    if ($MetricsSource) {
        Write-Host "Using Black Duck Metrics source '$MetricsSource'"

        $MetricsFileName = Parse-Metrics-File-Name -MetricsSource $MetricsSource

        $MetricsJarFile = "$MetricsFolder/$MetricsFileName"
    } else {
        Write-Host "Unable to find Black Duck Metrics Source, will attempt to find a last downloaded jar."

        $LastDownloadFileExists = Test-Path $LastDownloadFile
        Write-Host "Last download exists '$LastDownloadFileExists'"

        if ($LastDownloadFileExists) {
            $MetricsJarFile = Get-Content -Path $LastDownloadFile
            Write-Host "Using last downloaded Black Duck Metrics '$MetricsJarFile'"
        } else {
            Write-Host "Unable to determine Black Duck Metrics version and no downloaded jar found."
            exit -1
        }
    }


    $MetricsJarExists = Test-Path $MetricsJarFile
    Write-Host "Black Duck Metrics jar exists '$MetricsJarExists'"

    if (!$MetricsJarExists) {
        Receive-MetricsJar -MetricsUrl $MetricsSource -MetricsJarFile $MetricsJarFile -ProxyInfo $ProxyInfo -LastDownloadFile $LastDownloadFile
    } else {
        Write-Host "You have already downloaded the latest file, so the local file will be used."
    }

    return $MetricsJarFile
}

function Parse-Metrics-File-Name($MetricsSource) {
    $SlashParts = $MetricsSource.Split("/")
    $LastPart = $SlashParts[$SlashParts.Length - 1]
    return $LastPart
}

function Invoke-Metrics ($MetricsJarFile, $MetricsArgs) {
    $JavaArgs = @("-jar", $MetricsJarFile)
    $AllArgs = $JavaArgs + $MetricsArgs
    Set-ToEscaped($AllArgs)
    Write-Host "Running Black Duck Metrics: $AllArgs"
    $JavaCommand = Determine-Java($JavaHome, $MetricsJavaPath)
    $MetricsProcess = Start-Process $JavaCommand -ArgumentList $AllArgs -NoNewWindow -PassThru
    Wait-Process -InputObject $MetricsProcess -ErrorAction SilentlyContinue
    $MetricsExitCode = $MetricsProcess.ExitCode;
    Write-Host "Result code of $MetricsExitCode, exiting"
    return $MetricsExitCode
}

function Determine-Java ($EnvJavaHome, $EnvMetricsJavaPath) {
    $JavaCommand = "java"
    if ($MetricsJavaPath -ne "") {
        $JavaCommand = $MetricsJavaPath
        Write-Host "Java Source: Metrics_JAVA_PATH=$JavaCommand"
    } elseif ($JavaHome -ne "") {
        $JavaCommand = "$JavaHome/bin/java"
        Write-Host "Java Source: JAVA_HOME/bin/java=$JavaCommand"
    } else {
        Write-Host "Java Source: PATH"
    }

    return $JavaCommand
}

function Initialize-MetricsFolder ($MetricsFolder, $TempFolder, $HomeTempFolder) {
    if ($MetricsFolder -ne "") {
        Write-Host "Using supplied Black Duck Metrics folder: $MetricsFolder"
        return Initialize-Folder -Folder $MetricsFolder
    }

    if ($TempFolder -ne "") {
        Write-Host "Using system temp folder: $TempFolder"
        return Initialize-Folder -Folder $TempFolder
    }

    return Initialize-Folder -Folder $HomeTempFolder
}

function Initialize-Folder ($Folder) {
    If (!(Test-Path $Folder)) {
        Write-Host "Created folder: $Folder"
        New-Item -ItemType Directory -Force -Path $Folder | Out-Null #Pipe to Out-Null to prevent dirtying to the function output
    }
    return $Folder
}

function Receive-MetricsSource ($ProxyInfo, $MetricsVersionUrl, $MetricsVersionKey) {
    Write-Host "Finding latest Black Duck Metrics version."
    $MetricsVersionData = Invoke-WebRequestWrapper -Url $MetricsVersionUrl -ProxyInfo $ProxyInfo
    if (!$MetricsVersionData){
        Write-Host "Failed to get Black Duck Metrics version"
        return $null
    }

    $MetricsVersionJson = ConvertFrom-Json -InputObject $MetricsVersionData

    $Properties = $MetricsVersionJson | select -ExpandProperty "properties"
    $MetricsVersionUrl = $Properties | select -ExpandProperty $MetricsVersionKey
    return $MetricsVersionUrl
}

function Receive-MetricsJar ($MetricsUrl, $MetricsJarFile, $LastDownloadFile, $ProxyInfo) {
    Write-Host "You don't have Black Duck Metrics. Downloading now."
    Write-Host "Using url $MetricsUrl"
    $MetricsJarTempFile = "$MetricsJarFile.tmp"
    $Request = Invoke-WebRequestWrapper -Url $MetricsUrl -DownloadLocation $MetricsJarTempFile -ProxyInfo $ProxyInfo
    Rename-Item -Path $MetricsJarTempFile -NewName $MetricsJarFile
    $MetricsJarExists = Test-Path $MetricsJarFile
    Write-Host "Downloaded Black Duck Metrics jar successfully '$MetricsJarExists'"
    Set-Content -Value $MetricsJarFile -Path $LastDownloadFile
}

function Set-ToEscaped ($ArgArray) {
    for ($i = 0; $i -lt $ArgArray.Count ; $i++) {
        $Value = $ArgArray[$i]
        $ArgArray[$i] = """$Value"""
    }
}

function Test-JavaNotAvailable() {
    Write-Host "Checking if Java is installed by asking for version."
    try {
        $ProcessStartInfo = New-object System.Diagnostics.ProcessStartInfo
        $ProcessStartInfo.CreateNoWindow = $true
        $ProcessStartInfo.UseShellExecute = $false
        $ProcessStartInfo.RedirectStandardOutput = $true
        $ProcessStartInfo.RedirectStandardError = $true
        $ProcessStartInfo.FileName = Determine-Java($JavaHome, $MetricsJavaPath)
        $ProcessStartInfo.Arguments = @("-version")
        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessStartInfo
        [void]$Process.Start()
        $StdOutput = $process.StandardOutput.ReadToEnd()
        $StdError = $process.StandardError.ReadToEnd()
        $Process.WaitForExit()
        Write-Host "Java Standard Output: $StdOutput"
        Write-Host "Java Error Output: $StdError"
        Write-Host "Successfully able to start java and get version."
        return $FALSE;
    }
    catch {
        Write-Host "An error occurred checking the Java version. Please ensure Java is installed."
        return $TRUE;
    }
}
