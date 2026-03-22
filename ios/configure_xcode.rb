require 'xcodeproj'

# This script helps configure the Xcode project for NDI SDK integration.
# Run this on a Mac after downloading the NDI SDK.

project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Runner' }

# 1. Add NDI Bridge Header
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runner/NDI-Bridging-Header.h'
  config.build_settings['HEADER_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/NDISDK/include'
  config.build_settings['LIBRARY_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/NDISDK/lib'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
end

# 2. Add Swift files if not already in the project
# Note: Runner/ usually includes all files in it by default if they are in the folder,
# but sometimes manual addition is needed.
group = project.main_group.find_subpath('Runner', true)
files = ['NDIManager.swift', 'NDIView.swift', 'NDI-Bridging-Header.h']

files.each do |f|
  file_ref = group.find_file_by_path(f)
  if file_ref.nil?
    file_ref = group.new_file(f)
    target.source_build_phase.add_file_reference(file_ref) unless f.end_with?('.h')
  end
end

['VideoToolbox.framework', 'AudioToolbox.framework', 'CoreMedia.framework', 'CoreVideo.framework'].each do |framework|
  path = "System/Library/Frameworks/#{framework}"
  file_ref = project.frameworks_group.find_file_by_path(framework) || project.frameworks_group.new_file(path, :developer_dir)
  target.frameworks_build_phase.add_file_reference(file_ref)
end

project.save
puts "✅ Xcode project configured for NDI SDK integration."
