
function Assert-Scope
{
    [CmdletBinding()]
    param(
        [Parameter(ValueFromPipeline)]
        [Object] $Scope,

        [String] $Message
    )

    begin
    {
        Set-StrictMode -Version 'Latest'
        Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

        $writeError = $false
        $receivedCount = 0

        $seenScopes = [Collections.Generic.Hashset[EnvironmentVariableTarget]]::New()
    }

    process
    {
        if ($null -eq $Scope)
        {
            return
        }

        if ($Scope -isnot [EnvironmentVariableTarget])
        {
            $msg = "Failed to validate scope ""${Scope}"" because it is a [$($Scope.GetType().FullName)] object, but " +
                   'we expected [EnvironmentVariableTarget].'
            Write-Error -Message $msg -ErrorAction Stop
            return
        }

        $receivedCount += 1

        # PowerShell and .NET do not support user-level and computer-level environment variables on Linux and macOS.
        if (-not $IsWindows -and $Scope -ne [EnvironmentVariableTarget]::Process)
        {
            $writeError = $true
            return
        }

        if ($seenScopes.Contains($Scope))
        {
            return
        }

        $Scope | Write-Output
        [void]$seenScopes.Add($Scope)
    }

    end
    {
        # Operate on process-level environment variables by default, if the user specifies no scope.
        if ($receivedCount -eq 0)
        {
            return [EnvironmentVariableTarget]::Process
        }

        if ($writeError)
        {
            if (-not $Message)
            {
                $Message = 'PowerShell and .NET only support user-level and computer-level environment variables on ' +
                           'Windows.'
            }
            Write-Error -Message $Message -ErrorAction $ErrorActionPreference
        }
    }

}