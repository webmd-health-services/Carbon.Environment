# Overview

The Carbon.Environment PowerShell module creates, sets, tests, and removes environment variables.

# System Requirements

* Windows PowerShell 5.1 and .NET 4.6.1+
* PowerShell Core 6+

# Installing

To install globally:

```powershell
Install-Module -Name 'Carbon.Environment'
Import-Module -Name 'Carbon.Environment'
```

To install privately:

```powershell
Save-Module -Name 'Carbon.Environment' -Path '.'
Import-Module -Name '.\Carbon.Environment'
```

# Commands

* `Remove-CEnvVariable` for removing existing environment variables.
* `Set-CEnvVariable` for creating or setting environment variables.
* `Test-CEnvVariable` for testing if an environment variable exists.
* `Uninstall-CEnvVariable` for removing environment variables, ignoring any that don't exist.