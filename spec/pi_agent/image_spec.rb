# frozen_string_literal: true

require "base64"
require "tempfile"

RSpec.describe PiAgent::Image do
  describe ".from_bytes" do
    it "base64-encodes the bytes and serializes to ImageContent" do
      image = described_class.from_bytes("rawbytes", mime_type: "image/png")

      expect(image.to_h).to eq(
        {
          "type" => "image",
          "data" => Base64.strict_encode64("rawbytes"),
          "mimeType" => "image/png"
        }
      )
    end

    it "round-trips through base64" do
      bytes = "\x89PNG\r\n\x1a\n binary".b
      image = described_class.from_bytes(bytes, mime_type: "image/png")
      expect(Base64.strict_decode64(image.data)).to eq(bytes)
    end
  end

  describe ".from_file" do
    it "reads a file and infers the MIME type from the extension" do
      file = Tempfile.new(["pic", ".jpg"])
      file.binmode
      file.write("jpegbytes")
      file.flush

      image = described_class.from_file(file.path)
      expect(image.mime_type).to eq("image/jpeg")
      expect(Base64.strict_decode64(image.data)).to eq("jpegbytes")
    ensure
      file&.close!
    end

    it "maps each supported extension to the right MIME type" do
      {
        ".png" => "image/png",
        ".jpg" => "image/jpeg",
        ".jpeg" => "image/jpeg",
        ".gif" => "image/gif",
        ".webp" => "image/webp"
      }.each do |ext, mime|
        file = Tempfile.new(["pic", ext])
        file.binmode
        file.write("x")
        file.flush
        expect(described_class.from_file(file.path).mime_type).to eq(mime)
      ensure
        file&.close!
      end
    end

    it "raises ArgumentError for an unsupported extension" do
      file = Tempfile.new(["doc", ".pdf"])
      file.flush
      expect { described_class.from_file(file.path) }
        .to raise_error(ArgumentError, /Unsupported image extension/)
    ensure
      file&.close!
    end
  end

  describe "#initialize" do
    it "accepts already-encoded base64 data" do
      image = described_class.new(data: "YWJj", mime_type: "image/gif")
      expect(image.to_h).to eq({ "type" => "image", "data" => "YWJj", "mimeType" => "image/gif" })
    end
  end
end
