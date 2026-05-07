
#Requires -Version 5.1
Set-StrictMode -Version 'Latest'

BeforeDiscovery {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\PSModules\Carbon.Accounts' -Resolve) `
                  -Function @('Test-CRunAsElevated') `
                  -Prefix 'T' `
                  -Verbose:$false

}

BeforeAll {
    Set-StrictMode -Version 'Latest'

    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '..\Carbon.Environment' -Resolve) -Verbose:$false

    $script:varName = ''
    $script:testNum = 0
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function Assert-NoTestEnvironmentVariableAt( $Scope )
    {
        $actualValue = [Environment]::GetEnvironmentVariable($script:varName, $Scope)
        $actualValue | Should -BeNullOrEmpty
    }

    function Set-TestEnvironmentVariable($Scope)
    {
        $EnvVarValue = [Guid]::NewGuid().ToString()
        [Environment]::SetEnvironmentVariable($script:varName, $EnvVarValue, $Scope)
        Set-Item -Path ('env:{0}' -f $script:varName) -Value $EnvVarValue

        $actualValue = [Environment]::GetEnvironmentVariable($script:varName, $Scope)
        $actualValue | Should -Be $EnvVarValue
        Test-Path -Path ('env:{0}' -f $script:varName) | Should -BeTrue

        return $EnvVarValue
    }

    function ThenError
    {
        param(
            [switch] $Not,

            [switch] $IsEmpty,

            [String] $MatchesRegex
        )

        if ($IsEmpty)
        {
            $Global:Error | Should -Not:$Not -BeNullOrEmpty
        }

        if ($MatchesRegex)
        {
            $Global:Error | Should -Not:$Not -Match $MatchesRegex
        }
    }
}

AfterAll {
    & {
            [Environment]::GetEnvironmentVariables('Process').Keys
            [Environment]::GetEnvironmentVariables('User').Keys
            [Environment]::GetEnvironmentVariables('Machine').Keys
        } |
        Where-Object { $_ -like 'CARBON_REMOVEENVVAR_TEST_*' } |
        Select-Object -Unique |
        ForEach-Object {
            $forComputerArg = @{}
            if (Test-TCRunAsElevated)
            {
                $forComputerArg['ForComputer'] = $true
            }
            Remove-CEnvVariable -Name $_ -ForProcess -ForUser @forComputerArg -ErrorAction Ignore
        }
}

Describe 'Remove-CEnvVariable' {
    BeforeEach {
        while ($true)
        {
            $script:testNum += 1
            $script:varName = "CARBON_REMOVEENVVAR_TEST_${script:testNum}"
            if (-not [Environment]::GetEnvironmentVariable($script:varName, 'Process') -and
                -not [Environment]::GetEnvironmentVariable($script:varName, 'User') -and
                -not [Environment]::GetEnvironmentVariable($script:varName, 'Machine') -and
                -not (Test-Path -Path "env:${script:varName}"))
            {
                break
            }
        }

        $Global:Error.Clear()
    }

    It 'removes computer-level variable' -Skip:(-not (Test-TCRunAsElevated)) {
        Set-TestEnvironmentVariable 'Machine'
        Remove-CEnvVariable -Name $script:varName -ForComputer
        Assert-NoTestEnvironmentVariableAt -Scope Machine
    }

    It 'removes user-level variable' {
        Set-TestEnvironmentVariable 'User'
        Remove-CEnvVariable -Name $script:varName -ForUser
        Assert-NoTestEnvironmentVariableAt -Scope User
    }

    It 'removes process-level variable' {
        Set-TestEnvironmentVariable 'Process'
        Remove-CEnvVariable -Name $script:varName -ForProcess
        Assert-NoTestEnvironmentVariableAt -Scope Process
    }

    Context '<_> scope' -ForEach 'Computer','User','Process' {
        $scope = $_
        $skip = $scope -eq 'Computer' -and -not (Test-TCRunAsElevated)
        It 'removes variable with the Force' -ForEach $scope -Skip:$skip {
            $scope = $_
            $setScope = $scope
            if( $scope -eq 'Computer' )
            {
                $setScope = 'Machine'
            }
            Set-TestEnvironmentVariable $setScope
            $scopeParam = @{
                                ('For{0}' -f $scope) = $true
                        }
            Remove-CEnvVariable -Name $script:varName @scopeParam -Force
            Assert-NoTestEnvironmentVariableAt -Scope $setScope
            Test-Path -Path ('env:{0}' -f $script:varName) | Should -BeFalse
        }
    }

    It 'fails if variable does not exist' {
        Remove-CEnvVariable -Name 'IDoNotExist' -ForProcess -ErrorAction SilentlyContinue
        ThenError -Not -IsEmpty
        ThenError -MatchesRegex 'does not exist'
    }

    It 'ignores failures' {
        Remove-CEnvVariable -Name 'IDoNotExist' -ForProcess -ErrorAction Ignore
        ThenError -IsEmpty
    }

    It 'does not write an error when forcing removal at process scope' {
        Remove-CEnvVariable -Name 'IDoNotExist' -ForUser -Force -ErrorAction SilentlyContinue
        ThenError -Matches 'user-level'
        ThenError -Not -Matches 'process-level'
    }

    It 'supports WhatIf' {
        $envVarValue = Set-TestEnvironmentVariable -Scope Process

        Remove-CEnvVariable -Name $script:varName -ForProcess -WhatIf

        $actualValue = [Environment]::GetEnvironmentVariable($script:varName, 'Process')
        $actualValue | Should -Not -BeNullOrEmpty
        $envVarValue | Should -Be $actualValue
    }

    It 'removes from all scopes at once' {
        $value = [Guid]::NewGuid().ToString()
        $forComputerScopeArg = @{}
        if (Test-TCRunAsElevated)
        {
            $forComputerScopeArg['ForComputer'] = $true
        }

        Set-CEnvVariable -Name $script:varName -Value $value -ForProcess -ForUser @forComputerScopeArg
        Remove-CEnvVariable -Name $script:varName -ForProcess -ForUser @forComputerScopeArg
        Assert-NoTestEnvironmentVariableAt -Scope Machine
        Assert-NoTestEnvironmentVariableAt -Scope User
        Assert-NoTestEnvironmentVariableAt -Scope Process
    }

    It 'requires at least one scope' {
        Remove-CEnvVariable -Name $script:varName -ErrorAction SilentlyContinue
        $Global:Error | Should -Match 'target not specified'
    }

    It 'removes variable for another user' {
        $name = [Guid]::NewGuid().ToString()
        $value = [Guid]::NewGuid().ToString()
        Set-CEnvVariable -Name $name -Value $value -ForUser -Credential $script:credentials
        Remove-CEnvVariable -Name $name -ForUser -Credential $script:credentials
        $actualValue = $value
        $job = Start-Job -ScriptBlock {
            Get-Item -Path ('env:{0}' -f $using:name) -ErrorAction Ignore
        } -Credential $script:credentials
        $actualValue = $job | Wait-Job | Receive-Job
        $job | Remove-Job -Force -ErrorAction Ignore
        $actualValue | Should -BeNullOrEmpty
    }
}