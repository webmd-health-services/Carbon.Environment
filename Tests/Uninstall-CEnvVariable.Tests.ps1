
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

    $script:varNamePrefix = "CARBON_UNINSTALLENVVAR_$($PSVersionTable['PSEdition'])_"
    $script:credentials = Import-Clixml -Path (Join-Path -Path $PSScriptRoot -ChildPath '..\.cenvironment' -Resolve)

    function GivenEnvVar
    {
        param(
            [Parameter(Mandatory)]
            [String] $Named,

            [EnvironmentVariableTarget] $AtScope,

            [pscredential] $ForUser,

            [String[]] $WithValue
        )

        if ($Named -notlike "${script:varNamePrefix}*")
        {
            $Named = "${script:varNamePrefix}${Named}"
        }

        $setArgs = @{ }
        if ($ForUser)
        {
            $setArgs['Credential'] = $ForUser
        }
        elseif ($PSBoundParameters.ContainsKey('AtScope'))
        {
            $setArgs['Scope'] = $AtScope
        }

        $value = $WithValue -join [IO.Path]::PathSeparator
        if (-not $PSBoundParameters.ContainsKey('WithValue'))
        {
            $value = $PSBoundParameters['Named']
        }

        Set-CEnvVariable -Name $Named -Value $value @setArgs
    }

    function ThenEnvVar
    {
        [CmdletBinding()]
        param(
            [String] $Named,
            [switch] $Not,
            [switch] $Exists,
            [pscredential] $ForUser,
            [EnvironmentVariableTarget[]] $AtScope,
            [String[]] $WithValue
        )

        if ($Named -notlike "${script:varNamePrefix}*")
        {
            $Named = "${script:varNamePrefix}${Named}"
        }

        if ($ForUser)
        {
            Start-Job { $null -ne [Environment]::GetEnvironmentVariable($using:Named, 'User') } -Credential $ForUser |
                Receive-Job -Wait -AutoRemoveJob |
                Should -Not:$Not -BeTrue
            return
        }

        $expectedValue = $WithValue -join [IO.Path]::PathSeparator
        foreach ($scope in $AtScope)
        {
            Test-CEnvVariable -Name $Named -Scope $scope | Should -Not:$Not -BeTrue
            if ($PSBoundParameters.ContainsKey('WithValue'))
            {
                [Environment]::GetEnvironmentVariable($Named, $scope) | Should -Be $expectedValue
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

    function WhenUninstalling
    {
        [CmdletBinding()]
        param(
            [String[]] $Named,

            [hashtable] $WithArgs = @{}
        )

        $Named =
            $Named |
            ForEach-Object {
                    if ($_ -notlike "${script:varNamePrefix}*")
                    {
                        "${script:varNamePrefix}${_}"
                    }
                    else
                    {
                        $_
                    }
                }
        Uninstall-CEnvVariable -Name $Named @WithArgs
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

Describe 'Uninstall-CEnvVariable' {
    BeforeEach {
        $Global:Error.Clear()
    }

    Context 'Windows' -Skip:(-not $IsWindows) {
        Context "<_>-level" -ForEach @('Process', 'User', 'Machine') {

            $skip = $_ -eq 'Machine' -and -not (Test-TCRunAsElevated)

            It 'removes variable' -Skip:$skip -ForEach $_ {
                $name = "${_}_000"
                GivenEnvVar $name -AtScope $_
                WhenUninstalling $name -WithArgs @{ Scope = $_ }
                ThenEnvVar $name -Not -Exists
            }

            It 'only removes variable at that scope' -Skip:$skip -ForEach $_ {
                $scope = $_
                $name = "${scope}_010"
                GivenEnvVar $name -AtScope Process
                GivenEnvVar $name -AtScope User
                if (Test-TCRunAsElevated)
                {
                    GivenEnvVar $name -AtScope Machine
                }
                WhenUninstalling $name -WithArgs @{ Scope = $scope }
                ThenEnvVar $name -Not:($scope -eq 'Process') -Exists -AtScope Process
                ThenEnvVar $name -Not:($scope -eq 'User') -Exists -AtScope User
                ThenEnvVar $name -Not:($scope -eq 'Machine' -or -not (Test-TCRunAsElevated)) -Exists -AtScope Machine
            }
        }

        It 'removes from multiple scopes' {
            $scopes = @('Process', 'User')
            if (Test-TCRunAsElevated)
            {
                $scopes += 'Machine'
            }
            $name = '020'
            foreach ($scope in $scopes)
            {
                GivenEnvVar $name -AtScope $scope
            }
            WhenUninstalling $name -WithArgs @{ Scope = $scopes }
            ThenEnvVar $name -Not -Exists
            ThenError -IsEmpty
        }

        It 'removes variable for another user' {
            $name = '030'
            GivenEnvVar $name -AtScope User
            GivenEnvVar $name -ForUser $script:credentials
            WhenUninstalling $name -WithArgs @{ Credential = $script:credentials }
            ThenEnvVar $name -Not -Exists -ForUser $script:credentials
            ThenEnvVar $name -Exists -AtScope User
            ThenError -IsEmpty
        }

        It 'removes only at specified scope' {
            $name = '040'
            GivenEnvVar $name -AtScope User
            WhenUninstalling $name -WithArgs @{}
            ThenEnvVar $name -Exists -AtScope User
            ThenEnvVar $name -Not -Exists -AtScope Process
        }
    }

    Context 'Linux and macOS' -Skip:$IsWindows {
        Context "<_>-level" -ForEach @('User', 'Machine') {
            It 'writes an error' -ForEach $_ {
                WhenUninstalling '050' -WithArgs @{ Scope = $_ ; ErrorAction = 'SilentlyContinue' }
                ThenError -Matches 'only support .* on Windows' -HasCount 1
            }
        }

        Context 'Process-level' {
            It 'removes variable' {
                $name = '060'
                GivenEnvVar $name -AtScope Process
                WhenUninstalling $name -WithArgs @{ Scope = 'Process' }
                ThenEnvVar $name -Not -Exists -AtScope Process
                ThenError -IsEmpty
            }
        }

        It 'still removes process-level variable when given unsupported scopes' {
            $scopes = @('Process', 'User', 'Machine')
            $name = '070'
            GivenEnvVar $name -AtScope Process
            WhenUninstalling $name -WithArgs @{ Scope = $scopes ; ErrorAction = 'SilentlyContinue' }
            ThenEnvVar $name -Not -Exists -AtScope Process
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }

        It 'does not support removing specfic user''s variables' {
            $name = '080'
            WhenUninstalling $name -WithArgs @{ Credential = $script:credentials ; ErrorAction = 'SilentlyContinue' }
            ThenError -Matches 'only support .* on Windows' -HasCount 1
        }
    }

    It 'ignores non-existent variable' {
        $name = '090'
        WhenUninstalling $name -WithArgs @{ Scope = 'Process' }
        ThenEnvVar $name -Not -Exists
        ThenError -IsEmpty
    }

    It 'supports WhatIf' {
        $name = '100'
        GivenEnvVar $name -AtScope Process
        WhenUninstalling $name -WithArgs @{ WhatIf = $true }
        ThenEnvVar $name -Exists -AtScope Process
        ThenError -IsEmpty
    }

    It 'accepts pipeline input' {
        $name = "${script:varNamePrefix}110"
        $name2 = "${script:varNamePrefix}111"
        GivenEnvVar $name
        GivenEnvVar $name2
        $name,$name2 | Uninstall-CEnvVariable
        ThenEnvVar $name -Not -Exists -AtScope Process
        ThenEnvVar $name2 -Not -Exists -AtScope Process
        ThenError -IsEmpty
    }

    It 'removes from process scope by default' {
        $name = '120'
        GivenEnvVar $name -AtScope Process
        ThenEnvVar $name -Exists -AtScope Process
        WhenUninstalling $name
        ThenEnvVar $name -Not -Exists -AtScope Process
    }

    It 'accepts array of names' {
        $name = '130'
        $name2 = '131'
        GivenEnvVar $name
        GivenEnvVar $name2
        WhenUninstalling $name,$name2
        ThenEnvVar $name -Not -Exists -AtScope Process
        ThenEnvVar $name2 -Not -Exists -AtScope Process
    }


    Context 'is a list' {
        It 'removes items' {
            $name = '140'
            GivenEnvVar $name -WithValue @('one', 'two', 'three', 'four')
            WhenUninstalling $name -WithArgs @{ Item = @('two', 'four') }
            ThenEnvVar $name -AtScope Process -Exists -WithValue @('one', 'three')
        }

        Context 'item does not exist' {
            It 'removes items that do exist' {
                $name = '150'
                GivenEnvVar $name -WithValue @('one', 'two', 'three')
                WhenUninstalling $name -WithArgs @{ Item = @('three', 'five', 'six') }
                ThenEnvVar $name -AtScope Process -Exists -WithValue @('one', 'two')
                ThenError -IsEmpty
            }

            It 'can exclude items from information message' {
                $name = '160'
                GivenEnvVar $name -WithValue @('one', 'two', 'three')
                WhenUninstalling $name `
                                 -WithArgs @{ Item = @('three') ; Sensitive = $true } `
                                 -InformationVariable 'infoMsgs'
                ThenEnvVar $name -AtScope Process -Exists -WithValue @('one', 'two')
                ThenError -IsEmpty
                $infoMsgs | Should -Not -Match 'three'
            }
        }

        It 'uses custom separator' {
            $name = '170'
            GivenEnvVar $name -WithValue '1|2|3|4'
            WhenUninstalling $name -WithArgs @{ Item = @('2', '3') ; Separator = '|'}
            ThenEnvVar $name -AtScope Process -Exists -WithValue '1|4'
            ThenError -IsEmpty
        }

        It 'supports WhatIf' {
            $name = '180'
            GivenEnvVar $name -WithValue @('a', 'b', 'c')
            WhenUninstalling $name -WithArgs @{ Item = 'b' ; WhatIf = $true }
            ThenEnvVar $name -AtScope Process -Exists -WithValue @('a', 'b', 'c')
            ThenError -IsEmpty
        }

        Context 'deleting all items from the list' {
            $allowsEmptyEnvVar = [Environment]::Version -ge ([Version]::New(9, 0))
            Context 'allows setting empty environment variables' -Skip:(-not $allowsEmptyEnvVar) {
                It 'does not delete the environment variable' {
                    $name = '190'
                    GivenEnvVar $name -WithValue @('e', 'f', 'g')
                    WhenUninstalling $name -WithArgs @{ Item = @('e', 'f', 'g') }
                    ThenEnvVar $name -AtScope PRocess -Exists -WithValue ''
                    ThenError -IsEmpty
                }
            }

            Context 'does not allow setting empty environment variables' -Skip:$allowsEmptyEnvVar {
                It 'deletes the environment variable' {
                    $name = '200'
                    GivenEnvVar $name -WithValue @('e', 'f', 'g')
                    WhenUninstalling $name -WithArgs @{ Item = @('e', 'f', 'g') }
                    ThenEnvVar $name -AtScope Process -Not -Exists
                    ThenError -IsEmpty
                }
            }
        }
    }
}
