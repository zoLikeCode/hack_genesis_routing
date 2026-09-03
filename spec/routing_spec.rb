# frozen_string_literal: true

RSpec.describe Routing do
  it "has a version" do
    expect(Routing::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
