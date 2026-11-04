# Frozen old-package audit

This root audits the old C923... installer and the local 9b66790bc7ea payload. All 16,428 declared owned files matched their hashes, Python's 55-file source set matched, and the new runtime DLLs matched actual entries of NuGet archives whose content hashes were verified using the SDK's NuGet.Packaging API.

The first Python checker incorrectly compared raw signed ZIP SHA512 with NuGet lock contentHash. Those false values are retained but are not valid package-mismatch verdicts; `nuget-content-review.json` uses the correct API and direct ZIP-entry byte checks. No dependency was declared incompatible based on the raw-ZIP comparison.

Thirty local PIL/psutil bytecode files were observed after the acceptance host imported those modules without disabling host bytecode. They are post-build local payload drift, not evidence about the bytes of the sealed installer. They were neither deleted nor added to its manifest.

The old package is rejected because Microsoft.Extensions-LICENSE.txt contained SDK terms rather than the package's declared MIT text. `license-finding.json` and `SUMMARY.json` preserve that conclusion. The implementation subsequently corrected the build source; a new unique package must be audited separately. This root will not be rewritten to make the old package pass.
