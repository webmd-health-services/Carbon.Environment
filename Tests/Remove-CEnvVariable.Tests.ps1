
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

    $script:varNamePrefix = "CARBON_REMOVEENVVAR_$($PSVersionTable['PSEdition'])_"
    $script:varName = ''
    $script:testNum = 0
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function GivenEnvVar
    {
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [String[]] $WithValue,

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

        $value = $PSBoundParameters['Named']
        if ($WithValue)
        {
            $value = $WithValue -join ([IO.Path]::PathSeparator)
        }

        Set-CEnvVariable -Name $Named -Value $value @setArgs
    }

    function ThenEnvVar
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position=0)]
            [String] $Named,
            [String[]] $WithValue,
            [switch] $Not,
            [switch] $Exists,
            [Parameter(Mandatory, ParameterSetName='ForUser')]
            [pscredential] $ForUser,
            [Parameter(Mandatory, ParameterSetName='AtScope')]
            [EnvironmentVariableTarget] $AtScope
        )

        $Named = "${script:varNamePrefix}${Named}"

        $expectedValue = $null
        if ($WithValue)
        {
            $expectedValue = $WithValue -join ([IO.Path]::PathSeparator)
        }

        foreach ($scope in $AtScope)
        {
            if ($ForUser)
            {
                $value =
                    Start-Job -ScriptBlock { [Environment]::GetEnvironmentVariable($using:Named, $using:scope) } `
                              -Credential $ForUser |
                        Receive-Job -Wait -AutoRemoveJob
                $value | Should -Not:$Not -BeNullOrEmpty
                if ($expectedValue)
                {
                    $value | Should -Not:$Not -Be $expectedValue
                }
            }
            else
            {
                if ($expectedValue)
                {
                    [Environment]::GetEnvironmentVariable($Named, $scope) | Should -Be $expectedValue
                }
                else
                {
                    Test-CEnvVariable -Name $Named -Scope $scope | Should -Not:$Not -BeTrue
                }
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
            ThenError -IsEmpty
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

    Context 'is a list' {
        It 'removes items' {
            $name = '130'
            GivenEnvVar $name -WithValue @('one', 'two', 'three', 'four')
            WhenRemoving $name -WithArgs @{ Item = @('two', 'four') }
            ThenEnvVar $name -AtScope Process -Exists -WithValue @('one', 'three')
        }

        Context 'item does not exist' {
            It 'writes an error and removes items that do exist' {
                $name = '140'
                GivenEnvVar $name -WithValue @('one', 'two', 'three')
                WhenRemoving $name -WithArgs @{ Item = @('three', 'five', 'six') ; ErrorAction = 'SilentlyContinue' }
                ThenEnvVar $name -AtScope Process -Exists -WithValue @('one', 'two')
                ThenError -Matches 'five.six.*items do not exist' -HasCount 1
            }

            It 'can exclude items from information message' {
                $name = '140'
                GivenEnvVar $name -WithValue @('one', 'two', 'three')
                WhenRemoving $name -WithArgs @{ Item = @('three', 'five', 'six') ; Sensitive = $true ; ErrorAction = 'SilentlyContinue' }
                ThenEnvVar $name -AtScope Process -Exists -WithValue @('one', 'two')
                ThenError -Matches 'sensitive items from.*the items do not exist' -HasCount 1
            }
        }

        It 'uses custom separator' {
            $name = '150'
            GivenEnvVar $name -WithValue '1|2|3|4'
            WhenRemoving $name -WithArgs @{ Item = @('2', '3') ; Separator = '|'}
            ThenEnvVar $name -AtScope Process -Exists -WithValue '1|4'
        }

        It 'supports WhatIf' {
            $name = '160'
            GivenEnvVar $name -WithValue @('a', 'b', 'c')
            WhenRemoving $name -WithArgs @{ Item = 'b' ; WhatIf = $true }
            ThenEnvVar $name -AtScope Process -Exists -WithValue @('a', 'b', 'c')
        }

        Context 'deleting all items from the list' {
            $allowsEmptyEnvVar = [Environment]::Version -ge ([Version]::New(9, 0))
            Context 'allows setting empty environment variables' -Skip:(-not $allowsEmptyEnvVar) {
                It 'does not delete the environment variable' {
                    $name = '170'
                    GivenEnvVar $name -WithValue @('e', 'f', 'g')
                    WhenRemoving $name -WithArgs @{ Item = @('e', 'f', 'g') }
                    ThenEnvVar $name -AtScope PRocess -Exists -WithValue ''
                }
            }

            Context 'does not allow setting empty environment variables' -Skip:$allowsEmptyEnvVar {
                It 'deletes the environment variable' {
                    $name = '180'
                    GivenEnvVar $name -WithValue @('e', 'f', 'g')
                    WhenRemoving $name -WithArgs @{ Item = @('e', 'f', 'g') }
                    ThenEnvVar $name -AtScope Process -Not -Exists
                }
            }
        }
    }
}