
function Set-CEnvVariable
{
    <#
    .SYNOPSIS
    Creates or sets an environment variable.

    .DESCRIPTION
    The `Set-CEnvVariable` function creates or sets en environment variable value. It uses
    `[Environment]::SetEnvironmentVariable`. Pass the name of the environment variable to the `Name` parameter, the
    value to the `Value` parameter. To set the variable computer-wide, use the `ForComputer` switch. To set the variable
    for the current user, use the `ForUser` switch. To set the variable for the current process, use the `ForProcess`
    switch. Multiple scopes are accepted.

    Changes to environment variables in the User and Machine scope are not picked up by running processes.  Any running
    processes that use this environment variable should be restarted.

    To set an environment variable for a specific user, pass that user's credentials to the `-Credential` parameter.
    This will run a PowerShell process as that user in order to set the environment variable.

    Normally, you have to restart your PowerShell session/process to see the variable in the `env:` drive. Use the
    `-Force` switch to also add the variable to the `env:` drive.

    .LINK
    Remove-CEnvVariable

    .LINK
    Test-CEnvVariable

    .EXAMPLE
    Set-CEnvVariable -Name 'MyEnvironmentVariable' -Value 'Value1' -ForProcess

    Creates the `MyEnvironmentVariable` with an initial value of `Value1` in the process scope, i.e. the variable is
    only accessible in the current process.

    .EXAMPLE
    Set-CEnvVariable -Name 'MyEnvironmentVariable' -Value 'Value1' -ForComputer

    Creates the `MyEnvironmentVariable` with an initial value of `Value1` in the machine scope, i.e. the variable is
    accessible in all newly launched processes.

    .EXAMPLE
    Set-CEnvVariable -Name 'SomeUsersEnvironmentVariable' -Value 'SomeValue' -ForUser -Credential $userCreds

    Demonstrates that you can set a user-level environment variable for another user by passing its credentials to the
    `Credential` parameter. Runs a separate PowerShell process as that user to set the environment variable.

    .EXAMPLE
    Set-CEnvVariable -Name 'MySensitiveEnvironmentVariable' -Value 'SecretValue' -ForProcess -Sensitive

    Demonstrates how to omit the environment variable value from the information message output by this function.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # The name of environment variable to add/set.
        [Parameter(Mandatory)]
        [String] $Name,

        # The environment variable's value.
        [Parameter(Mandatory)]
        [String] $Value,

        # Sets the environment variable for the current computer.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [switch] $ForComputer,

        # Sets the environment variable for the current user.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [Parameter(Mandatory, ParameterSetName='ForSpecificUser')]
        [switch] $ForUser,

        # Sets the environment variable for the current process.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [switch] $ForProcess,

        # Set the variable in the current PowerShell session's `env:` drive, too. Normally, you have to restart your
        # session to see the variable in the `env:` drive.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [switch] $Force,

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
        $parameters.Remove('Credential')
        $job = Start-Job -ScriptBlock {
            Import-Module -Name (Join-Path -path $using:moduleDirPath -ChildPath 'Carbon.Environment.psm1' -Resolve)
            $VerbosePreference = $using:VerbosePreference
            $ErrorActionPreference = $using:ErrorActionPreference
            $DebugPreference = $using:DebugPreference
            $WhatIfPreference = $using:WhatIfPreference
            Set-CEnvVariable @using:parameters
        } -Credential $Credential
        $job | Wait-Job | Receive-Job
        $job | Remove-Job -Force -ErrorAction Ignore
        return
    }

    if( -not $ForProcess -and -not $ForUser -and -not $ForComputer )
    {
        Write-Error -Message ('Environment variable target not specified. You must supply one of the ForComputer, ForUser, or ForProcess switches.')
        return
    }

    Invoke-Command -ScriptBlock {
            if( $ForComputer )
            {
                [EnvironmentVariableTarget]::Machine
            }

            if( $ForUser )
            {
                [EnvironmentVariableTarget]::User
            }

            if( $Force -or $ForProcess )
            {
                [EnvironmentVariableTarget]::Process
            }
        } |
        Where-Object { $PSCmdlet.ShouldProcess( "${_}-level environment variable ""${Name}""", "set") } |
        ForEach-Object {
            $valueMsg = " to ""${Value}"""
            if ($Sensitive)
            {
                $valueMsg = ''
            }

            $msg = "Setting $($_.ToString().ToLowerInvariant())-level environment variable ""${Name}""${valueMsg}."
            Write-Information $msg
            [Environment]::SetEnvironmentVariable( $Name, $Value, $_ )
        }
}
