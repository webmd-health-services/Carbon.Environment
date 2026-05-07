# Overview

The Carbon.Environment PowerShell module configures and manages the current environment.

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
