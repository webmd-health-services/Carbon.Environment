
function Set-CEnvVariable
{
    <#
    .SYNOPSIS
    Creates or sets an environment variable.

    .DESCRIPTION
    Uses the .NET [Environment class](http://msdn.microsoft.com/en-us/library/z8te35sa) to create or set an environment
    variable in the Process, User, or Machine scopes.

    Changes to environment variables in the User and Machine scope are not picked up by running processes.  Any running
    processes that use this environment variable should be restarted.

    To set an environment variable for a specific user, pass that user's credentials to the `-Credential` parameter.
    This will run a PowerShell process as that user in order to set the environment variable.

    Normally, you have to restart your PowerShell session/process to see the variable in the `env:` drive. Use the
    `-Force` switch to also add the variable to the `env:` drive.

    .LINK
    Remove-CEnvVariable

    .LINK
    http://msdn.microsoft.com/en-us/library/z8te35sa

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
        [pscredential] $Credential
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
        Where-Object { $PSCmdlet.ShouldProcess( "$_-level environment variable '$Name'", "set") } |
        ForEach-Object { [Environment]::SetEnvironmentVariable( $Name, $Value, $_ ) }
}

