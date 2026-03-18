# frozen_string_literal: true

module Wild
  module CapabilityGate
    # The core access decision engine.
    #
    # Given a caller identity and capability name, determines whether the caller
    # is granted that capability based on grants and prerequisite satisfaction.
    #
    # Decision tree (from 002-AT-STND-capability-model.md):
    # 1. Is capability known?            → No: DENY(unknown_capability)
    # 2. Is caller granted?              → No: DENY(not_granted)
    # 3. Are all prerequisites satisfied? → No: DENY(prerequisite_not_met)
    # 4. ALLOW
    #
    # See also: 003-TQ-STND-governance-model.md (fail-closed, no implicit grants)
    class Evaluator
      require_relative 'evaluator/grant_loader'

      def initialize(registry:, grants:)
        @registry = registry
        @grants = Array(grants).freeze
        freeze
      end

      def self.from_files(capabilities_path:, grants_path:)
        registry = Registry.from_file(capabilities_path)
        grants = GrantLoader.load_file(grants_path)
        new(registry: registry, grants: grants)
      end

      # Evaluate whether the caller is granted the named capability.
      # Context provides runtime values for prerequisite checks (e.g., config values).
      # Returns an EvaluationResult — always, never raises.
      def evaluate(caller_id:, capability_name:, context: {})
        capability_name = capability_name.to_sym
        caller_id = String(caller_id)

        check_capability_known(caller_id, capability_name) ||
          check_caller_granted(caller_id, capability_name) ||
          check_prerequisites(caller_id, capability_name, context) ||
          allow_with_prerequisites(caller_id, capability_name)
      end

      private

      def check_capability_known(caller_id, capability_name)
        return if @registry.known?(capability_name)

        EvaluationResult.denied(
          capability_name: capability_name, caller_id: caller_id,
          reason: :unknown_capability,
          details: "capability #{capability_name.inspect} is not registered"
        )
      end

      def check_caller_granted(caller_id, capability_name)
        return if @grants.any? { |g| g.matches_caller?(caller_id) && g.grants_capability?(capability_name) }

        EvaluationResult.denied(
          capability_name: capability_name, caller_id: caller_id,
          reason: :not_granted,
          details: "caller #{caller_id.inspect} is not granted #{capability_name.inspect}"
        )
      end

      def check_prerequisites(caller_id, capability_name, context)
        capability = @registry.fetch(capability_name)
        return if capability.prerequisites.empty?

        checker = Prerequisites::Checker.new(context: context)
        result = checker.check_all(capability.prerequisites)
        return if result.satisfied?

        EvaluationResult.denied(
          capability_name: capability_name, caller_id: caller_id,
          reason: :prerequisite_not_met,
          details: result.details
        )
      end

      def allow_with_prerequisites(caller_id, capability_name)
        capability = @registry.fetch(capability_name)
        checked = capability.prerequisites.map(&:type)

        EvaluationResult.allowed(
          capability_name: capability_name,
          caller_id: caller_id,
          prerequisites_checked: checked
        )
      end
    end
  end
end
