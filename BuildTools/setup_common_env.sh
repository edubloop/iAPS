#!/usr/bin/env bash
set -euo pipefail

# Read bundler version from Gemfile.lock if present; fall back to pinned version.
# To adopt Gemfile.lock: run `bundle lock` locally, commit Gemfile.lock, and
# this script will auto-detect the required bundler version going forward.
BUNDLER_VERSION_FALLBACK="2.7.2"
if [ -f "Gemfile.lock" ] && grep -q "BUNDLED WITH" Gemfile.lock; then
  BUNDLER_VERSION=$(grep -A1 "BUNDLED WITH" Gemfile.lock | tail -1 | tr -d ' \r')
  echo "Detected Bundler ${BUNDLER_VERSION} from Gemfile.lock"
else
  BUNDLER_VERSION="${BUNDLER_VERSION_FALLBACK}"
  echo "No Gemfile.lock found; using pinned Bundler ${BUNDLER_VERSION}"
fi

echo "Installing Bundler ${BUNDLER_VERSION}"
gem install bundler -v "${BUNDLER_VERSION}"

if [ -n "${GITHUB_ENV:-}" ]; then
  echo "BUNDLER_VER=${BUNDLER_VERSION}" >> "${GITHUB_ENV}"
fi

echo "Patching Fastlane match table printer if present"
TABLE_PRINTER_PATH="$(ruby -e 'puts Gem::Specification.find_by_name("fastlane").gem_dir')/match/lib/match/table_printer.rb"

if [ -f "${TABLE_PRINTER_PATH}" ]; then
  sed -i "" "/puts(Terminal::Table.new(params))/d" "${TABLE_PRINTER_PATH}"
else
  echo "Warning: table_printer.rb not found, continuing"
fi

echo "Installing Ruby dependencies"
bundle _${BUNDLER_VERSION}_ install
