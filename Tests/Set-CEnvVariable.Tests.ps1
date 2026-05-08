
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

    $script:varNamePrefix = 'CARBON_SETENVVAR_TEST_'
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function GivenEnvVar
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [Parameter(Mandatory)]
            [String] $WithValue,

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

        Set-CEnvVariable -Name $Named -Value $WithValue @setArgs
    }

    function ThenEnvVar
    {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory, Position=0)]
            [String] $Named,
            [switch] $Not,
            [switch] $Exists,
            [String] $WithValue,
            [Parameter(Mandatory, ParameterSetName='ForUser')]
            [pscredential] $ForUser,
            [Parameter(Mandatory, ParameterSetName='AtScope')]
            [EnvironmentVariableTarget[]] $AtScope
        )

        $Named = "${script:varNamePrefix}${Named}"

        foreach ($scope in $AtScope)
        {
            if ($ForUser)
            {
                Start-Job { [Environment]::GetEnvironmentVariable($using:Named, 'User') } -Credential $ForUser |
                    Receive-Job -Wait -AutoRemoveJob |
                    Should -Not:$Not -Be $WithValue
            }
            else
            {
                foreach ($_scope in $AtScope)
                {
                    [Environment]::GetEnvironmentVariable($Named, $_scope) | Should -Not:$Not -Be $WithValue
                }
            }

        }
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

    function WhenSetting
    {
        [CmdletBinding()]
        param(
            [String] $Named,

            [hashtable] $WithArgs = @{}
        )

        $Named = "${script:varNamePrefix}${Named}"
        Set-CEnvVariable -Name $Named @WithArgs
    }
}

AfterAll {
    $scopes = @('Process','User')
    & {
            [Environment]::GetEnvironmentVariables('Process').Keys
            [Environment]::GetEnvironmentVariables('User').Keys
            if (Test-TCRunAsElevated)
            {
                [Environment]::GetEnvironmentVariables('Machine').Keys
                $scopes += 'Machine'
            }
        } |
        Where-Object { $_ -like "${script:varNamePrefix}*" } |
        Uninstall-CEnvVariable -Scope $scopes
}

Describe 'Set-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context '<_>-level' -ForEach 'Machine','User','Process' {
        $scope = $_
        $skip = $scope -eq 'Machine' -and -not (Test-TCRunAsElevated)
        It 'creates variable' -ForEach $scope -Skip:$skip {
            $name = "${_}_001"
            WhenSetting $name -WithArgs @{ Value = $name ; Scope = $_ }
            ThenEnvVar $name -Exists -AtScope $_ -WithValue $name
            ThenError -IsEmpty
        }

        It 'overwrites existing variable' -ForEach $scope -Skip:$skip {
            $name = "${_}_002"
            GivenEnvVar $name -WithValue 'old value' -AtScope $_
            WhenSetting $name -WithArgs @{ Value = $name ; Scope = $_ }
            ThenEnvVar $name -Exists -AtScope $_ -WithValue $name
            ThenError -IsEmpty
        }
    }

    It 'supports WhatIf' {
        $name = '003'
        WhenSetting $name -WithArgs @{ Value = 'neverset' ; WhatIf = $true }
        ThenEnvVar $name -Not -Exists -AtScope 'Process','User','Machine'
        ThenError -IsEmpty
    }

    It 'sets variable for another user' {
        $name = '004'
        WhenSetting $name -WithArgs @{ Value = $name ; Credential = $script:credentials }
        ThenEnvVar $name -Not -Exists -AtScope 'Process','User','Machine'
        ThenEnvVar $name -Exists -ForUser $script:credentials -WithValue $name
    }

    It 'hides value in information message' {
        $name = '005'
        $value = '~!@#$%^&*()_+'
        WhenSetting $name -WithArgs @{ Value = $value ; Sensitive = $true } -InformationVariable 'infoMsgs'
        ThenEnvVar $name -Exists -AtScope Process -WithValue $value
        $infoMsgs | Should -Not -BeNullOrEmpty
        $infoMsgs[0].MessageData | Should -Not -Match ([regex]::Escape($value))
    }

    It 'allows empty string values' {
        $name = '006'
        WhenSetting $name -WithArgs @{ Value = '' }
        # In .NET framework and .NET before 9, you couldn't set an enviironment variable to an empty string.
        if ([Environment]::Version -lt [Version]::New(9, 0))
        {
            ThenEnvVar $name -Not -Exists -AtScope Process,User,Machine
        }
        else
        {
            ThenEnvVar $name -Exists -AtScope Process -WithValue ''
        }
    }

    It 'does not set environment variable if value has not changed' {
        $name = '007'
        GivenEnvVar $name -WithValue $name
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
        WhenSetting $name -WithArgs @{ Value = $name } -InformationVariable 'infoMsgs'
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
        $infoMsgs | Should -BeNullOrEmpty
    }

    It 'sets multiple scopes' {
        $name = '008'
        WhenSetting $name -WithArgs @{ Value = $name ; Scope = @('Process', 'User') }
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
        ThenEnvVar $name -Exists -AtScope User -WithValue $name
    }

    It 'sets at distinct scopes' {
        $name = '009'
        WhenSetting $name -WithArgs @{ Value = "PROCESS_${name}" ; Scope = 'Process' }
        WhenSetting $name -WithArgs @{ Value = "USER_${name}" ; Scope = 'User' }
        ThenEnvVar $name -Exists -AtScope Process -WithValue "PROCESS_${name}"
        ThenEnvVar $name -Exists -AtScope User -WithValue "USER_${name}"
    }

    It 'sets at process scope by default' {
        $name = '010'
        WhenSetting $name -WithArgs @{ Value = $name }
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
    }
}
