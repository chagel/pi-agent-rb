# frozen_string_literal: true

RSpec.describe PiAgent::Framer do
  let(:framer) { described_class.new }

  def collect(input)
    lines = []
    framer.feed(input) { |line| lines << line }
    lines
  end

  it "splits on LF only" do
    expect(collect("a\nb\nc\n")).to eq(%w[a b c])
  end

  it "buffers partial lines across feeds" do
    expect(collect("ab")).to eq([])
    expect(collect("c\n")).to eq(["abc"])
  end

  it "strips a trailing CR before yielding" do
    expect(collect("a\r\nb\r\n")).to eq(%w[a b])
  end

  it "does not split on U+2028 or U+2029" do
    input = "\"a b c\"\n"
    expect(collect(input)).to eq(["\"a b c\""])
  end

  it "drops empty lines" do
    expect(collect("\n\nfoo\n\n")).to eq(["foo"])
  end

  it "yields lines in UTF-8 encoding" do
    framer.feed("hello\n") do |line|
      expect(line.encoding).to eq(Encoding::UTF_8)
    end
  end

  it "reports buffered? state" do
    expect(framer.buffered?).to be false
    framer.feed("partial") {}
    expect(framer.buffered?).to be true
    framer.feed("\n") {}
    expect(framer.buffered?).to be false
  end

  it "handles multi-byte UTF-8 split across chunk boundaries" do
    # U+2603 SNOWMAN = E2 98 83
    expect(collect("\xE2".b)).to eq([])
    expect(collect("\x98".b)).to eq([])
    expect(collect("\x83\n".b)).to eq(["☃"])
  end
end
