# frozen_string_literal: true

require_relative 'capability_gate/version'
require_relative 'capability_gate/prerequisite'
require_relative 'capability_gate/capability'
require_relative 'capability_gate/grant'
require_relative 'capability_gate/evaluation_result'
require_relative 'capability_gate/registry'
require_relative 'capability_gate/prerequisites/check_result'
require_relative 'capability_gate/prerequisites/file_exists_checker'
require_relative 'capability_gate/prerequisites/config_value_checker'
require_relative 'capability_gate/prerequisites/checker'
require_relative 'capability_gate/evaluator'

module Wild
  module CapabilityGate
  end
end
