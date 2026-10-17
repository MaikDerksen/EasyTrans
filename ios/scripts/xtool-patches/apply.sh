#!/usr/bin/env bash
# Adds `xtool sign` (offline signing for a given UDID) to the xtool checkout. Idempotent.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
cd "$HOME/build/xtool-src/Sources"

cp "$HERE/SignCommand.swift" XToolSupport/SignCommand.swift

# Register the command next to `install`.
grep -q 'SignCommand.self' XToolSupport/XTool.swift ||
  sed -i 's/^\(\s*\)InstallCommand.self,/\1InstallCommand.self,\n\1SignCommand.self,/' XToolSupport/XTool.swift

# TargetDevice needs a public init to be created outside XKit.
grep -q 'public init(udid: String, name: String)' XKit/Signer/SigningContext.swift ||
  sed -i 's/^\(\s*\)public var name: String$/&\n\n\1public init(udid: String, name: String) {\n\1    self.udid = udid\n\1    self.name = name\n\1}/' XKit/Signer/SigningContext.swift

grep -n 'SignCommand' XToolSupport/XTool.swift
sed -n 12,25p XKit/Signer/SigningContext.swift
