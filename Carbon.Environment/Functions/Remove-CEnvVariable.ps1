
function Remove-CEnvVariable
{
    <#
    .SYNOPSIS
    Removes an environment variable.

    .DESCRIPTION
    The `Remove-CEnvVariable` function deletes environment variables. Pass the name to the `Name` parameter and
    the scope(s) to remove it from with the `ForProcess`, `ForUser`, and/or `ForComputer` switches. If an environment
    variable does not exist at that scope, the function writes an error. Uses the
    `[Environment]::SetEnvironmentVariable` method to remove variable. Writes an information message for each
    environment variable removed.

    Changes to environment variables in the User and Machine scope are not picked up by running processes.  Any running
    processes that use this environment variable should be restarted.

    Normally, you have to restart your PowerShell session/process to no longer see the variable in the `env:` drive. Use
    the `-Force` switch to also remove the variable from the `env:` drive.

    On Windows, environment variable names are case-insensitive. On Linux and macOS, environment variable names are
    case-sensitive.

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
        # The environment variable to remove. Case-insensitive on Windows, case-sensitive on Linux and macOS.
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
            if ($ForComputer)
            {
                [EnvironmentVariableTarget]::Machine
            }

            if ($ForUser)
            {
                [EnvironmentVariableTarget]::User
            }

            if ($Force -or $ForProcess)
            {
                [EnvironmentVariableTarget]::Process
            }
        } |
        Where-Object { $PSCmdlet.ShouldProcess( "${_}-level environment variable ""${Name}""", "remove" ) } |
        ForEach-Object {
                $scope = $_

                if (-not (Test-CEnvVariable -Name $Name -Scope $scope))
                {
                    # If forced, and we added the process scope, don't write an error
                    if ($Force -and $scope -eq [EnvironmentVariableTarget]::Process -and -not $ForProcess)
                    {
                        continue
                    }

                    $msg = "Failed to delete ${Scope}-level environment variable ""${Name}"" because it does not " +
                           'exist.'
                    Write-Error -Message $msg -ErrorAction $ErrorActionPreference
                    return
                }

                $msg = "Removing $($Scope.ToString().ToLowerInvariant())-level environment variable ""${Name}""."
                Write-Information $msg
                [Environment]::SetEnvironmentVariable( $Name, [NullString]::Value, $scope )
            }
}
