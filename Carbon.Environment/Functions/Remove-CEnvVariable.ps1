
function Remove-CEnvVariable
{
    <#
    .SYNOPSIS
    Removes an environment variable or items from an environment variable that's a list.

    .DESCRIPTION
    The `Remove-CEnvVariable` function deletes environment variables or items from an environment variable that
    is a list.

    To delete an environment variable, pass the names of the environment variables to delete to the `Name` parameter (or
    pipe the names into the function). If an environment variable does not exist at that scope, the function writes an
    error. Otherwise, the environment variable is deleted.

    To delete an item from an environment variable that is a list (e.g. `PATH`, `PSModulePath`, etc.), pass the
    environment variable's name to the `Name` parameter and the items to remove from the environment variable's list to
    the `Item` parameter. If an item doesn't exist in the list, the function deletes items that are in the list and
    writes an error if any items to remove are missing. By default, creates the list by splitting the environment
    variable's value using `[IO.Path]::PathSeparator` (`;` on Windows, `:` on Linux and macOS). To use a different
    separator, pass it to the `Separator` parameter.

    By default, operates on the current process's environment variables. PowerShell and .NET do not support user-level
    and computer-level environment variables. On Windows, use the `Scope` parameter to remove user-level and/or
    machine-level environment variables. Multiple scopes are accepted. Changes to environment variables are not
    reflected in running processes, including the current PowerShell session. If you want the removal of the user-level
    or machine-level environment variable to be reflected in the current process, include `Process` in the list of
    scopes passed to the `Scope` parameter.

    To remove a user-level environment variable for a specific user on Windows, pass that user's credentials to the
    `-Credential` parameter. A PowerShell process is run as that user to remove the environment variable.

    On Windows, environment variable names are case-insensitive. On Linux and macOS, environment variable names are
    case-sensitive.

    .LINK
    Set-CEnvVariable

    .LINK
    Test-CEnvVariable

    .LINK
    Uninstall-CEnvVariable

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

    .EXAMPLE
    Remove-CEnvVariable -Name 'PATH' -Item 'C:\Some\Obsolete\Path'

    Demonstrates how to remove items from an environment variable whose value is a list. In this example, the
    `C:\Some\Obsolete\Path` path is removed from the `PATH` enviornment variable.

    .EXAMPLE
    Remove-CEnvVariable -Name 'PATH' -Item 'C:\Some\Obsolete\Path','C:\Some\Other\Obsolete\Path'

    Demonstrates that you can pass multiple items to the `Item` parameter to remove multiple items from an environment
    variable.

    .EXAMPLE
    Remove-CEnvVariable -Name 'MyPipeVar' -Item 'a' -Separator '|'

    Demonstrates how to remove items from an environment variable whose value is a list that uses a custom separator. In
    this case the `MyPipeVar` environment variable is split using a `|` character, `a` is removed, the list is joined
    with `|` character, and the environment variable is set to the new value.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='Single_ForCurrentUser')]
    param(
        # The environment variable to remove. Case-insensitive on Windows, case-sensitive on Linux and macOS.
        [Parameter(Mandatory, Position=0, ParameterSetName='Single_ForCurrentUser', ValueFromPipeline)]
        [Parameter(Mandatory, Position=0, ParameterSetName='Single_ForSpecificUser', ValueFromPipeline)]
        [Parameter(Mandatory, Position=0, ParameterSetName='List_ForCurrentUser')]
        [Parameter(Mandatory, Position=0, ParameterSetName='List_ForSpecificUser')]
        [String[]] $Name,

        # Items to remove from the environment variable.
        [Parameter(Mandatory, ParameterSetName='List_ForCurrentUser')]
        [Parameter(Mandatory, ParameterSetName='List_ForSpecificUser')]
        [String[]] $Item,

        # The separator for the items in the environment variable. Default is `[IO.Path]::PathSeparator`, `;` on
        # Windows, `:` on Linux and macOS.
        [Parameter(ParameterSetName='List_ForCurrentUser')]
        [Parameter(ParameterSetName='List_ForSpecificUser')]
        [String] $Separator,

        # The scopes at which to remove the environment variable. Default is the current process.
        [Parameter(ParameterSetName='Single_ForCurrentUser')]
        [Parameter(ParameterSetName='List_ForCurrentUser')]
        [EnvironmentVariableTarget[]] $Scope,

        # Remove an environment variable for a specific user.
        [Parameter(Mandatory, ParameterSetName='Single_ForSpecificUser')]
        [Parameter(Mandatory, ParameterSetName='List_ForSpecificUser')]
        [pscredential] $Credential,

        [Parameter(ParameterSetName='List_ForCurrentUser')]
        [Parameter(ParameterSetName='List_ForSpecificUser')]
        [switch] $Sensitive
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

        $userEnvVars = [Collections.Generic.List[string]]::new()

        $Scope = $Scope | Assert-Scope

        if (-not $Separator)
        {
            $Separator = [IO.Path]::PathSeparator
        }
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

                if ($Item)
                {
                    if (-not (Test-CEnvVariable -Name $_name -Scope $_scope))
                    {
                        $msg = "Failed to remove items from ${target} because it does not exist."
                        Write-Error -Message $msg -ErrorAction $ErrorActionPreference
                        continue
                    }

                    $currentItems = Split-CEnvVariable -Name $_name -Scope $_scope -Separator $Separator
                    $itemsMissing = $Item | Where-Object { $_ -notin $currentItems }
                    if ($itemsMissing)
                    {
                        $suffix = ''
                        if (($itemsMissing | Measure-Object).Count -gt 1)
                        {
                            $suffix = 's'
                        }

                        $itemsMsg = """$($itemsMissing -join $Separator)"" item${suffix}"
                        $thoseThe = 'those'
                        if ($Sensitive)
                        {
                            $itemsMsg = "sensitive item${suffix}"
                            $thoseThe = 'the'
                        }
                        $msg = "Failed to remove ${itemsMsg} from ${target} because ${thoseThe} item${suffix} do not " +
                               'exist.'
                        Write-Error -Message $msg -ErrorAction $ErrorActionPreference
                    }

                    $itemsToRemove = $Item | Where-Object { $_ -in $currentItems }
                    $suffix = ''
                    if (($itemsToRemove | Measure-Object).Count -gt 1)
                    {
                        $suffix = 's'
                    }
                    $itemsMsg = "item${suffix} ""$($itemsToRemove -join $Separator)"""
                    if ($Sensitive)
                    {
                        $itemsMsg = "sensitive item${suffix}"
                    }

                    $newItems = $currentItems | Where-Object { $_ -notin $itemsToRemove }
                    $newValue = $newItems -join $Separator

                    if (-not $PSCmdlet.ShouldProcess($target, ("remove ${itemsMsg}" -replace '"', '''')))
                    {
                        continue
                    }

                    Write-Information "Removing ${itemsMsg} from ${target}."
                    [Environment]::SetEnvironmentVariable($_name, $newValue, $_scope)
                    continue
                }

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
