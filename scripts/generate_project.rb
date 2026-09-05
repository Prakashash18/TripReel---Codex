#!/usr/bin/env ruby

require 'xcodeproj'

ROOT = File.expand_path('..', __dir__)
PROJECT_PATH = File.join(ROOT, 'TripReel.xcodeproj')

project = Xcodeproj::Project.new(PROJECT_PATH, false, 60)
project.root_object.compatibility_version = 'Xcode 15.0'
project.root_object.attributes['LastSwiftUpdateCheck'] = '2660'
project.root_object.attributes['LastUpgradeCheck'] = '2660'

target = project.new_target(:application, 'TripReel', :ios, '17.0')
target.product_reference.name = 'TripReel.app'

unit_test_target = project.new_target(:unit_test_bundle, 'TripReelTests', :ios, '17.0')
ui_test_target = project.new_target(:ui_test_bundle, 'TripReelUITests', :ios, '17.0')
unit_test_target.add_dependency(target)
ui_test_target.add_dependency(target)

app_group = project.main_group.new_group('TripReel', 'TripReel')

Dir.glob(File.join(ROOT, 'TripReel/**/*.swift')).sort.each do |absolute_path|
  relative_path = absolute_path.delete_prefix(File.join(ROOT, 'TripReel/'))
  reference = app_group.new_file(relative_path)
  target.source_build_phase.add_file_reference(reference)
end

assets = app_group.new_file('Resources/Assets.xcassets')
target.resources_build_phase.add_file_reference(assets)

%w[InstrumentSerif-Regular.ttf InstrumentSerif-Italic.ttf].each do |font_name|
  font = app_group.new_file("Resources/Fonts/#{font_name}")
  target.resources_build_phase.add_file_reference(font)
end

app_group.new_file('Resources/Info.plist')
app_group.new_file('Resources/Fonts/OFL-InstrumentSerif.txt')

tests_group = project.main_group.new_group('TripReelTests', 'TripReelTests')
Dir.glob(File.join(ROOT, 'TripReelTests/**/*.swift')).sort.each do |absolute_path|
  relative_path = absolute_path.delete_prefix(File.join(ROOT, 'TripReelTests/'))
  reference = tests_group.new_file(relative_path)
  unit_test_target.source_build_phase.add_file_reference(reference)
end

ui_tests_group = project.main_group.new_group('TripReelUITests', 'TripReelUITests')
Dir.glob(File.join(ROOT, 'TripReelUITests/**/*.swift')).sort.each do |absolute_path|
  relative_path = absolute_path.delete_prefix(File.join(ROOT, 'TripReelUITests/'))
  reference = ui_tests_group.new_file(relative_path)
  ui_test_target.source_build_phase.add_file_reference(reference)
end

project.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['CLANG_ENABLE_MODULES'] = 'YES'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  settings['SDKROOT'] = 'iphoneos'
  settings['SWIFT_VERSION'] = '5.0'
end

target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['ASSETCATALOG_COMPILER_APPICON_NAME'] = 'AppIcon'
  settings['ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME'] = 'AccentColor'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['CURRENT_PROJECT_VERSION'] = '1'
  settings['DEVELOPMENT_TEAM'] = 'GT9EAB8826'
  settings['ENABLE_PREVIEWS'] = 'YES'
  settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  settings['INFOPLIST_FILE'] = 'TripReel/Resources/Info.plist'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  settings['LD_RUNPATH_SEARCH_PATHS'] = ['$(inherited)', '@executable_path/Frameworks']
  settings['MARKETING_VERSION'] = '1.0'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.prakashash18.tripreel'
  settings['PRODUCT_NAME'] = '$(TARGET_NAME)'
  settings['SUPPORTED_PLATFORMS'] = 'iphoneos iphonesimulator'
  settings['SUPPORTS_MACCATALYST'] = 'NO'
  settings['SWIFT_EMIT_LOC_STRINGS'] = 'YES'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
end

unit_test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['BUNDLE_LOADER'] = '$(TEST_HOST)'
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tripreel.tests'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
  settings['TEST_HOST'] = '$(BUILT_PRODUCTS_DIR)/TripReel.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/TripReel'
end

ui_test_target.build_configurations.each do |configuration|
  settings = configuration.build_settings
  settings['CODE_SIGN_STYLE'] = 'Automatic'
  settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
  settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.tripreel.uitests'
  settings['SWIFT_VERSION'] = '5.0'
  settings['TARGETED_DEVICE_FAMILY'] = '1'
  settings['TEST_TARGET_NAME'] = 'TripReel'
end

project.save

scheme = Xcodeproj::XCScheme.new
scheme.add_build_target(target)
scheme.set_launch_target(target)
scheme.add_test_target(unit_test_target)
scheme.add_test_target(ui_test_target)
scheme.save_as(project.path, 'TripReel', true)

puts "Generated #{PROJECT_PATH}"
