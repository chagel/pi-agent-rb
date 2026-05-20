# frozen_string_literal: true

module PiAgent
  # A transport carries the pi RPC protocol between this process and a
  # running `pi --mode rpc`. It abstracts *where* pi runs: a local
  # subprocess (Transport::Subprocess), or — via a caller-supplied
  # transport — a process inside a remote sandbox.
  #
  # Contract. A transport is constructed with two callables:
  #
  #   on_message: ->(Hash)    # one parsed JSON message from pi's stdout
  #   on_stderr:  ->(String)  # one line from pi's stderr
  #
  # and responds to:
  #
  #   #start            -> self;  begin delivering messages
  #   #write(Hash)      -> serialize to a JSON line, send to pi's stdin
  #   #close(timeout:)  -> shut pi down
  #   #alive?           -> Boolean
  #
  # Implementations own framing (pi speaks strict-LF JSONL — see Framer)
  # and the thread-safety of #write. Client injects its own handlers via
  # a transport factory, so transports never need settable callbacks.
  module Transport
  end
end
