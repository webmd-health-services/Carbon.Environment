
function Remove-CEnvVariable
{
    <#
    .SYNOPSIS
    Removes an environment variable.

    .DESCRIPTION
    Uses the .NET [Environment class](http://msdn.microsoft.com/en-us/library/z8te35sa) to remove an environment
    variable from the Process, User, or Computer scopes.

    Changes to environment variables in the User and Machine scope are not picked up by running processes.  Any running
    processes that use this environment variable should be restarted.

    Normally, you have to restart your PowerShell session/process to no longer see the variable in the `env:` drive. Use
    the `-Force` switch to also remove the variable from the `env:` drive.

    Beginning with Carbon 2.3.0, you can set an environment variable for a specific user by specifying the `-ForUser`
    switch and passing the user's credentials with the `-Credential` parameter. This runs a separate PowerShell process
    as that user to remove the variable.

    Beginning in Carbon 2.3.0, you can specify multiple scopes from which to remove an environment variable. In previous
    versions, you could only remove from one scope.

    .LINK
    Set-CEnvVariable

    .LINK
    http://msdn.microsoft.com/en-us/library/z8te35sa

    .EXAMPLE
    Remove-CEnvVariable -Name 'MyEnvironmentVariable' -ForProcess

    Removes the `MyEnvironmentVariable` from the process scope.

    .EXAMPLE
    Remove-CEnvVariable -Name 'SomeUsersVariable' -ForUser -Credential $credential

    Demonstrates that you can remove another user's user-level environment variable by passing its credentials to the
    `Credential` parameter. This runs a separate PowerShell process as that user to remove the variable.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        # The environment variable to remove.
        [Parameter(Mandatory)]
        [String] $Name,

        # Removes the environment variable for the current computer.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [switch] $ForComputer,

        # Removes the environment variable for the current user.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [Parameter(Mandatory, ParameterSetName='ForSpecificUser')]
        [switch] $ForUser,

        # Removes the environment variable for the current process.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [switch] $ForProcess,

        # Remove the variable from the current PowerShell session's `env:` drive, too. Normally, you have to restart
        # your session to no longer see the variable in the `env:` drive.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [switch] $Force,

        # Remove an environment variable for a specific user.
        [Parameter(Mandatory, ParameterSetName='ForSpecificUser')]
        [pscredential] $Credential
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if ($PSCmdlet.ParameterSetName -eq 'ForSpecificUser')
    {
        $parameters = $PSBoundParameters
        $parameters.Remove('Credential')
        $job = Start-Job -ScriptBlock {
            Import-Module -Name (Join-Path -Path $using:moduleDirPath -ChildPath 'Carbon.Environment.psm1')
            $VerbosePreference = $using:VerbosePreference
            $ErrorActionPreference = $using:ErrorActionPreference
            $DebugPreference = $using:DebugPreference
            $WhatIfPreference = $using:WhatIfPreference
            Remove-CEnvVariable @using:parameters
        } -Credential $Credential
        $job | Wait-Job | Receive-Job
        $job | Remove-Job -Force -ErrorAction Ignore
        return
    }

    if (-not $ForProcess -and -not $ForUser -and -not $ForComputer)
    {
        $msg = 'Environment variable target not specified. You must supply one of the ForComputer, ForUser, or ' +
               'ForProcess switches.'
        Write-Error -Message $msg -ErrorAction $ErrorActionPreference
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

            if( $ForProcess )
            {
                [EnvironmentVariableTarget]::Process
            }
        } |
        Where-Object { $PSCmdlet.ShouldProcess( "${_}-level environment variable ""${Name}""", "remove" ) } |
        ForEach-Object {
                $scope = $_
                [Environment]::SetEnvironmentVariable( $Name, [NullString]::Value, $scope )
                if ($Force -and $scope -ne [EnvironmentVariableTarget]::Process)
                {
                    [Environment]::SetEnvironmentVariable($Name, [NullString]::Value, 'Process')
                }
            }
}
