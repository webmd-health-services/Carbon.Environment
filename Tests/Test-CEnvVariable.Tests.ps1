
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

    $script:varNamePrefix = "CARBON_TESTENVVAR_TEST_$($PSVersionTable['PSEdition'])_"
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function GivenEnvVar
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [EnvironmentVariableTarget] $AtScope,

            [pscredential] $ForUser,

            [String] $WithValue
        )

        $Named = "${script:varNamePrefix}${Named}"

        $setArgs = @{ }
        if ($ForUser)
        {
            $setArgs['Credential'] = $ForUser
        }
        elseif ($PSBoundParameters.ContainsKey('AtScope'))
        {
            $setArgs['Scope'] = $AtScope
        }

        $value = $PSBoundParameters['Named']
        if ($PSBoundParameters.ContainsKey('WithValue'))
        {
            $value = $WithValue
        }

        Set-CEnvVariable -Name $Named -Value $value @setArgs
    }


    function ThenError
    {
        [CmdletBinding()]
        param(
            [switch] $IsEmpty,

            [String] $MatchesRegex,

            [int] $HasCount
        )

        if ($IsEmpty)
        {
            $Global:Error | Should -BeNullOrEmpty
        }

        if ($MatchesRegex)
        {
            $Global:Error | Should -Match $MatchesRegex
        }

        if ($PSBoundParameters.ContainsKey('HasCount'))
        {
            $Global:Error | Should -HaveCount $HasCount
        }
    }

    function WhenTesting
    {
        param(
            [String] $Named,

            [hashtable] $WithArgs = @{}
        )

        Test-CEnvVariable -Name "${script:varNamePrefix}${Named}" @WithArgs
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

Describe 'Test-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context 'Windows' -Skip:(-not $IsWindows) {
        Context '<_>-level' -ForEach @('Process', 'User', 'Machine') {
            It 'returns true' -ForEach $_ {
                $scope = $_
                [Environment]::GetEnvironmentVariables($scope).Keys |
                    # If VSCODE_GIT_ASKPASS_EXTRA_ARGS env var's value is empty, it's value comes back as `$null` when
                    # run under Pester.
                    Where-Object { $_ -ne 'VSCODE_GIT_ASKPASS_EXTRA_ARGS' } |
                    Test-CEnvVariable -Scope $scope |
                    Should -BeTrue
                ThenError -IsEmpty
            }
        }

        It 'can check at specific scope' {
            $name = '010'
            GivenEnvVar $name -AtScope User
            WhenTesting $name -WithArgs @{ Scope = 'Process' } | Should -BeFalse
            WhenTesting $name -WithArgs @{ Scope = 'User' } | Should -BeTrue
            WhenTesting $name -WithArgs @{ Scope = 'Machine' } | Should -BeFalse
            ThenError -IsEmpty
        }

        It 'tests for specific user' {
            $name = '020'
            GivenEnvVar $name -ForUser $script:credentials
            WhenTesting $name -WithArgs @{ Credential = $script:credentials } | Should -BeTrue
            WhenTesting $name | Should -BeFalse
            WhenTesting $name -WithArgs @{ Scope = 'User' } | Should -BeFalse

            $envVars = Get-ChildItem -Path 'env:'
            $envVars | Test-CEnvVariable -Credential $script:credentials | Should -HaveCount $envVars.Count
            ThenError -IsEmpty
        }
    }

    Context 'Linux and macOS' -Skip:$IsWindows {
        Context '<_>-level' -ForEach @('User', 'Machine') {
            It 'returns nothing and writes an error' -ForEach $_ {
                [Environment]::GetEnvironmentVariables($_).Keys |
                    Test-CEnvVariable -Scope $_ -ErrorAction SilentlyContinue |
                    Should -BeNullOrEmpty
                ThenError -Matches 'only support .* on Windows' -HasCount 1
            }
        }

        It 'does not support testing a specific user''s variables' {
            $name = '040'
            WhenTesting $name -WithArgs @{ Credential = $script:credentials ; ErrorAction = 'SilentlyContinue' } |
                Should -HaveCount 0
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }
    }

    Context 'when environment variable does not exist' {
        It 'returns false' {
            WhenTesting 'NonExistentVar' | Should -BeFalse
            ThenError -IsEmpty
        }
    }

    It 'checks at process scope by default' {
        $name = '060'
        GivenEnvVar $name -AtScope Process
        WhenTesting $name | Should -BeTrue
        ThenError -IsEmpty
    }

    It 'accepts pipeline input' {
        Get-ChildItem -Path 'env:' | Select-Object -ExpandProperty Name | Test-CEnvVariable | Should -BeTrue
        Get-ChildItem -Path 'env:' | Test-CEnvVariable | Should -BeTrue
        'IDoNotExist' | Test-CEnvVariable | Should -BeFalse
        ThenError -IsEmpty
    }

    Context 'is a list' {
        It 'finds an item' {
            $paths = Split-CEnvVariable -Name 'PATH'
            foreach ($path in $paths)
            {
                Test-CEnvVariable -Name 'PATH' -Item $path | Should -BeTrue
            }
        }

        It 'does not find an item' {
            Test-CEnvVariable -Name 'PATH' -Item 'SomePathThatDoesNotExist' | Should -BeFalse
        }

        It 'uses custom separator' {
            $firstPath = Split-CEnvVariable -Name 'PATH' | Select-Object -First 1
            Test-CEnvVariable -Name 'PATH' -Item $firstPath -Separator '|' | Should -BeFalse
            Test-CEnvVariable -Name 'PATH' -Item $firstPath | Should -BeTrue

            $name = '100'
            GivenEnvVar $name -AtScope Process -WithValue 'a|b|c|d'
            WhenTesting $name -WithArgs @{ Item = 'd' ; Separator = '|' } | Should -BeTrue
            WhenTesting $name -WithArgs @{ Item = 'e' ; Separator = '|' } | Should -BeFalse
        }
    }

}
