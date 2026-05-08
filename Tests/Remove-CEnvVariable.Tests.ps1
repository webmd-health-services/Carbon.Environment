
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Carbon.Accounts' -Resolve) `
                  -Function @('Test-CRunAsElevated') `
                  -Prefix 'T' `
                  -Verbose:$false

    if (-not (Test-Path -Path 'variable:IsWindows'))
    {
        $script:IsWindows = $true
        $script:IsLinux = $script:IsMacOS = $false
    }
}

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon.Environment' -Resolve) -Verbose:$false

    $script:varNamePrefix = 'CARBON_REMOVEENVVAR_'
    $script:varName = ''
    $script:testNum = 0
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function GivenEnvVar
    {
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [EnvironmentVariableTarget[]] $AtScope,

            [pscredential] $ForUser
        )

        if (-not $Named.StartsWith($script:varNamePrefix))
        {
            $Named = "${script:varNamePrefix}${Named}"
        }

        $setArgs = @{}
        if ($ForUser)
        {
            $setArgs['Credential'] = $ForUser
        }
        elseif ($PSBoundParameters.ContainsKey('AtScope'))
        {
            $setArgs['Scope'] = $AtScope
        }
        Set-CEnvVariable -Name $Named -Value $PSBoundParameters['Named'] @setArgs
    }

    function ThenEnvVar
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position=0)]
            [String] $Named,
            [switch] $Not,
            [switch] $Exists,
            [Parameter(Mandatory, ParameterSetName='ForUser')]
            [pscredential] $ForUser,
            [Parameter(Mandatory, ParameterSetName='AtScope')]
            [EnvironmentVariableTarget] $AtScope
        )

        $Named = "${script:varNamePrefix}${Named}"

        foreach ($scope in $AtScope)
        {
            if ($ForUser)
            {
                Start-Job { $null -ne [Environment]::GetEnvironmentVariable($using:Named, $using:scope) } `
                          -Credential $ForUser | `
                    Receive-Job -Wait -AutoRemoveJob | `
                    Should -Not:$Not -BeTrue
            }
            else
            {
                Test-CEnvVariable -Name $Named -Scope $scope | Should -Not:$Not -BeTrue
            }

        }
    }

    function ThenError
    {
        [CmdletBinding()]
        param(
            [switch] $Not,

            [switch] $IsEmpty,

            [String] $MatchesRegex,

            [int] $HasCount
        )

        if ($IsEmpty)
        {
            $Global:Error | Should -Not:$Not -BeNullOrEmpty
        }

        if ($MatchesRegex)
        {
            $Global:Error | Should -Not:$Not -Match $MatchesRegex
        }

        if ($PSBoundParameters.ContainsKey('HasCount'))
        {
            $Global:Error | Should -HaveCount $HasCount
        }
    }

    function WhenRemoving
    {
        param(
            [String[]] $Named,
            [hashtable] $WithArgs = @{}
        )

        $Named =
            $Named |
            ForEach-Object {
                if ($_.StartsWith($script:varNamePrefix))
                {
                    return $_
                }
                return "${script:varNamePrefix}${_}"
            }

        Remove-CEnvVariable -Name $Named @WithArgs
    }
}

AfterAll {
    $scopes = @('Process')
    if ($IsWindows)
    {
        $scopes += @('User')
        if (Test-TCRunAsElevated)
        {
            $scopes += 'Machine'
        }
    }

    & {
            [Environment]::GetEnvironmentVariables('Process').Keys
            if ($IsWindows)
            {
                [Environment]::GetEnvironmentVariables('User').Keys
                if (Test-TCRunAsElevated)
                {
                    [Environment]::GetEnvironmentVariables('Machine').Keys
                }
            }
        } |
        Where-Object { $_ -like "${script:varNamePrefix}*" } |
        Uninstall-CEnvVariable -Scope $scopes
}

Describe 'Remove-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context 'Windows' -Skip:(-not $IsWindows) {
        Context '<_>-level' -ForEach 'Machine','User','Process' {
            $skip = $_ -eq 'Machine' -and -not (Test-TCRunAsElevated)
            It 'removes variable' -ForEach $_ -Skip:$skip {
                $name = "${_}_000"
                GivenEnvVar $name -AtScope $_
                WhenRemoving $name -WithArgs @{ Scope = $_ }
                ThenEnvVar $name -AtScope $_ -Not -Exists
                if ($IsWindows)
                {
                    ThenError -IsEmpty
                }
                else
                {
                    ThenError -Matches 'not supported'
                }
            }
        }

        It 'removes from multiple scopes' {
            $name = '010'
            GivenEnvVar $name -AtScope Process
            GivenEnvVar $name -AtScope User
            if (Test-TCRunAsElevated)
            {
                GivenEnvVar $name -AtScope Machine
            }
            $scopes = @('Process', 'User')
            if (Test-TCRunAsElevated)
            {
                $scopes += 'Machine'
            }

            WhenRemoving $name -WithArgs @{ Scope = $scopes }
            ThenEnvVar $name -AtScope Process -Not -Exists
            ThenEnvVar $name -AtScope User -Not -Exists
            ThenEnvVar $name -AtScope Machine -Not -Exists
        }

        It 'removes variable for another user' {
            $name = '020'
            GivenEnvVar $name -ForUser $script:credentials
            GivenEnvVar $name -AtScope Process
            WhenRemoving $name -WithArgs @{ Credential = $script:credentials }
            ThenEnvVar $name -ForUser $script:credentials -Not -Exists
            ThenEnvVar $name -AtScope Process -Exists
        }
    }

    Context 'Linux and macOS' -Skip:$IsWindows {
        Context '<_>-level' -ForEach @('User', 'Machine') {
            It 'fails' -ForEach $_ {
                WhenRemoving 'does not matter' -WithArgs @{ Scope = $_ ; ErrorAction = 'SilentlyContinue' }
                ThenError -Matches 'only support .* on Windows' -HasCount 1
            }
        }
        Context 'Process-level' {
            It 'removes variable' {
                $name = '030'
                GivenEnvVar $name -AtScope Process
                ThenEnvVar $name -AtScope Process -Exists
                WhenRemoving $name -WithArgs @{ Scope = 'Process' }
                ThenEnvVar $name -AtScope Process -Not -Exists
                ThenError -IsEmpty
            }
        }

        It 'only removes at process scope' {
            $name = '040'
            GivenEnvVar $name -AtScope Process
            WhenRemoving $name -WithArgs @{ Scope = 'Process','User','Machine' ; ErrorAction = 'SilentlyContinue' }
            ThenEnvVar $name -AtScope Process -Not -Exists
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }

        It 'does not support other user environment variables' {
            $name = '050'
            WhenRemoving $name -WithArgs @{ Credential = $script:credentials ; ErrorAction = 'SilentlyContinue' }
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }
    }

    Context 'variable does not exist' {
        It 'writes an error' {
            WhenRemoving '060' -WithArgs @{ ErrorAction = 'SilentlyContinue' }
            ThenError -Not -IsEmpty
            ThenError -MatchesRegex 'does not exist' -HasCount 1
        }
    }

    It 'ignores failures' {
        WhenRemoving '070' -withArgs @{ ErrorAction = 'Ignore' }
        ThenError -IsEmpty
    }

    It 'supports WhatIf' {
        $name = '080'
        GivenEnvVar $name
        WhenRemoving $name -WithArgs @{ WhatIf = $true }
        ThenEnvVar $name -Exists -AtScope Process
    }

    It 'removes at process scope by default' {
        $name = '090'
        GivenEnvVar $name -AtScope Process
        WhenRemoving $name
        ThenEnvVar $name -AtScope Process -Not -Exists
    }

    It 'accepts pipeline input' {
        $name = "${script:varNamePrefix}100"
        $name2 = "${script:varNamePrefix}101"
        GivenEnvVar $name
        GivenEnvVar $name2
        $name, $name2 | Remove-CEnvVariable
        ThenEnvVar $name -AtScope Process -Not -Exists
        ThenEnvVar $name2 -AtScope Process -Not -Exists
    }

    It 'accepts multiple names' {
        $name = '120'
        $name2 = '121'
        GivenEnvVar $name
        GivenEnvVar $name2
        WhenRemoving $name,$name2
        ThenEnvVar $name -AtScope Process -Not -Exists
        ThenEnvVar $name2 -AtScope Process -Not -Exists
    }
}