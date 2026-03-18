# frozen_string_literal: true

require_relative 'lib/wild/capability_gate/version'

Gem::Specification.new do |spec|
  spec.name = 'wild-capability-gate'
  spec.version = Wild::CapabilityGate::VERSION
  spec.authors = ['Intent Solutions']
  spec.summary = 'Governed access control for sensitive AI tool capabilities'
  spec.description = 'Prerequisite-based capability gating for AI tool execution. ' \
                     'Fail-closed evaluation with audit logging and session-scoped state.'
  spec.homepage = 'https://github.com/jeremylongshore/wild-capability-gate'
  spec.license = 'Nonstandard'
  spec.required_ruby_version = '>= 3.2.0'

  spec.files = Dir['lib/**/*.rb', 'config/**/*.yml', 'LICENSE', 'README.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'yaml' # stdlib, declared explicitly for clarity

  spec.metadata['rubygems_mfa_required'] = 'true'
end
