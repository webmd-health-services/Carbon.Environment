
# Carbon.Environment Changelog

## 1.0.0

### Upgrade Instructions

If migrating from Carbon:

* Rename usages of `Remove-CEnvironmentVariable` with `Remove-CEnvVariable`.
* Rename usages of `Set-CEnvironmentVariable` with `Set-CEnvVariable`.

### Added

* `Remove-CEnvVariable` for removing environment variables. Migrated from Carbon's `Remove-CEnvironmentVariable`.
* `Set-CEnvVariable` for setting environment variables. Migrated from Carbon's `Set-CEnvironmentVariable`.
* `Test-CEnvVariable` for testing if an environment variable exists.
