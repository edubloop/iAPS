#!/usr/bin/env bash
set -euo pipefail

BUNDLER_VERSION="2.7.2"

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
