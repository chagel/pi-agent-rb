# frozen_string_literal: true

RSpec.describe PiAgent::Future do
  it "resolves with a value across threads" do
    fut = described_class.new
    Thread.new do
      sleep 0.01
      fut.resolve(42)
    end
    expect(fut.value!(timeout: 1)).to eq(42)
  end

  it "rejects with an exception across threads" do
    fut = described_class.new
    err = RuntimeError.new("nope")
    Thread.new do
      sleep 0.01
      fut.reject(err)
    end
    expect { fut.value!(timeout: 1) }.to raise_error(RuntimeError, "nope")
  end

  it "raises TimeoutError when not resolved in time" do
    fut = described_class.new
    expect { fut.value!(timeout: 0.05) }.to raise_error(PiAgent::TimeoutError)
  end

  it "ignores subsequent resolutions after the first" do
    fut = described_class.new
    fut.resolve(1)
    fut.resolve(2)
    expect(fut.value!(timeout: 0.01)).to eq(1)
  end

  it "ignores subsequent rejection after resolution" do
    fut = described_class.new
    fut.resolve(:ok)
    fut.reject(RuntimeError.new("late"))
    expect(fut.value!(timeout: 0.01)).to eq(:ok)
  end

  it "rejects non-Exception arguments to #reject" do
    fut = described_class.new
    expect { fut.reject("not an exception") }.to raise_error(ArgumentError)
  end

  it "reports resolved? correctly" do
    fut = described_class.new
    expect(fut.resolved?).to be false
    fut.resolve(nil)
    expect(fut.resolved?).to be true
  end
end
