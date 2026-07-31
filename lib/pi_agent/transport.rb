# frozen_string_literal: true

module PiAgent
  # A transport carries the pi RPC protocol between this process and a
  # running `pi --mode rpc`. It abstracts *where* pi runs: a local
  # subprocess (Transport::Subprocess), or — via a caller-supplied
  # transport — a process inside a remote sandbox.
  #
  # Contract. A transport is constructed with callables:
  #
  #   on_message: ->(Hash)    # one parsed JSON message from pi's stdout
  #   on_stderr:  ->(String)  # one line from pi's stderr
  #   on_close:   ->(String)  # death notification (optional; see below)
  #
  # and responds to:
  #
  #   #start            -> self;  begin delivering messages
  #   #write(Hash)      -> serialize to a JSON line, send to pi's stdin
  #   #close(timeout:)  -> shut pi down
  #   #alive?           -> Boolean
  #
  # Death notification (on_close). A transport MUST invoke on_close
  # exactly once when it reaches a terminal state on its own — child
  # process exit, read-stream EOF, fatal stream error — with a short
  # human-readable reason (e.g. "process terminated by signal 9").
  # Dispatch any already-read stdout messages via on_message *before*
  # calling on_close, so responses that raced the death are not lost. A
  # shutdown initiated by the owner via #close is not a death and must
  # not be reported. On notification, Client rejects in-flight requests
  # and ends Session event streams promptly with TransportClosedError
  # instead of letting them wait out their timeouts.
  #
  # on_close is optional for compatibility: Client inspects the transport
  # factory's parameters and passes the keyword only when the factory
  # accepts it (explicitly or via **kwargs). A factory with the older
  # `(on_message:, on_stderr:)` shape keeps its previous behavior —
  # request and event timeouts remain the only death backstop.
  #
  # Implementations own framing (pi speaks strict-LF JSONL — see Framer)
  # and the thread-safety of #write. Client injects its own handlers via
  # a transport factory, so transports never need settable callbacks.
  module Transport
  end
end
