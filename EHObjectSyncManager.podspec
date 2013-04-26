Pod::Spec.new do |s|
  s.name         = 'EHObjectSyncManager'
  s.version      = '0.0.1'
  s.summary      = 'Leverages RestKit to observe managed object changes and automatically and transparently communicates them to a server.'
  s.homepage     = 'https://github.com/eric-horacek/EHObjectSyncManager'
  s.author       = { 'Eric Horacek' => 'horacek.eric@gmail.com' }
  s.license      = 'MIT'
  s.platform     = :ios, '5.0'
  
  s.source       = { :git => 'https://github.com/eric-horacek/EHObjectSyncManager.git', :tag => s.version.to_s }
  s.source_files = s.name.to_s + '/*.{h,m}'
  
  s.requires_arc = true

  s.dependency 'RestKit'
end
