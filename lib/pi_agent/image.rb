# frozen_string_literal: true

require "base64"

module PiAgent
  # An image attachment for a prompt/steer/follow_up message.
  #
  # Serializes to the pi RPC ImageContent shape:
  #   { "type" => "image", "data" => <base64>, "mimeType" => <mime> }
  #
  # The pi prompt commands accept image attachments only; other file
  # types are not part of the prompt wire protocol.
  class Image
    MIME_BY_EXTENSION = {
      ".png" => "image/png",
      ".jpg" => "image/jpeg",
      ".jpeg" => "image/jpeg",
      ".gif" => "image/gif",
      ".webp" => "image/webp"
    }.freeze

    attr_reader :data, :mime_type

    # Build from a file on disk. MIME type is inferred from the extension.
    def self.from_file(path)
      ext = File.extname(path).downcase
      mime = MIME_BY_EXTENSION[ext]
      raise ArgumentError, "Unsupported image extension #{ext.inspect} (#{path})" unless mime

      from_bytes(File.binread(path), mime_type: mime)
    end

    # Build from raw binary image bytes.
    def self.from_bytes(bytes, mime_type:)
      new(data: Base64.strict_encode64(bytes), mime_type: mime_type)
    end

    # `data` must already be base64-encoded image data.
    def initialize(data:, mime_type:)
      @data = data
      @mime_type = mime_type
    end

    def to_h
      { "type" => "image", "data" => @data, "mimeType" => @mime_type }
    end
  end
end
