module AggregateRoot
  class Repository
    def initialize(event_store = default_event_store)
      @event_store = event_store
      @version     = -1
    end

    def load(aggregate, stream_name)
      events_enumerator(stream_name).each.with_index do |event, index|
        aggregate.apply(event)
        @version = index
      end
      @loaded_from_stream_name = stream_name
    end

    def store(aggregate, stream_name = @loaded_from_stream_name)
      @event_store.publish(aggregate.unpublished_events.to_a, stream_name: stream_name, expected_version: @version)
      @version += aggregate.unpublished_events.size
    end

    private

    def default_event_store
      AggregateRoot.configuration.default_event_store
    end

    def events_enumerator(stream_name)
      @event_store.read.in_batches.stream(stream_name).each
    end
  end
end