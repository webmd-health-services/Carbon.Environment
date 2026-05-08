
function Uninstall-CEnvVariable
{
    <#
    .SYNOPSIS
    Removes an environment variable if it exists.

    .DESCRIPTION
    The `Uninstall-CEnvVariable` function deletes environment variables, but only if they exist. Pass the names
    of the environment variables to delete to the `Name` parameter (or pipe in the names). Each environment variable
    that exists is deleted. No errors are written if an environment variable doesn't exist.

    By default, removes the current process's environment variables. Use the `Scope` parameter to remove user-level
    and/or machine-level environment variables. Multiple scopes are accepted. Changes to environment variables are not
    reflected in running processes, including the current PowerShell session. If you want the removal of user-level
    and/or machine-level environment variable to be reflected in the current process, include `Process` in the list of
    scopes passed to the `Scope` parameter.

    To remove a specific user's user-level environment variable, pass that user's credentials to the `-Credential`
    parameter.

    On Windows, environment variable names are case-insensitive. On Linux and macOS, environment variable names are
    case-sensitive.

    .LINK
    Remove-CEnvVariable

    .LINK
    Set-CEnvVariable

    .LINK
    Test-CEnvVariable

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'MyEnvironmentVariable'

    Demonstrates how to remove an environment variable from the current process if it exists. In this case, will remove
    the `MyEnvironmentVariable` environment variable, if it exists.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'MyUserVariable' -Scope User

    Demonstrates how to remove a user-level environment by including `User` in the list of scopes.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'MyComputerVariable' -Scope Machine

    Demonstrates how to remove a computer-level environment by including `Machine` in the list of scopes.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'MyComputerVariable' -Scope User,Machine

    Demonstrates that you can pass multiple scopes to the `Scope` parameter.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'MyComputerVariable' -Scope Process,Machine

    Demonstrates how to have the removal of a computer-level environment reflected in the current process by including
    `Process` in the list of scopes.

    .EXAMPLE
    'Var1','Var2' | Uninstall-CEnvVariable

    Demonstrates that you can pipe names to `Uninstall-CEnvVariable`.

    .EXAMPLE
    Uninstall-CEnvVariable Name 'Var1','Var2'

    Demonstrates that you can pass an array of names to the `Name` parameter.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'SomeUsersVariable' -Credential $credential

    Demonstrates that you can remove another user's user-level environment variable by passing its credentials to the
    `Credential` parameter. This runs a separate PowerShell process as that user to remove the variable.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='ForCurrentUser')]
    param(
        # The environment variable to remove. Case-insensitive on Windows, case-sensitive on Linux and macOS.
        [Parameter(Mandatory, ValueFromPipeline)]
        [String[]] $Name,

        # The scopes at which to remove the environment variable. Defaults to the current process.
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

        $userEnvVarsToDelete = [Collections.Generic.List[String]]::New()
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ForSpecificUser')
        {
            $userEnvVarsToDelete.AddRange($Name)
            return
        }

        if (-not $PSBoundParameters.ContainsKey('Scope'))
        {
            $Scope = [EnvironmentVariableTarget]::Process
        }

        $Scope = $Scope | Select-Object -Unique | Sort-Object -Descending

        foreach ($_name in $Name)
        {
            foreach ($_scope in $Scope)
            {
                if (-not (Test-CEnvVariable -Name $_name -Scope $_scope))
                {
                    continue
                }

                $target = "$($_scope.ToString().ToLowerInvariant())-level environment variable ""${_name}"""

                if (-not $PSCmdlet.ShouldProcess($target, 'remove'))
                {
                    continue
                }

                Write-Information "Removing ${target}."
                [Environment]::SetEnvironmentVariable( $_name, [NullString]::Value, $_scope )
            }
        }
    }

    end
    {
        if (-not $userEnvVarsToDelete.Count)
        {
            return
        }

        $uninstallArgs = $PSBoundParameters
        [void]$uninstallArgs.Remove('Credential')
        [void]$uninstallArgs.Remove('Name')
        Start-Job -ScriptBlock {
                    Import-Module -Name (Join-Path -Path $using:moduleDirPath -ChildPath 'Carbon.Environment.psm1')
                    $VerbosePreference = $using:VerbosePreference
                    $ErrorActionPreference = $using:ErrorActionPreference
                    $DebugPreference = $using:DebugPreference
                    $WhatIfPreference = $using:WhatIfPreference
                    $InformationPreference = $using:InformationPreference
                    Uninstall-CEnvVariable -Name $using:userEnvVarsToDelete -Scope User @using:uninstallArgs
                } -Credential $Credential |
            Receive-Job -Wait -AutoRemoveJob
    }
}
