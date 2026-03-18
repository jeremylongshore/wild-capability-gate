# frozen_string_literal: true

require 'tempfile'
require 'fileutils'

RSpec.describe Wild::CapabilityGate::Evaluator do
  subject(:evaluator) do
    described_class.from_files(
      capabilities_path: capabilities_path,
      grants_path: grants_path
    )
  end

  let(:fixtures_dir) { File.expand_path('../../fixtures', __dir__) }
  let(:capabilities_path) { File.join(fixtures_dir, 'valid_capabilities.yml') }
  let(:grants_path) { File.join(fixtures_dir, 'valid_grants.yml') }

  describe '.from_files' do
    it 'loads from capability and grant config files' do
      expect(evaluator).to be_a(described_class)
      expect(evaluator).to be_frozen
    end
  end

  describe '#evaluate' do
    context 'when capability is unknown' do
      it 'denies with :unknown_capability reason' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :nonexistent_capability
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:unknown_capability)
        expect(result.details).to include('nonexistent_capability')
      end
    end

    context 'when caller is not granted the capability' do
      it 'denies with :not_granted reason' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :admin_tools
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:not_granted)
        expect(result.details).to include('introspection-agent')
        expect(result.details).to include('admin_tools')
      end
    end

    context 'when caller has no grants at all' do
      it 'uses wildcard grant if available for standard capabilities' do
        result = evaluator.evaluate(
          caller_id: 'service-account:unknown-agent',
          capability_name: :basic_introspection
        )

        expect(result).to be_allowed
      end

      it 'denies capabilities not in wildcard grant' do
        result = evaluator.evaluate(
          caller_id: 'service-account:unknown-agent',
          capability_name: :privileged_introspection
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:not_granted)
      end
    end

    context 'when caller is explicitly granted a standard capability (no prerequisites)' do
      it 'allows access' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :basic_introspection
        )

        expect(result).to be_allowed
        expect(result.capability_name).to eq(:basic_introspection)
        expect(result.caller_id).to eq('service-account:introspection-agent')
      end
    end

    context 'when caller is granted and prerequisites are satisfied' do
      let(:attestation_file) { Tempfile.new('safety-attestation') }

      after { attestation_file.close! }

      it 'allows privileged_introspection when attestation file exists' do
        # Use a capabilities config referencing a real temp file
        evaluator_with_prereqs = build_evaluator_with_prereq(
          prereq_path: attestation_file.path
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :gated_capability
        )

        expect(result).to be_allowed
        expect(result.prerequisites_checked).to eq(%i[file_exists])
      end

      it 'allows admin_tools when file exists and config value matches' do
        evaluator_with_prereqs = build_evaluator_with_multiple_prereqs(
          prereq_path: attestation_file.path
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:admin-agent',
          capability_name: :gated_capability,
          context: { 'admin_tools_enabled' => true }
        )

        expect(result).to be_allowed
        expect(result.prerequisites_checked).to eq(%i[file_exists config_value])
      end
    end

    context 'when prerequisites are not satisfied' do
      it 'denies with :prerequisite_not_met when file does not exist' do
        evaluator_with_prereqs = build_evaluator_with_prereq(
          prereq_path: '/nonexistent/attestation.md'
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :gated_capability
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:prerequisite_not_met)
        expect(result.details).to include('/nonexistent/attestation.md')
      end

      it 'denies with :prerequisite_not_met when config value is wrong' do
        attestation_file = Tempfile.new('safety-attestation')

        evaluator_with_prereqs = build_evaluator_with_multiple_prereqs(
          prereq_path: attestation_file.path
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:admin-agent',
          capability_name: :gated_capability,
          context: { 'admin_tools_enabled' => false }
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:prerequisite_not_met)
        expect(result.details).to include('admin_tools_enabled')

        attestation_file.close!
      end

      it 'denies with :prerequisite_not_met when config key is missing' do
        attestation_file = Tempfile.new('safety-attestation')

        evaluator_with_prereqs = build_evaluator_with_multiple_prereqs(
          prereq_path: attestation_file.path
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:admin-agent',
          capability_name: :gated_capability,
          context: {}
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:prerequisite_not_met)

        attestation_file.close!
      end
    end

    context 'for prerequisite evaluation order' do
      it 'checks capability existence before prerequisites' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :nonexistent
        )

        expect(result.reason).to eq(:unknown_capability)
      end

      it 'checks grant before prerequisites' do
        evaluator_with_prereqs = build_evaluator_with_prereq(
          prereq_path: '/nonexistent/file.md'
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:unauthorized-agent',
          capability_name: :gated_capability
        )

        expect(result.reason).to eq(:not_granted)
      end

      it 'short-circuits on first failing prerequisite' do
        evaluator_with_prereqs = build_evaluator_with_multiple_prereqs(
          prereq_path: '/nonexistent/file.md'
        )

        result = evaluator_with_prereqs.evaluate(
          caller_id: 'service-account:admin-agent',
          capability_name: :gated_capability,
          context: { 'admin_tools_enabled' => true }
        )

        expect(result.reason).to eq(:prerequisite_not_met)
        expect(result.details).to include('/nonexistent/file.md')
      end
    end

    context 'with empty grants' do
      let(:grants_path) { File.join(fixtures_dir, 'empty_grants.yml') }

      it 'denies everything — no grants means no access' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :basic_introspection
        )

        expect(result).to be_denied
        expect(result.reason).to eq(:not_granted)
      end
    end

    context 'with string capability names' do
      it 'accepts string input and normalizes to symbol' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: 'basic_introspection'
        )

        expect(result).to be_allowed
        expect(result.capability_name).to eq(:basic_introspection)
      end
    end
  end

  def build_evaluator_with_prereq(prereq_path:)
    prereqs = [Wild::CapabilityGate::Prerequisite.new(type: :file_exists, path: prereq_path)]
    build_evaluator_for(
      prerequisites: prereqs, risk_level: :elevated,
      caller_id: 'service-account:introspection-agent'
    )
  end

  def build_evaluator_with_multiple_prereqs(prereq_path:)
    prereqs = [
      Wild::CapabilityGate::Prerequisite.new(type: :file_exists, path: prereq_path),
      Wild::CapabilityGate::Prerequisite.new(type: :config_value, key: 'admin_tools_enabled', value: true)
    ]
    build_evaluator_for(
      prerequisites: prereqs, risk_level: :critical,
      caller_id: 'service-account:admin-agent'
    )
  end

  def build_evaluator_for(prerequisites:, risk_level:, caller_id:)
    capability = Wild::CapabilityGate::Capability.new(
      name: :gated_capability, description: 'Test gated capability',
      risk_level: risk_level, prerequisites: prerequisites
    )
    grants = [Wild::CapabilityGate::Grant.new(caller_id: caller_id, capabilities: [:gated_capability])]
    described_class.new(registry: Wild::CapabilityGate::Registry.new([capability]), grants: grants)
  end
end
