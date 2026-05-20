# frozen_string_literal: true

require_relative "pi_agent/version"
require_relative "pi_agent/errors"
require_relative "pi_agent/framer"
require_relative "pi_agent/future"
require_relative "pi_agent/transport"
require_relative "pi_agent/client"

module PiAgent
  def self.open(**)
    client = Client.new(**).start
    return client unless block_given?

    begin
      yield client
    ensure
      client.close
    end
  end
end
