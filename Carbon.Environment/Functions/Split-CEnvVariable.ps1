
function Split-CEnvVariable
{
    <#
    .SYNOPSIS
    Splits an environment variable value into a list.

    .DESCRIPTION
    The `Split-CEnvVariable` function splits an environment variable into a list. Pass the name of the
    environment variable to the `Name` parameter. By default, will split the environment variable using the
    `[IO.Path]::PathSeparator` character (`;` on Windows, `:` on Linux and macOS). Pass a custom separator to the
    `Separator` parameter.

    By default, splits process-level environment variables. To operate on user-level and computer-level environment
    variables, use the `Scope` parameter. Note that user-level and computer-level environment variables are only
    supported on Windows.

    If the environment variable doesn't exist, writes an error and returns an empty array.

    Environment variable names are case-insensitive on Windows and are case-sensitive on Linux and macOS.

    .EXAMPLE
    Split-CEnvVariable -Name 'PATH'

    Demonstrates how to split the current process's `PATH` environment variable using the `[IO.Path]::PathSeparator`.

    .EXAMPLE
    Split-CEnvVariable -Name 'PATH' -Scope Machine

    Demonstrates how to operate on a machine-level environment variable by passing `Machine` to the `Scope` parameter.

    .EXAMPLE
    Split-CEnvVariable -Name 'MyPipeVar' -Separator '|'

    Demonstrates how to split an environment variable using a custom separator.
    #>
    [CmdletBinding()]
    param(
        # The name of the environmen variable whose value to split. If the variable doesn't exist, writes an error.
        [Parameter(Mandatory)]
        [String] $Name,

        # The scope/level of environment variable to split. By default, uses process-level environment variables. Pass
        # `User` or `Machine` to split a user-level or machine-level environment variable.
        [EnvironmentVariableTarget] $Scope,

        # The string to use that separates items in the environment variable's values. By default, splits the
        # environment variable's value using `[IO.Path]::PathSeparator` (`;` on Windows, `:` on Linux and macOS).
        [String] $Separator
    )

    Set-StrictMode -Version 'Latest'
    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $Scope = $Scope | Assert-Scope

    if (-not (Test-CEnvVariable -Name $Name -Scope $Scope))
    {
        $msg = "Failed to split $($Scope.ToString().ToLowerInvariant())-level environment variable ""${Name}"" " +
               'because it doesn''t exist.'
        Write-Error -Message $msg -ErrorAction Ignore
        return @()
    }

    $value = [Environment]::GetEnvironmentVariable($Name, $Scope)

    if ($null -eq $value)
    {
        return @()
    }

    if (-not $Separator)
    {
        $Separator = [IO.Path]::PathSeparator
    }

    return $value.Split($Separator, [StringSplitOptions]::None)
}
