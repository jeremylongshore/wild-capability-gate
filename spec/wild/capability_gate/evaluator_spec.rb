# frozen_string_literal: true

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
      it 'uses wildcard grant if available' do
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

    context 'when caller is explicitly granted' do
      it 'allows the introspection agent to use basic_introspection' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :basic_introspection
        )

        expect(result).to be_allowed
        expect(result.capability_name).to eq(:basic_introspection)
        expect(result.caller_id).to eq('service-account:introspection-agent')
      end

      it 'allows the introspection agent to use privileged_introspection' do
        result = evaluator.evaluate(
          caller_id: 'service-account:introspection-agent',
          capability_name: :privileged_introspection
        )

        expect(result).to be_allowed
      end

      it 'allows the admin agent to use admin_tools' do
        result = evaluator.evaluate(
          caller_id: 'service-account:admin-agent',
          capability_name: :admin_tools
        )

        expect(result).to be_allowed
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
end
