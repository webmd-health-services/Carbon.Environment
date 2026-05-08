
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

Describe 'Set-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context 'Windows' -Skip:(-not $IsWindows) {
        Context '<_>-level' -ForEach 'Machine','User','Process' {
            $skip = $_ -eq 'Machine' -and -not (Test-TCRunAsElevated)
            It 'creates variable' -ForEach $_ -Skip:$skip {
                $name = "${_}_000"
                WhenSetting $name -WithArgs @{ Value = $name ; Scope = $_ }
                ThenEnvVar $name -Exists -AtScope $_ -WithValue $name
                ThenError -IsEmpty
            }

            It 'overwrites value' -ForEach $_ -Skip:$skip {
                $name = "${_}_010"
                GivenEnvVar $name -WithValue 'old value' -AtScope $_
                WhenSetting $name -WithArgs @{ Value = $name ; Scope = $_ }
                ThenEnvVar $name -Exists -AtScope $_ -WithValue $name
                ThenError -IsEmpty
            }
        }

        It 'sets variable for another user' {
            $name = '020'
            WhenSetting $name -WithArgs @{ Value = $name ; Credential = $script:credentials }
            ThenEnvVar $name -Not -Exists -AtScope 'Process','User','Machine'
            ThenEnvVar $name -Exists -ForUser $script:credentials -WithValue $name
        }

        It 'sets multiple scopes' {
            $name = '030'
            WhenSetting $name -WithArgs @{ Value = $name ; Scope = @('Process', 'User') }
            ThenEnvVar $name -Exists -AtScope Process -WithValue $name
            ThenEnvVar $name -Exists -AtScope User -WithValue $name
        }

        It 'sets at distinct scopes' {
            $name = '040'
            WhenSetting $name -WithArgs @{ Value = "PROCESS_${name}" ; Scope = 'Process' }
            WhenSetting $name -WithArgs @{ Value = "USER_${name}" ; Scope = 'User' }
            ThenEnvVar $name -Exists -AtScope Process -WithValue "PROCESS_${name}"
            ThenEnvVar $name -Exists -AtScope User -WithValue "USER_${name}"
        }

    }

    Context 'Linux and macOS' -Skip:$IsWindows {
        Context '<_>-level' -ForEach @('User', 'Machine') {
            It 'fails' -ForEach $_ {
                WhenSetting 'does not matter' `
                            -WithArgs @{ Value = 'does not matter' ; Scope = $_ ; ErrorAction = 'SilentlyContinue' }
                ThenError -Matches 'only support .* on Windows' -HasCount 1
            }
        }
        Context 'Process-level' {
            It 'creates variable' {
                $name = '050'
                ThenEnvVar $name -Not -Exists -AtScope Process
                WhenSetting $name -WithArgs @{ Value = $name ; Scope = 'Process' }
                ThenEnvVar $name -AtScope Process -Exists -WithValue $name
                ThenError -IsEmpty
            }
            It 'overwrites value' {
                $name = '060'
                GivenEnvVar $name -WithValue 'old value' -AtScope Process
                WhenSetting $name -WithArgs @{ Value = $name ; Scope = 'Process' }
                ThenEnvVar $name -Exists -AtScope Process -WithValue $name
                ThenError -IsEmpty
            }
        }

        It 'does not set variable for another user' {
            $setArgs =
                @{ Value = 'does not matter' ; Credential = $script:credentials ; ErrorAction = 'SilentlyContinue' }
            WhenSetting 'does not matter' -WithArgs $setArgs
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }

        It 'only sets at process scope' {
            $name = '070'
            $setArgs = @{ Value = $name ; Scope = 'Process', 'User', 'Machine' ; ErrorAction = 'SilentlyContinue' }
            WhenSetting $name -WithArgs $setArgs
            ThenEnvVar $name -Exists -AtScope Process -WithValue $name
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }
    }

    It 'supports WhatIf' {
        $name = '080'
        WhenSetting $name -WithArgs @{ Value = 'neverset' ; WhatIf = $true }
        ThenEnvVar $name -Not -Exists -AtScope 'Process','User','Machine'
        ThenError -IsEmpty
    }

    It 'hides value in information message' {
        $name = '090'
        $value = '~!@#$%^&*()_+'
        WhenSetting $name -WithArgs @{ Value = $value ; Sensitive = $true } -InformationVariable 'infoMsgs'
        ThenEnvVar $name -Exists -AtScope Process -WithValue $value
        $infoMsgs | Should -Not -BeNullOrEmpty
        $infoMsgs[0].MessageData | Should -Not -Match ([regex]::Escape($value))
    }

    It 'allows empty string values' {
        $name = '100'
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
        $name = '110'
        GivenEnvVar $name -WithValue $name
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
        WhenSetting $name -WithArgs @{ Value = $name } -InformationVariable 'infoMsgs'
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
        $infoMsgs | Should -BeNullOrEmpty
    }

    It 'sets at process scope by default' {
        $name = '120'
        WhenSetting $name -WithArgs @{ Value = $name }
        ThenEnvVar $name -Exists -AtScope Process -WithValue $name
    }
}
