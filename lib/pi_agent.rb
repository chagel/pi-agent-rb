# frozen_string_literal: true

require_relative "pi_agent/version"
require_relative "pi_agent/errors"
require_relative "pi_agent/framer"
require_relative "pi_agent/future"
require_relative "pi_agent/transport"
require_relative "pi_agent/extension_ui"
require_relative "pi_agent/client"
require_relative "pi_agent/event"
require_relative "pi_agent/session"

module PiAgent
  # Open a low-level RPC client (spawns `pi --mode rpc`).
  def self.open(**)
    client = Client.new(**).start
    return client unless block_given?

    begin
      yield client
    ensure
      client.close
    end
  end

  # Open a high-level agent session. This is the common entrypoint.
  def self.session(**)
    client = Client.new(**).start
    session = Session.new(client)
    return session unless block_given?

    begin
      yield session
    ensure
      session.close
    end
  end
end
