
function Set-CEnvVariable
{
    <#
    .SYNOPSIS
    Creates or sets an environment variable.

    .DESCRIPTION
    The `Set-CEnvVariable` function creates or sets an environment variable. Pass the name of the environment variable
    to the `Name` parameter and the value to the `Value` parameter. An environment variable with that name and value is
    set for the current process. Use the `Scope` parameter to set user-level and/or machine-level variables. Uses
    `[Environment]::SetEnvironmentVariable` to create the variable if it doesn't exist, or update its value if the
    variable exists and its value is different from the value being set.

    For environment variable's that are lists (e.g. `PATH`, `PSModulesPath`, etc.), `Set-CEnvVariable` can add items to
    the beginning or end of the list. Pass the item(s) to add to the list to the `Item` parameter. Any item not already
    in the list is added to the beginning. To append items instead, use the `Append` switch. By default, uses
    `[IO.Path]::PathSeparator` as the item separator. Use the `Separator` parameter to use a custom separator. If an
    item is already in the list, it is not moved.

    By default, creates and sets the current process's environment variables. PowerShell and .NET on Linux and macOS do
    not support user-level and computer-level environment variables. On Windows, use the `Scope` parameter to remove
    user-level and/or machine-level environment variables. Multiple scopes are accepted. Changes to environment
    variables are not reflected in running processes, including the current PowerShell session. If you want a new or
    changed user-level or machine-level environment variable to be reflected in the current process, include `Process`
    in the list of scopes passed to the `Scope` parameter.

    To create or set an environment variable for a specific user on Windows, pass that user's credentials to the
    `-Credential` parameter. This will run a PowerShell process that creates or sets the environment variable.

    Writes an information message for each environment variable created or updated. The message includes the value being
    set. Use the `Sensitive` switch to omit the value from the information message.

    On Windows, environment variable names are case-insensitive. On Linux and macOS, environment variable names are
    case-sensitive.

    In PowerShell 7.4 and earlier, setting `Value` to an empty string deletes the variable. In newer versions of
    PowerShell, the variable is set to an empty value.

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
        [Parameter(Mandatory, Position=0)]
        [String] $Name,

        # The environment variable's value. In PowerShell 7.4 and earlier, setting this to an empty string deletes the
        # variable. In newer versions, the variable is created with an empty value.
        [Parameter(Mandatory, ParameterSetName='Single_CurrentUser')]
        [Parameter(Mandatory, ParameterSetName='Single_ForSpecificUser')]
        [AllowEmptyString()]
        [String] $Value,

        # Adds an item in an environment variable this is a list of items.
        [Parameter(Mandatory, ParameterSetName='List_CurrentUser')]
        [Parameter(Mandatory, ParameterSetName='List_ForSpecificUser')]
        [String[]] $Item,

        # The separator between items in the list. Default is `[IO.Path]::PathSeparator` (`;` on Windows; `:` on Linux
        # and macOS).
        [Parameter(ParameterSetName='List_CurrentUser')]
        [Parameter(ParameterSetName='List_ForSpecificUser')]
        [String] $Separator,

        # When adding an item to an environment variable that is a list, add it to the end of the list. By default, it
        # is added to the beginning.
        [Parameter(ParameterSetName='List_CurrentUser')]
        [Parameter(ParameterSetName='List_ForSpecificUser')]
        [switch] $Append,

        # The scopes at which to set the variable. Default is the current process. Changes to user-level and
        # computer-level variables are not reflected in the current process's environment variables unless `Process` is
        # in this list.
        [Parameter(ParameterSetName='Single_CurrentUser')]
        [Parameter(ParameterSetName='List_CurrentUser')]
        [EnvironmentVariableTarget[]] $Scope,

        [Parameter(Mandatory,ParameterSetName='List_ForSpecificUser')]
        [Parameter(Mandatory,ParameterSetName='Single_ForSpecificUser')]
        # Set an environment variable for a specific user.
        [pscredential] $Credential,

        # Don't output the variable's value in information messages.
        [switch] $Sensitive
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    if ($Credential)
    {
        if (-not $IsWindows)
        {
            $msg = 'PowerShell and .NET only support user-level environment variables on Windows.'
            Write-Error -Message $msg -ErrorAction $ErrorActionPreference
            return
        }

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

    $Scope = $Scope | Assert-Scope

    if (-not $Separator)
    {
        $Separator = [IO.Path]::PathSeparator
    }

    foreach ($_scope in $Scope)
    {
        $target = "$($_scope.ToString().ToLowerInvariant())-level environment variable ""${Name}"""
        $action = 'set'
        $actionMsg = 'Setting'

        # Are we adding an item to an environment variable that is a list?
        if ($Item)
        {
            $items = Split-CEnvVariable -Name $Name -Scope $_scope -Separator $Separator
            $itemsToAdd = $Item | Where-Object { $items -notcontains $_ }
            if (-not $itemsToAdd)
            {
                continue
            }

            if ($itemsToAdd)
            {
                $newItems = $itemsToAdd -join $Separator

                $location = 'beginning'
                if ($Append)
                {
                    $location = 'end'
                }

                $action = "add ""${newItems}"""
                $actionMsg = "Adding ""${newItems}"" to ${location} of"
                if ($Sensitive)
                {
                    $itemCount = ($itemsToAdd | Measure-Object).Count
                    $suffix = ''
                    if ($itemCount -gt 1)
                    {
                        $suffix = 's'
                    }
                    $action = "adding ${itemCount} item${suffix}"
                    $actionMsg = "Adding ${itemCount} item${suffix} to ${location} of"
                }

                $items = & {
                    if (-not $Append)
                    {
                        $newItems | Write-Output
                    }

                    $items | Write-Output

                    if ($Append)
                    {
                        $newItems | Write-Output
                    }
                }

                $Value = $items -join $Separator
            }
        }

        # Only set the variable if its value has changed.
        if ($Value -eq [Environment]::GetEnvironmentVariable($Name, $_scope))
        {
            continue
        }

        if (-not $PSCmdlet.ShouldProcess($target, $action))
        {
            continue
        }

        $valueMsg = " to ""${Value}"""
        if ($Sensitive -or $Item)
        {
            $valueMsg = ''
        }

        Write-Information "${actionMsg} ${target}${valueMsg}."
        [Environment]::SetEnvironmentVariable($Name, $Value, $_scope)
    }
}
