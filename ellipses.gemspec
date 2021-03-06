# frozen_string_literal: true

$LOAD_PATH.push File.expand_path('lib', __dir__)

require 'ellipses/version'

Gem::Specification.new do |s|
  s.name        = 'ellipses'
  s.author      = 'Recai Oktaş'
  s.email       = 'roktas@gmail.com'
  s.license     = 'GPL-3.0-or-later'
  s.version     = Ellipses::VERSION.dup
  s.summary     = 'Ellipses'
  s.description = 'Ellipses'

  s.homepage      = 'https://alaturka.github.io/ellipses'
  s.files         = Dir['CHANGELOG.md', 'LICENSE.md', 'README.md', 'BENİOKU.md', 'ellipses.gemspec', 'lib/**/*']
  s.executables   = %w[src srv]
  s.require_paths = %w[lib]

  s.metadata['changelog_uri']     = 'https://github.com/alaturka/ellipses/blob/master/CHANGELOG.md'
  s.metadata['source_code_uri']   = 'https://github.com/alaturka/ellipses'
  s.metadata['bug_tracker_uri']   = 'https://github.com/alaturka/ellipses/issues'

  s.required_ruby_version = '>= 2.5.0' # rubocop:disable Gemspec/RequiredRubyVersion

  s.add_dependency 'dry-cli'
  s.add_dependency 'tomlrb'

  s.metadata = {
    'rubygems_mfa_required' => 'true'
  }
end
