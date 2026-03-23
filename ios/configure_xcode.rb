require 'xcodeproj'

# This script helps configure the Xcode project for NDI SDK integration.
project_path = 'Runner.xcodeproj'
begin
  project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'Runner' }

# 1. Add NDI Bridge Header & Search Paths
target.build_configurations.each do |config|
  config.build_settings['SWIFT_OBJC_BRIDGING_HEADER'] = 'Runner/NDI-Bridging-Header.h'
  config.build_settings['HEADER_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/NDISDK/include'
  config.build_settings['LIBRARY_SEARCH_PATHS'] = '$(inherited) $(PROJECT_DIR)/NDISDK/lib'
  config.build_settings['ENABLE_BITCODE'] = 'NO'
end

# 2. Add Swift files to the project
group = project.main_group.find_subpath('Runner', true)
files = ['NDIManager.swift', 'NDIView.swift', 'NDI-Bridging-Header.h']

files.each do |f|
  file_ref = group.find_file_by_path(f)
  if file_ref.nil?
    file_ref = group.new_file(f)
    target.source_build_phase.add_file_reference(file_ref) unless f.end_with?('.h')
  end
end

# 3. Add Native iOS Frameworks (AJOUT DE ACCELERATE POUR NDI)
['VideoToolbox.framework', 'AudioToolbox.framework', 'CoreMedia.framework', 'CoreVideo.framework', 'Accelerate.framework'].each do |framework|
  path = "System/Library/Frameworks/#{framework}"
  file_ref = project.frameworks_group.find_file_by_path(framework) || project.frameworks_group.new_file(path, :developer_dir)
  target.frameworks_build_phase.add_file_reference(file_ref)
end

# 4. LINK NDI LIBRARY (Ajout crucial pour éviter le crash au build)
# Assure-toi que c'est bien le nom exact de ton fichier dans ios/NDISDK/lib/
ndi_lib_name = 'libndi_ios.a' 
ndi_lib_path = "NDISDK/lib/#{ndi_lib_name}"
ndi_file_ref = project.frameworks_group.find_file_by_path(ndi_lib_path) || project.frameworks_group.new_file(ndi_lib_path)
target.frameworks_build_phase.add_file_reference(ndi_file_ref)

project.save
puts "✅ Xcode project configured for NDI SDK integration."
rescue => e
  puts "❌ ERROR: Failed to configure Xcode project: #{e.message}"
  exit 1
end
