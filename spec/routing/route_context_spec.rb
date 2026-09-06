# frozen_string_literal: true

RSpec.describe Routing::RouteContext do
  subject(:context) { described_class.new }

  it "keeps attempted and temporarily excluded lists separate", :aggregate_failures do
    context.exclude_temporarily!("vipay")
    context.mark_attempted!("payflow")

    expect(context.temporarily_excluded).to eq(["vipay"])
    expect(context.attempted).to eq(["payflow"])
  end

  it "clears only pass-local exclusions" do
    context.exclude_temporarily!("vipay")
    context.mark_attempted!("payflow")
    context.clear_temporarily_excluded!

    expect(context.temporarily_excluded).to eq([])
    expect(context.attempted).to eq(["payflow"])
  end
end
