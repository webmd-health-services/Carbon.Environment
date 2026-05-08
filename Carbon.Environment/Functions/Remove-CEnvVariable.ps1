
function Remove-CEnvVariable
{
    <#
    .SYNOPSIS
    Removes an environment variable.

    .DESCRIPTION
    The `Remove-CEnvVariable` function deletes environment variables. Pass the names of the environment
    variables to delete to the `Name` parameter (or pipe the names into the function). If an environment variable does
    not exist at that scope, the function writes an error. Otherwise, the environment variable is deleted.

    By default, operates on the current process's environment variables. Use the `Scope` parameter to remove user-level
    and/or machine-level environment variables. Multiple scopes are accepted. Changes to environment variables are not
    reflected in running processes, including the current PowerShell session. If you want the removal of the user-level
    or machine-level environment variable to be reflected in the current process, include `Process` in the list of
    scopes passed to the `Scope` parameter.

    To remove a user-level environment variable for a specific user, pass that user's credentials to the `-Credential`
    parameter. A PowerShell process is run as that user to remove the environment variable.

    On Windows, environment variable names are case-insensitive. On Linux and macOS, environment variable names are
    case-sensitive.

    .LINK
    Set-CEnvVariable

    .LINK
    Test-CEnvVariable

    .EXAMPLE
    Remove-CEnvVariable -Name 'MyEnvironmentVariable'

    Demonstrates how to remove an environment variable from the current process. In this example, the
    `MyEnvironmentVariable` is removed. If it doesn't exist, an error is written.

    .EXAMPLE
    Remove-CEnvVariable -Name 'SomeComputerVariable' -Scope Machine

    Demonstrates how to remove a computer-level environment variable. In this example, the `SomeComputerVariable`
    environment variable is removed from the computer's environment variables. If that computer-level variable doesn't
    exist, an error is written.

    .EXAMPLE
    Remove-CEnvVariable -Name 'SomeUsersVariable' -Scope User

    Demonstrates how to remove a user-level environment variable for the current user. In this example, the
    `SomeUsersVariable` environment variable is removed from the current user's environment variables. If it doesn't
    exist at the user scope, an error is written.

    .EXAMPLE
    Remove-CEnvVariable -Name 'SomeUsersVariable' -Scope Process,User

    Demonstrates how to have the change to a user-level or machine-level environment variable reflected in the current
    process by including `Process` in the list of scopes passed to `Scope`.

    .EXAMPLE
    Remove-CEnvVariable -Name 'SomeUsersVariable' -Credential $user

    Demonstrates how to remove a user-level environment variable for a specific user. In this example, the
    `SomeUsersVariable` environment variable is removed from the `$user` user's environment variables. If that user
    doesn't have a `SomeUsersVariable` environment variable, an error is written.

    .EXAMPLE
    'Var1','Var2' | Remove-CEnvVariable

    Demonstrates that you can pipe the environment variables to delete to `Remove-CEnvVariable`.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='ForCurrentUser')]
    param(
        # The environment variable to remove. Case-insensitive on Windows, case-sensitive on Linux and macOS.
        [Parameter(Mandatory, ValueFromPipeline)]
        [String[]] $Name,

        # The scopes at which to remove the environment variable. Default is the current process.
        [Parameter(ParameterSetName='ForCurrentUser')]
        [EnvironmentVariableTarget[]] $Scope,

        # Remove an environment variable for a specific user.
        [Parameter(Mandatory, ParameterSetName='ForSpecificUser')]
        [pscredential] $Credential
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

        $userEnvVars = [Collections.Generic.List[string]]::new()

        if (-not $PSBoundParameters.ContainsKey('Scope'))
        {
            $Scope = [EnvironmentVariableTarget]::Process
        }

        # Delete at each scope once and delete from higher scopes first.
        $Scope = $Scope | Select-Object -Unique | Sort-Object -Descending
    }

    process
    {
        if ($Credential)
        {
            $userEnvVars.AddRange( $Name )
            return
        }

        foreach ($_name in $Name)
        {
            foreach ($_scope in $Scope)
            {
                $target = "$($_scope.ToString().ToLowerInvariant())-level environment variable ""${_name}"""

                if (-not (Test-CEnvVariable -Name $_name -Scope $_scope))
                {
                    $msg = "Failed to delete ${target} because it does not exist."
                    Write-Error -Message $msg -ErrorAction $ErrorActionPreference
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess($target, "remove"))
                {
                    continue
                }

                Write-Information "Removing ${target}."
                [Environment]::SetEnvironmentVariable($_name, [NullString]::Value, $_scope)
            }
        }
    }

    end
    {
        if (-not $Credential -or -not $userEnvVars.Count)
        {
            return
        }

        $parameters = $PSBoundParameters
        [void]$parameters.Remove('Credential')
        [void]$parameters.Remove('Name')
        Start-Job -ScriptBlock {
                    Import-Module -Name (Join-Path -Path $using:moduleDirPath -ChildPath 'Carbon.Environment.psm1')
                    $VerbosePreference = $using:VerbosePreference
                    $ErrorActionPreference = $using:ErrorActionPreference
                    $DebugPreference = $using:DebugPreference
                    $WhatIfPreference = $using:WhatIfPreference
                    $InformationPreference = $using:InformationPreference
                    Remove-CEnvVariable -Name $using:userEnvVars @using:parameters -Scope User
                } -Credential $Credential |
            Receive-Job -Wait -AutoRemoveJob
    }
}
