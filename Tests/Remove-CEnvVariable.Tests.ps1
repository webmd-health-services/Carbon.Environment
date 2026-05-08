
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

        if ($null -ne $AtScope)
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

Describe 'Remove-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context '<_>-level' -ForEach 'Machine','User','Process' {
        $scope = $_
        $skip = $scope -eq 'Machine' -and -not (Test-TCRunAsElevated)
        It 'removes variable' -ForEach $scope -Skip:$skip {
            $name = "${_}_001"
            GivenEnvVar $name -AtScope $_
            WhenRemoving $name -WithArgs @{ Scope = $_ }
            ThenEnvVar $name -AtScope $_ -Not -Exists
            ThenError -IsEmpty
        }
    }

    It 'fails if variable does not exist' {
        WhenRemoving '002' -WithArgs @{ ErrorAction = 'SilentlyContinue' }
        ThenError -Not -IsEmpty
        ThenError -MatchesRegex 'does not exist'
    }

    It 'ignores failures' {
        WhenRemoving '003' -withArgs @{ ErrorAction = 'Ignore' }
        ThenError -IsEmpty
    }

    It 'supports WhatIf' {
        $name = '004'
        GivenEnvVar $name
        WhenRemoving $name -WithArgs @{ WhatIf = $true }
        ThenEnvVar $name -Exists -AtScope Process
    }

    It 'removes from multiple scopes' {
        $name = '005'
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

    It 'removes at process scope by default' {
        $name = '006'
        GivenEnvVar $name -AtScope Process
        WhenRemoving $name
        ThenEnvVar $name -AtScope Process -Not -Exists
    }

    It 'removes variable for another user' {
        $name = '007'
        GivenEnvVar $name -ForUser $script:credentials
        GivenEnvVar $name -AtScope Process
        WhenRemoving $name -WithArgs @{ Credential = $script:credentials }
        ThenEnvVar $name -ForUser $script:credentials -Not -Exists
        ThenEnvVar $name -AtScope Process -Exists
    }

    It 'accepts pipeline input' {
        $name = "${script:varNamePrefix}008"
        $name2 = "${script:varNamePrefix}009"
        GivenEnvVar $name
        GivenEnvVar $name2
        $name, $name2 | Remove-CEnvVariable
        ThenEnvVar $name -AtScope Process -Not -Exists
        ThenEnvVar $name2 -AtScope Process -Not -Exists
    }

    It 'accepts multiple names' {
        $name = '010'
        $name2 = '011'
        GivenEnvVar $name
        GivenEnvVar $name2
        WhenRemoving $name,$name2
        ThenEnvVar $name -AtScope Process -Not -Exists
        ThenEnvVar $name2 -AtScope Process -Not -Exists
    }
}