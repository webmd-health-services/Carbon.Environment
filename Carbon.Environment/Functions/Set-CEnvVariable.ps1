
function Set-CEnvVariable
{
    <#
    .SYNOPSIS
    Creates or sets an environment variable.

    .DESCRIPTION
    The `Set-CEnvVariable` function creates or sets an environment variable. Pass the name of the environment
    variable to the `Name` parameter and the value to the `Value` parameter. An environment variable with that name and
    value is set for the current process. Use the `Scope` parameter to set user-level and/or machine-level variables.
    Uses `[Environment]::SetEnvironmentVariable` to create the variable if it doesn't exist, or update its value if the
    variable exists and its value is different from the value being set.

    By default, creates and sets the current process's environment variables. Use the `Scope` parameter to remove
    user-level and/or machine-level environment variables. Multiple scopes are accepted. Changes to environment
    variables are not reflected in running processes, including the current PowerShell session. If you want a new or
    changed user-level or machine-level environment variable to be reflected in the current process, include `Process`
    in the list of scopes passed to the `Scope` parameter.

    Writes an information message for each environment variable created or updated. The message includes the value being
    set. Use the `Sensitive` switch to omit the value from the information message.

    On Windows, environment variable names are case-insensitive. On Linux and macOS, environment variable names are
    case-sensitive.

    In PowerShell 7.4 and earlier, setting `Value` to an empty string deletes the variable. In newer versions of
    PowerShell, the variable is set to an empty value.

    To create or set an environment variable for a specific user, pass that user's credentials to the `-Credential`
    parameter. This will run a PowerShell process that creates or sets the environment variable.

    .LINK
    Remove-CEnvVariable

    .LINK
    Test-CEnvVariable

    .LINK
    Uninstall-CEnvVariable

    .EXAMPLE
    Set-CEnvVariable -Name 'MyEnvironmentVariable' -Value 'Value1'

    Demonstrates how to create or set an environemnt variable for the current process. In this example, the current
    process's `MyEnvironmentVariable` variable is created or set with a value of `Value1`.

    .EXAMPLE
    Set-CEnvVariable -Name 'MyEnvironmentVariable' -Value 'Value1' -Scope Machine

    Demonstrates how to create a computer-level environment variable by including `Machine` in the list of scopes passed
    to the `Scope` parameter. The current process's environment variables will not have the new or updated environment
    variable.

    .EXAMPLE
    Set-CEnvVariable -Name 'MyEnvironmentVariable' -Value 'Value1' -Scope User

    Demonstrates how to create a user environment variable by including `User` in the list of scopes passed to the
    `Scope` parameter. The current process's environment variables will not have the new or updated environment
    variable.

    .EXAMPLE
    Set-CEnvVariable -Name 'MyEnvironmentVariable' -Value 'Value1' -Scope Process,User

    Demonstrates how to have a change to a user or machine-level environment variable reflected in the current process
    by including `Process` in the list of scopes passed to the `Scope` parameter.

    .EXAMPLE
    Set-CEnvVariable -Name 'SomeUsersEnvironmentVariable' -Value 'SomeValue' -Credential $userCreds

    Demonstrates how to set an environment variable for a specific user by passing that user's credentials to the
    `Credential` parameter.

    .EXAMPLE
    Set-CEnvVariable -Name 'MySensitiveEnvironmentVariable' -Value 'SecretValue' -Sensitive

    Demonstrates how to omit the environment variable's value from the information message output by this function.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # The name of environment variable to add/set. Case-insensitive on Windows. Case-sensitive on Linux and macOS.
        [Parameter(Mandatory)]
        [String] $Name,

        # The environment variable's value. In PowerShell 7.4 and earlier, setting this to an empty string deletes the
        # variable. In newer versions, the variable is created with an empty value.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [String] $Value,

        # The scopes at which to set the variable. Default is the current process. Changes to user-level and
        # computer-level variables are not reflected in the current process's environment variables unless `Process` is
        # in this list.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [EnvironmentVariableTarget[]] $Scope,

        [Parameter(Mandatory,ParameterSetName='ForSpecificUser')]
        # Set an environment variable for a specific user.
        [pscredential] $Credential,

        # Don't output the variable's value in information messages.
        [switch] $Sensitive
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if( $PSCmdlet.ParameterSetName -eq 'ForSpecificUser' )
    {
        $parameters = $PSBoundParameters
        [void]$parameters.Remove('Credential')
        $job = Start-Job -ScriptBlock {
            Import-Module -Name (Join-Path -path $using:moduleDirPath -ChildPath 'Carbon.Environment.psm1' -Resolve)
            $VerbosePreference = $using:VerbosePreference
            $ErrorActionPreference = $using:ErrorActionPreference
            $DebugPreference = $using:DebugPreference
            $WhatIfPreference = $using:WhatIfPreference
            $InformationPreference = $using:InformationPreference
            Set-CEnvVariable @using:parameters -Scope User
        } -Credential $Credential
        $job | Wait-Job | Receive-Job
        $job | Remove-Job -Force -ErrorAction Ignore
        return
    }

    if (-not $PSBoundParameters.ContainsKey('Scope'))
    {
        $Scope = [EnvironmentVariableTarget]::Process
    }

    # Set at lower scopes first.
    $Scope = $Scope | Select-Object -Unique | Sort-Object

    foreach ($_scope in $Scope)
    {
        # Only set the variable if its value has changed.
        if ($Value -eq [Environment]::GetEnvironmentVariable($Name, $_scope))
        {
            continue
        }

        $target = "$($_scope.ToString().ToLowerInvariant())-level environment variable ""${Name}"""

        if (-not $PSCmdlet.ShouldProcess($target, "set"))
        {
            continue
        }

        $valueMsg = " to ""${Value}"""
        if ($Sensitive)
        {
            $valueMsg = ''
        }

        Write-Information "Setting ${target}${valueMsg}."
        [Environment]::SetEnvironmentVariable($Name, $Value, $_scope)
    }
}
