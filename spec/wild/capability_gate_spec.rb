# frozen_string_literal: true

RSpec.describe Wild::CapabilityGate do
  it 'has a version number' do
    expect(described_class::VERSION).not_to be_nil
  end

  it 'defines the Wild::CapabilityGate module' do
    expect(described_class).to be_a(Module)
  end
end
