
function Test-CEnvVariable
{
    <#
    .SYNOPSIS
    Tests if an environment variable exists.

    .DESCRIPTION
    The `Test-CEnvVariable` function tests if an environment variable exists. Pass the name of the variable to
    the `Name` parameter (or pipe in multiple names). If a variable with that name exists in the current process,
    returns `$true`. Otherwise, returns `$false`.

    By default, checks in the current process's environment variables. PowerShell and .NET do not support user-level and
    computer-level environment variables. On Windows, use the `Scope` parameter to check if user-level or computer-level
    environment variables exist.

    To check if a specific user has an environment variable on Windows, pass that user's credentials to the `Credential`
    parameter.

    On Windows, environment variable names are case-insenstive. On Linux and macOS, they are case-sensitive.

    .LINK
    Remove-CEnvVariable

    .LINK
    Set-CEnvVariable

    .LINK
    Uninstall-CEnvVariable

    .EXAMPLE
    Test-CEnvVariable -Name 'PATH'

    Demonstrates how to check that an environment variable exists. In this case, will return `$true` if the `PATH`
    environment variable exists at any scope.

    .EXAMPLE
    Test-CEnvVariable -Name 'MY_VAR' -Scope User

    Demonstrates how to check that an environment variable exists at a specific scope. In this case, will return `$true`
    if the user has a `MY_VAR` environment variable.

    .EXAMPLE
    'PATH' | Test-CEnvVariable

    Demonstrates that you can pipe environment variable names to `Test-CEnvVariable`.
    #>
    [CmdletBinding(DefaultParameterSetName='CurrentUser')]
    param(
        # The name of the environment variable to check. Case-insensitive on Windows. Cse-sensitive on Linux and MacOS.
        [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [String] $Name,

        # The specific scope to check. By default, checks the current process.
        [Parameter(ParameterSetName='CurrentUser')]
        [EnvironmentVariableTarget] $Scope,

        # The credential of the user whose user-level environment variables to check.
        [Parameter(Mandatory, ParameterSetName='ForUser')]
        [pscredential] $Credential
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

        $userEnvVars = [Collections.Generic.List[String]]::New()

        $validScope = $Scope | Assert-Scope
    }

    process
    {
        if ($Credential)
        {
            $userEnvVars.Add($Name)
            return
        }

        if ($null -eq $validScope)
        {
            return
        }

        return ($null -ne [Environment]::GetEnvironmentVariable($Name, $validScope))
    }

    end
    {
        if (-not $Credential -or -not $userEnvVars.Count)
        {
            return
        }

        if (-not $IsWindows)
        {
            $msg = 'PowerShell and .NET only support user-level environment variables on Windows.'
            Write-Error -Message $msg -ErrorAction $ErrorActionPreference
            return
        }

        $parameters = $PSBoundParameters
        [void]$parameters.Remove('Credential')
        [void]$parameters.Remove('Name')
        Start-Job -ScriptBlock {
                Import-Module -Name (Join-Path -path $using:moduleDirPath -ChildPath 'Carbon.Environment.psm1' -Resolve)
                $VerbosePreference = $using:VerbosePreference
                $ErrorActionPreference = $using:ErrorActionPreference
                $DebugPreference = $using:DebugPreference
                $WhatIfPreference = $using:WhatIfPreference
                $InformationPreference = $using:InformationPreference
                $using:userEnvVars | Test-CEnvVariable @using:parameters -Scope User
            } -Credential $Credential |
            Receive-Job -Wait -AutoRemoveJob |
            Write-Output
    }
}