
# Carbon.Environment Changelog

## 1.0.0

### Upgrade Instructions

If migrating from Carbon:

* Rename usages of `Remove-CEnvironmentVariable` with `Remove-CEnvVariable`.
* Rename usages of `Set-CEnvironmentVariable` with `Set-CEnvVariable`.
* `Remove-CEnvVariable` now writes an error if the environment variable to remove does not exist. Add `-ErrorAction
  Ignore` to ignore any errors
* `Set-CEnvVariable` now writes an information message when setting an environment variable. The message includes the
  value. To omit the value from the messages, use the new `Sensitive` switch.
* `Set-CEnvVariable` now allows empty strings for the variable's value. In PowerShel 7.4 and earlier, this will delete
  the variable. In PowerShell 7.5 and later, the variable will be created with an empty value. Make sure you're using
  `Remove-CEnvVariable` to delete environment variables.
* The `ForProcess`, `ForUser`, and `ForComputer` switches on `Remove-CEnvVariable` and `Set-CEnvVariable` replaced with
  a single `Scope` parameter. Replaces usages of `ForProcess` with `-Scope Process`. Replace usages of `ForUser` with
  `-Scope User`. Replace usages of `ForComputer` with `-Scope Machine`. Multiple scopes can be included, e.g. `-Scope
  Process,User,Machine`.
* Removes usages of the `Remove-CEnvVariable` and `Set-CEnvVariable` functions' `-Force` switch and replace them with
  including `Process` in the list of scopes passed to the `Scope` parameter.

### Added

* `Remove-CEnvVariable` for removing environment variables. Migrated from Carbon's `Remove-CEnvironmentVariable`.
* `Set-CEnvVariable` for setting environment variables. Migrated from Carbon's `Set-CEnvironmentVariable`.
* `Test-CEnvVariable` for testing if an environment variable exists.
* `Remove-CEnvVariable` accepts multiple environment names.
* `Remove-CEnvVariable` accepts names piped in.

### Changed

* `Remove-CEnvVariable` writes an error if an environment variable doesn't exist.
* `Remove-CEnvVariable` writes an information message for each environment variable it deletes.
* `Set-CEnvVariable` writes an information message for each environment variable it sets, including the variable's
  value. Use the `Sensitive` switch to omit the value from the information message.
* `Set-CEnvVariable`: can now set environment variables to empty strings in PowerShell 7.5 or later. In PowerShell 7.4
  and earlier, setting an environment variable to an empty string deletes it.

### Removed

This functionality was removed if you're migrating from Carbon.

* The `ForProcess`, `ForUser`, and `ForComputer` switches on `Remove-CEnvVariable` and `Set-CEnvVariable`. Use the new
  `Scope` parameter instead, which supports multiple scopes.
* The `Force` switch on `Remove-CEnvVariable` and `Set-CEnvVariable`. Instead, include `Process` in the list of scopes
  passed to the `Scope` parameter.