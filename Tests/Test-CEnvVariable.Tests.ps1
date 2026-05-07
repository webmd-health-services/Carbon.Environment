
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon.Environment' -Resolve) -Verbose:$false

    $script:varNamePrefix = 'CARBON_SETENVVAR_TEST_'
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function GivenEnvVar
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [EnvironmentVariableTarget] $AtScope,

            [pscredential] $ForUser
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

        Set-CEnvVariable -Name $Named -Value $PSBoundParameters['Named'] @setArgs
    }


    function ThenError
    {
        param(
            [switch] $IsEmpty
        )

        if ($IsEmpty)
        {
            $Global:Error | Should -BeNullOrEmpty
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
    & {
            [Environment]::GetEnvironmentVariables('Process').Keys
            [Environment]::GetEnvironmentVariables('User').Keys
            if (Test-TCRunAsElevated)
            {
                [Environment]::GetEnvironmentVariables('Machine').Keys
            }
        } |
        Where-Object { $_ -like "${script:varNamePrefix}*" } |
        Select-Object -Unique |
        ForEach-Object {
            if (Test-TCRunAsElevated)
            {
                [Environment]::SetEnvironmentVariable($_, [NullString]::Value, 'Machine')
            }

            [Environment]::SetEnvironmentVariable($_, [NullString]::Value, 'User')
            [Environment]::SetEnvironmentVariable($_, [NullString]::Value, 'Process')
        }
}

Describe 'Test-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context '<_>-level' -ForEach @('Process', 'User', 'Machine') {
        It 'returns true' -ForEach $_ {
            [Environment]::GetEnvironmentVariables($_).Keys |
                Test-CEnvVariable -Scope $_ |
                Should -BeTrue
            ThenError -IsEmpty
        }
    }

    Context 'when environment variable does not exist' {
        It 'returns false' {
            WhenTesting 'NonExistentVar' | Should -BeFalse
            ThenError -IsEmpty
        }
    }

    It 'can check at specific scope' {
        $name = '003'
        GivenEnvVar $name -AtScope User
        WhenTesting $name -WithArgs @{ Scope = 'Process' } | Should -BeFalse
        WhenTesting $name -WithArgs @{ Scope = 'User' } | Should -BeTrue
        WhenTesting $name -WithArgs @{ Scope = 'Machine' } | Should -BeFalse
        ThenError -IsEmpty
    }

    It 'checks at process scope by default' {
        $name = '004'
        GivenEnvVar $name -AtScope User
        WhenTesting $name | Should -BeFalse
        WhenTesting $name -WithArgs @{ Scope = 'User' } | Should -BeTrue
        ThenError -IsEmpty
    }

    It 'accepts pipeline input' {
        Get-ChildItem -Path 'env:' | Select-Object -ExpandProperty Name | Test-CEnvVariable | Should -BeTrue
        Get-ChildItem -Path 'env:' | Test-CEnvVariable | Should -BeTrue
        'IDoNotExist' | Test-CEnvVariable | Should -BeFalse
        ThenError -IsEmpty
    }

    It 'tests for specific user' {
        $name = '005'
        GivenEnvVar $name -ForUser $script:credentials
        WhenTesting $name -WithArgs @{ Credential = $script:credentials } | Should -BeTrue
        WhenTesting $name | Should -BeFalse
        WhenTesting $name -WithArgs @{ Scope = 'User' } | Should -BeFalse

        $envVars = Get-ChildItem -Path 'env:'
        $envVars | Test-CEnvVariable -Credential $script:credentials | Should -HaveCount $envVars.Count
        ThenError -IsEmpty
    }
}
