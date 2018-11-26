require 'aggregate_root/version'
require 'aggregate_root/configuration'
require 'aggregate_root/repository'
require 'aggregate_root/default_apply_strategy'

module AggregateRoot
  module ClassMethods
    def on(*event_klasses, &block)
      event_klasses.each do |event_klass|
        name = event_klass.name || raise(ArgumentError, "Anonymous class is missing name")
        handler_name = "on_#{name}"
        define_method(handler_name, &block)
        @on_methods ||= {}
        @on_methods[event_klass]=handler_name
        private(handler_name)
      end
    end

    def on_methods
      ancestors.
        select{|k| k.instance_variables.include?(:@on_methods)}.
        map{|k| k.instance_variable_get(:@on_methods) }.
        inject({}, &:merge)
    end
  end

  def self.included(host_class)
    host_class.extend(ClassMethods)
  end

  def apply(*events)
    events.each do |event|
      apply_strategy.(self, event)
      unpublished << event
    end
  end

  def load(stream_name, event_store: default_event_store)
    @repo ||= AggregateRoot::Repository.new(event_store)
    @repo.load(self, stream_name)
    @loaded_from_stream_name = stream_name
    @unpublished_events      = nil
    self
  end

  def store(stream_name = loaded_from_stream_name, event_store: default_event_store)
    @repo ||= AggregateRoot::Repository.new(event_store)
    @repo.store(self, stream_name)
    @unpublished_events = nil
  end

  def unpublished_events
    unpublished.each
  end

  private

  def unpublished
    @unpublished_events ||= []
  end

  def apply_strategy
    DefaultApplyStrategy.new(on_methods: self.class.on_methods)
  end

  def default_event_store
    AggregateRoot.configuration.default_event_store
  end

  def events_enumerator(event_store, stream_name)
    event_store.read.in_batches.stream(stream_name).each
  end

  attr_reader :loaded_from_stream_name
end
