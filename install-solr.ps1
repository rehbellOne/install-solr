# Credit primarily to jermdavis for the original script

Param(
	[string]$hostsPath = "$env:windir\System32\drivers\etc\hosts",
	
	[string]$solrRoot = 'C:\SOLR',
    [string]$solrProjectName = "############SOLUTIONPREFIX###########",
	[string]$solrVersion = "########VERSION#########",	

    [string]$solrHost = "local-solr.#######WEBSITE########.com",
	[string]$solrIp = "127.0.0.1",
	[string]$solrPort = "#####PORTNUMBER#####",
    [bool]$solrSSL = $TRUE,

	[string]$nssmRoot = "C:\NSSM",
    [string]$nssmVersion = "2.24",    
	[string]$keystorePrefix = "solr-ssl",
	
    [string]$JavaInstallPath = 'C:\Java\JRE',
	[switch]$Clobber
)

$solrServiceName = "SOLR-$solrProjectName-$solrVersion"
$keystoreName = "$keystorePrefix.keystore"
$KeystoreFile = "$keystoreName.jks"
$P12File = "$keystoreName.p12"
$keystoreSecret = "secret"

$solrDestinationPath = "$solrRoot\$solrProjectName\$solrVersion"
$nssmDestinationPath = "$nssmRoot\$nssmVersion"

$solrPackage = "http://archive.apache.org/dist/lucene/solr/$solrVersion/solr-$solrVersion.zip"
$nssmPackage = "http://nssm.cc/release/nssm-$nssmVersion.zip"
$downloadFolder =(Resolve-Path "\")

## Verify elevated
## https://superuser.com/questions/749243/detect-if-powershell-is-running-as-administrator
$elevated = [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544")
if(!($elevated))
{
    throw "In order to install services, please run this script elevated."
}


$JavaMinVersionRequired = "8.0.1510"

if (Get-Module("helper")) {
	Remove-Module "helper"
}
Import-Module "$PSScriptRoot\helper.psm1"  

## HOSTS ENTRY
Write-Host "Checking for Host Entry matching " $solrHost

if ((Get-Content "$hostsPath" ) -notcontains "$solrHost")
 {
	Write-Host "Host Entry was not found. Adding one ..."
	ac -Encoding UTF8  "$hostsPath" "$solrIp	$solrHost" 
 }
 else
 { 
	Write-Host "Host Entry found."
 }


$ErrorActionPreference = 'Stop'

# Ensure Java environment variable
try {
	$keytool = (Get-Command 'keytool.exe').Source
} catch {
	$keytool = Get-JavaKeytool -JavaMinVersionRequired $JavaMinVersionRequired
}

### GET SOLR
$solrZipName = "solr-$solrVersion"
downloadAndUnzipIfRequired $solrRoot $solrZipName $solrPackage $solrDestinationPath

### GET NSSM
$nssmZipName = "nssm-$nssmVersion"
downloadAndUnzipIfRequired $nssmRoot $nssmZipName $nssmPackage $nssmDestinationPath

### PARAM VALIDATION
if($keystoreSecret -ne 'secret') {
	Write-Error 'The keystore password must be "secret", because Solr apparently ignores the parameter'
}

if((Test-Path $KeystoreFile)) {
	if($Clobber) {
		Write-Host "Removing $KeystoreFile..."
		Remove-Item $KeystoreFile
	} else {
		$KeystorePath = Resolve-Path $KeystoreFile
		Write-Error "Keystore file $KeystorePath already existed. To regenerate it, pass -Clobber."
	}
}

$P12Path = [IO.Path]::ChangeExtension($KeystoreFile, 'p12')
if((Test-Path $P12Path)) {
	if($Clobber) {
		Write-Host "Removing $P12Path..."
		Remove-Item $P12Path
	} else {
		$P12Path = Resolve-Path $P12Path
		Write-Error "Keystore file $P12Path already existed. To regenerate it, pass -Clobber."
	}
}

### DOING STUFF

Write-Host ''
Write-Host 'Generating JKS keystore...'
& $keytool -genkeypair -alias $keystorePrefix -keyalg RSA -keysize 2048 -keypass $keystoreSecret -storepass $keystoreSecret -validity 9999 -keystore $KeystoreFile -ext SAN=DNS:$solrHost,IP:$solrIp -dname "CN=$solrHost, OU=Organizational Unit, O=Organization, L=Location, ST=State, C=Country"

Write-Host ''
Write-Host 'Generating .p12 to import to Windows...'
& $keytool -importkeystore -srckeystore $KeystoreFile -destkeystore $P12Path -srcstoretype jks -deststoretype pkcs12 -srcstorepass $keystoreSecret -deststorepass $keystoreSecret

Write-Host ''
Write-Host 'Trusting generated SSL certificate...'
$secureStringKeystorePassword = ConvertTo-SecureString -String $keystoreSecret -Force -AsPlainText
$root = Import-PfxCertificate -FilePath $P12Path -Password $secureStringKeystorePassword -CertStoreLocation Cert:\LocalMachine\Root
Write-Host 'SSL certificate is now locally trusted. (added as root CA)'

if(-not $KeystoreFile.EndsWith('solr-ssl.keystore.jks')) {
	Write-Warning 'Your keystore file is not named "solr-ssl.keystore.jks"'
	Write-Warning 'Good for you.'
}

$KeystorePath = Resolve-Path $KeystoreFile
Move-Item $KeystorePath -Destination "$solrDestinationPath\server\etc\$keystoreName.jks" -Force

$P12Path = Resolve-Path $P12File
Move-Item $P12Path -Destination "$solrDestinationPath\server\etc\$keystoreName.p12" -Force

 # Update solr cfg to use keystore & right host name
 if(Test-Path -Path "$solrDestinationPath\bin\solr.in.cmd.old")
 {
		 Write-Host "Resetting solr.in.cmd" -ForegroundColor Green
		 Remove-Item "$solrDestinationPath\bin\solr.in.cmd"
		 Rename-Item -Path "$solrDestinationPath\bin\solr.in.cmd.old" -NewName "$solrDestinationPath\bin\solr.in.cmd"   
 }

	 Write-Host "Rewriting solr config"

	 $cfg = Get-Content "$solrDestinationPath\bin\solr.in.cmd"
	 Rename-Item "$solrDestinationPath\bin\solr.in.cmd" "$solrDestinationPath\bin\solr.in.cmd.old"
	 $certStorePath = "etc/$keystorePrefix.keystore.jks"
	 $newCfg = $cfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_ENABLED=true", "set SOLR_SSL_ENABLED=true" }	 
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_PORT=8983", "set SOLR_PORT=$solrPort" }	 
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_KEY_STORE=etc/solr-ssl.keystore.jks", "set SOLR_SSL_KEY_STORE=$certStorePath" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_KEY_STORE_PASSWORD=secret", "set SOLR_SSL_KEY_STORE_PASSWORD=$keystoreSecret" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_KEY_STORE_TYPE=JKS", "set SOLR_SSL_KEY_STORE_TYPE=JKS" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_TRUST_STORE=etc/solr-ssl.keystore.jks", "set SOLR_SSL_TRUST_STORE=$certStorePath" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_TRUST_STORE_PASSWORD=secret", "set SOLR_SSL_TRUST_STORE_PASSWORD=$keystoreSecret" }	 
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_TRUST_STORE_TYPE=JKS", "set SOLR_SSL_TRUST_STORE_TYPE=JKS" }
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_NEED_CLIENT_AUTH=false", "set SOLR_SSL_NEED_CLIENT_AUTH=false" }
	 #$newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_SSL_WANT_CLIENT_AUTH=false", "set SOLR_SSL_WANT_CLIENT_AUTH=false" }	 
	 $newCfg = $newCfg | ForEach-Object { $_ -replace "REM set SOLR_HOST=192.168.1.1", "set SOLR_HOST=$solrHost" }
	 $newCfg | Set-Content "$solrDestinationPath\bin\solr.in.cmd"


# install the service & runs

$svc = Get-Service "$solrServiceName" -ErrorAction SilentlyContinue
if(!($svc))
{
    Write-Host "Installing Solr service"
    &"$nssmRoot\nssm-$nssmVersion\win64\nssm.exe" install "$solrServiceName" "$solrDestinationPath\bin\solr.cmd" "-f" "-p $solrPort"
    $svc = Get-Service "$solrServiceName" -ErrorAction SilentlyContinue
}

if($svc.Status -ne "Running")
{
	Write-Host "Starting Solr service..."
	Start-Service "$solrServiceName"
}
elseif ($svc.Status -eq "Running")
{
	Write-Host "Restarting Solr service..."
	Restart-Service "$solrServiceName"
}

        
Start-Sleep -s 5

# finally prove it's all working
$protocol = "http"
if($solrSSL)
{
    $protocol = "https"
}

Invoke-Expression "start $($protocol)://$($solrHost):$solrPort/solr/#/"

Write-Host ''
Write-Host 'Done!' -ForegroundColor Green
Write-Host 'Your page will launch after the Service has started, but it will most likely not load SOLR immediately.' -ForegroundColor Green
Write-Host 'Give it about 10 seconds and then refresh the page. Happy Searching!' -ForegroundColor Green
