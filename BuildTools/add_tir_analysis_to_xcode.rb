#!/usr/bin/env ruby
# BuildTools/add_tir_analysis_to_xcode.rb
#
# Adds Track 1 TIRAnalysis files to the Xcode project targets.
# Run from any directory:
#   ruby BuildTools/add_tir_analysis_to_xcode.rb
#
# Requires: gem install xcodeproj

require 'xcodeproj'
require 'pathname'

PROJECT_PATH = File.expand_path('../FreeAPS.xcodeproj', __dir__)
REPO_ROOT    = File.expand_path('..', __dir__)

proj = Xcodeproj::Project.open(PROJECT_PATH)

app_target   = proj.targets.find { |t| t.name == 'FreeAPS' }
tests_target = proj.targets.find { |t| t.name == 'FreeAPSTests' }

abort 'Could not find FreeAPS target'      unless app_target
abort 'Could not find FreeAPSTests target' unless tests_target

# ──────────────────────────────────────────────────────────────────────────────
# 1. Source files — FreeAPS target
# ──────────────────────────────────────────────────────────────────────────────

modules_group = proj.main_group.find_subpath('FreeAPS/Sources/Modules', false)
abort 'Could not find FreeAPS/Sources/Modules group' unless modules_group

# Create TIRAnalysis group (sorted alphabetically it sits after Stat)
tir_group = modules_group.find_subpath('TIRAnalysis') ||
            modules_group.new_group('TIRAnalysis', 'TIRAnalysis')

engine_group = tir_group.find_subpath('Engine') ||
               tir_group.new_group('Engine', 'Engine')

# Module-level stubs
module_stubs = %w[
  TIRAnalysisDataFlow.swift
  TIRAnalysisProvider.swift
  TIRAnalysisStateModel.swift
]

# Engine files
engine_files = %w[
  TIRModels.swift
  ThresholdCrossingDetector.swift
  EventClassifier.swift
  TIRAnalysisEngine.swift
]

new_app_refs = []

module_stubs.each do |filename|
  abs = File.join(REPO_ROOT, 'FreeAPS/Sources/Modules/TIRAnalysis', filename)
  next unless File.exist?(abs)
  # Skip if already in group
  next if tir_group.children.any? { |c| c.path == filename }
  ref = tir_group.new_file(abs)
  new_app_refs << ref
  puts "  + TIRAnalysis/#{filename}"
end

engine_files.each do |filename|
  abs = File.join(REPO_ROOT, 'FreeAPS/Sources/Modules/TIRAnalysis/Engine', filename)
  next unless File.exist?(abs)
  next if engine_group.children.any? { |c| c.path == filename }
  ref = engine_group.new_file(abs)
  new_app_refs << ref
  puts "  + TIRAnalysis/Engine/#{filename}"
end

app_target.add_file_references(new_app_refs) unless new_app_refs.empty?
puts "Added #{new_app_refs.size} source file(s) to FreeAPS target"

# ──────────────────────────────────────────────────────────────────────────────
# 2. Test files — FreeAPSTests target
# ──────────────────────────────────────────────────────────────────────────────

tests_group = proj.main_group.find_subpath('FreeAPSTests', false)
abort 'Could not find FreeAPSTests group' unless tests_group

tir_tests_group = tests_group.find_subpath('TIRAnalysis') ||
                  tests_group.new_group('TIRAnalysis', 'TIRAnalysis')

test_files = %w[
  TIRThresholdCrossingDetectorTests.swift
  TIRAnalysisEngineTests.swift
]

new_test_refs = []

test_files.each do |filename|
  abs = File.join(REPO_ROOT, 'FreeAPSTests/TIRAnalysis', filename)
  next unless File.exist?(abs)
  next if tir_tests_group.children.any? { |c| c.path == filename }
  ref = tir_tests_group.new_file(abs)
  new_test_refs << ref
  puts "  + FreeAPSTests/TIRAnalysis/#{filename}"
end

tests_target.add_file_references(new_test_refs) unless new_test_refs.empty?
puts "Added #{new_test_refs.size} test file(s) to FreeAPSTests target"

# ──────────────────────────────────────────────────────────────────────────────
# 3. Save
# ──────────────────────────────────────────────────────────────────────────────

proj.save
puts "\nproject.pbxproj updated and saved."
