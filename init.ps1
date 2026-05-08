<#
.SYNOPSIS
Gets your computer ready to develop the Carbon.Environment module.

.DESCRIPTION
The init.ps1 script makes the configuraion changes necessary to get your computer ready to develop for the
Carbon.Environment module. It:


.EXAMPLE
.\init.ps1

Demonstrates how to call this script.
#>
[CmdletBinding()]
param(
)

#Requires -RunAsAdministrator
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

if (-not (Test-Path -Path 'variable:IsWindows'))
{
    $script:IsWindows = $true
    $script:IsLinux = $script:IsMacOS = $false
}

$password = ConvertTo-SecureString -String '1m33trequ!rments' -Force -AsPlainText
$credentials = [pscredential]::New('CEnvironment', $password)
$credentials | Export-Clixml -Path '.cenvironment'

if ($IsWindows)
{
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'PSModules\Carbon' -Resolve) `
                  -Function @('Install-CUser') `
                  -Verbose:$false

    Install-CUser -Credential $credentials -Description 'Carbon.Environment PowerShell module test user.'
}
