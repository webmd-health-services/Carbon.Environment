
function Uninstall-CEnvVariable
{
    <#
    .SYNOPSIS
    Removes an environment variable or an item from an environment variable, if it exists.

    .DESCRIPTION
    The `Uninstall-CEnvVariable` function deletes environment variables or items from an environment variable.
    When deleting an environment variable, ignores if the environment variable no longer exists. When deleting an item
    from an environment variables, ignores if the item is no longer in the environment variable.

    To delete environment variables, pass their names to the `Name` parameter (or pipe in the names). Each environment
    variable that exists is deleted.

    To delete an item from an environment variable that is a list (e.g. `PATH`, `PSModulePath`, etc.), pass the name of
    the environment variable to the `Name` parameter, and the items to remove from the environment variable to the
    `Item` parameter. Each item that exists in the environment variable is removed. By default, the environment variable
    is split using `[IO.Path]::PathSeparator` (`;` on Windows, `:` on Linux and macOS). Pass a custom separator to the
    `Separator` parameter.

    By default, removes the current process's environment variables. PowerShell and .NET do not support user-level and
    computer-level environment variables. On Windows, use the `Scope` parameter to remove user-level and/or
    machine-level environment variables. Multiple scopes are accepted. Changes to environment variables are not
    reflected in running processes, including the current PowerShell session. If you want the removal of user-level
    and/or machine-level environment variable to be reflected in the current process, include `Process` in the list of
    scopes passed to the `Scope` parameter.

    To remove a specific user's user-level environment variable on Windows, pass that user's credentials to the
    `-Credential` parameter.

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

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'PATH' -Item 'C:\Some\Obsolete\Path'

    Demonstrates how to remove items from an environment variable whose value is a list. In this example, the
    `C:\Some\Obsolete\Path` path is removed from the `PATH` enviornment variable.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'PATH' -Item 'C:\Some\Obsolete\Path','C:\Some\Other\Obsolete\Path'

    Demonstrates that you can pass multiple items to the `Item` parameter to remove multiple items from an environment
    variable.

    .EXAMPLE
    Uninstall-CEnvVariable -Name 'MyPipeVar' -Item 'a' -Separator '|'

    Demonstrates how to remove items from an environment variable whose value is a list that uses a custom separator. In
    this case the `MyPipeVar` environment variable is split using a `|` character, `a` is removed, the list is joined
    with `|` character, and the environment variable is set to the new value.
    #>
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName='ForCurrentUser')]
    param(
        # The environment variable to remove. Case-insensitive on Windows, case-sensitive on Linux and macOS.
        [Parameter(Mandatory, ValueFromPipeline)]
        [String[]] $Name,

        # Items to remove from the environment variable. By default, the entire environment variable is removed if it
        # exists. If one or more items are specified, the environment variable's value is split using
        # `[IO.Path]::PathSeparator` (`;` on Windows, `:` on Linux and macOS), and each item in the list is removed. The
        # list is joined with the path separator, and the environment variable's value is set.
        #
        # Use the `Separator` parameter to customize the separator to use use.
        [String[]] $Item,

        # The separator for items in the list. Ignored unless `Item` has a value.
        [String] $Separator,

        # If set and removing items from an environment variable's value, omits the values being removed from
        # information messages.
        [switch] $Sensitive,

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

        $Scope = $Scope | Assert-Scope

        if (-not $PSBoundParameters.ContainsKey('Separator'))
        {
            $Separator = [IO.Path]::PathSeparator
        }
    }

    process
    {
        if ($PSCmdlet.ParameterSetName -eq 'ForSpecificUser')
        {
            $userEnvVarsToDelete.AddRange($Name)
            return
        }

        foreach ($_name in $Name)
        {
            foreach ($_scope in $Scope)
            {
                if (-not (Test-CEnvVariable -Name $_name -Scope $_scope))
                {
                    continue
                }

                $target = "$($_scope.ToString().ToLowerInvariant())-level environment variable ""${_name}"""

                if ($Item)
                {
                    $currentItems = Split-CEnvVariable -Name $_name -Scope $_scope -Separator $Separator
                    $itemsToRemove = $currentItems | Where-Object { $_ -in $Item }
                    if (-not $itemsToRemove)
                    {
                        continue
                    }

                    $newItems = $currentItems | Where-Object { $_ -notin $itemsToRemove }
                    $newValue = $newItems -join $Separator
                    $itemsToRemoveMsg = $itemsToRemove -join $Separator
                    $infoItemsMsg = 'items'
                    $targetItemsMsg = ''
                    if (-not $Sensitive)
                    {
                        $infoItemsMsg = """${itemsToRemoveMsg}"""
                        $targetItemsMsg = " '${itemsToRemoveMsg}'"
                    }

                    $suffix = ''
                    if (($itemsToRemove | Measure-Object).Count -gt 1)
                    {
                        $suffix = 's'
                    }

                    if (-not $PSCmdlet.ShouldProcess($target, "remove item${suffix}${targetItemsMsg}"))
                    {
                        continue
                    }

                    Write-Information "Removing ${infoItemsMsg} from ${target}."
                    [Environment]::SetEnvironmentVariable($_name, $newValue, $_scope)
                    continue
                }

                if (-not $PSCmdlet.ShouldProcess($target, 'remove'))
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
        if (-not $userEnvVarsToDelete.Count)
        {
            return
        }

        if (-not $IsWindows)
        {
            $msg = 'PowerShell and .NET only support user-level environment variables on Windows.'
            Write-Error -Message $msg -ErrorAction $ErrorActionPreference
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
