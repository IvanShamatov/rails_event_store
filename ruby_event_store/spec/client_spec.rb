require 'spec_helper'
require 'time'

module RubyEventStore
  RSpec.describe Client do
    let(:client) { RubyEventStore::Client.new(repository: InMemoryRepository.new) }
    let(:stream) { SecureRandom.uuid }

    specify 'publish returns self when success' do
      expect(client.publish(TestEvent.new)).to eq(client)
    end

    specify 'append returns client when success' do
      expect(client.append(TestEvent.new, stream_name: stream)).to eq(client)
    end

    specify 'append to default stream when not specified' do
      expect(client.append(test_event = TestEvent.new)).to eq(client)
      expect(client.read.limit(100).to_a).to eq([test_event])
    end

    specify 'publish to default stream when not specified' do
      expect(client.publish([test_event = TestEvent.new])).to eq(client)
      expect(client.read.limit(100).to_a).to eq([test_event])
    end

    specify 'delete_stream returns client when success' do
      expect(client.delete_stream(stream)).to eq(client)
    end

    specify 'publish to default stream when not specified' do
      expect(client.publish(test_event = TestEvent.new)).to eq(client)
      expect(client.read.limit(100).to_a).to eq([test_event])
    end

    specify 'publish first event, expect any stream state' do
      expect(client.publish(first_event = TestEvent.new, stream_name: stream)).to eq(client)
      expect(client.read.stream(stream).to_a).to eq([first_event])
    end

    specify 'publish next event, expect any stream state' do
      client.append(first_event = TestEvent.new, stream_name: stream)

      expect(client.publish(second_event = TestEvent.new, stream_name: stream)).to eq(client)
      expect(client.read.stream(stream).to_a).to eq([first_event, second_event])
    end

    specify 'publish first event, expect empty stream' do
      expect(client.publish(first_event = TestEvent.new, stream_name: stream, expected_version: :none)).to eq(client)
      expect(client.read.stream(stream).to_a).to eq([first_event])
    end

    specify 'publish first event, fail if not empty stream' do
      client.append(first_event = TestEvent.new, stream_name: stream)

      expect { client.publish(second_event = TestEvent.new, stream_name: stream, expected_version: :none) }.to raise_error(WrongExpectedEventVersion)
      expect(client.read.stream(stream).to_a).to eq([first_event])
    end

    specify 'publish event, expect last event to be the last read one' do
      client.append(first_event = TestEvent.new, stream_name: stream)

      expect(client.publish(second_event = TestEvent.new, stream_name: stream, expected_version: 0)).to eq(client)
      expect(client.read.stream(stream).to_a).to eq([first_event, second_event])
    end

    specify 'publish event, fail if last event is not the last read one' do
      client.append(first_event = TestEvent.new, stream_name: stream)
      client.append(second_event = TestEvent.new, stream_name: stream)

      expect { client.publish(third_event = TestEvent.new, stream_name: stream, expected_version: 0) }.to raise_error(WrongExpectedEventVersion)
      expect(client.read.stream(stream).to_a).to eq([first_event, second_event])
    end

    specify 'append many events' do
      client.append(
        [first_event = TestEvent.new, second_event = TestEvent.new],
        stream_name: stream,
        expected_version: -1
      )
      expect(client.read.stream(stream).to_a).to eq([first_event, second_event])
    end

    specify 'read only up to page size from stream' do
      (1..102).each { client.append(TestEvent.new, stream_name: stream) }

      expect(client.read.stream(stream).limit(10).to_a.size).to eq(10)
      expect(client.read.backward.stream(stream).limit(10).to_a.size).to eq(10)
      expect(client.read.stream(stream).limit(100).to_a.size).to eq(PAGE_SIZE)
      expect(client.read.backward.stream(stream).limit(100).to_a.size).to eq(PAGE_SIZE)

      expect(client.read.limit(10).to_a.size).to eq(10)
      expect(client.read.backward.limit(10).to_a.size).to eq(10)
      expect(client.read.limit(100).to_a.size).to eq(PAGE_SIZE)
      expect(client.read.backward.limit(100).to_a.size).to eq(PAGE_SIZE)
    end

    specify 'published event metadata will be enriched by metadata provided in with_metadata when executed inside a block' do
      client.with_metadata(request_ip: '127.0.0.1') do
        client.publish(event = TestEvent.new)
      end
      published = client.read.limit(100).to_a

      expect(published.size).to eq(1)
      expect(published.first.metadata[:request_ip]).to eq('127.0.0.1')
      expect(published.first.metadata[:timestamp]).to be_a Time
    end

    specify 'published event metadata will not be enriched by metadata provided in with_metadata when published outside a block' do
      client.with_metadata(request_ip: '127.0.0.1')
      client.publish(event = TestEvent.new)
      published = client.read.limit(100).to_a

      expect(published.size).to eq(1)
      expect(published.first.metadata[:request_ip]).to be_nil
      expect(published.first.metadata[:timestamp]).to be_a Time
    end

    specify 'published event metadata will be enriched by nested metadata provided in with_metadata' do
      client.with_metadata(request_ip: '127.0.0.1') do
        client.publish(TestEvent.new)
        client.with_metadata(request_ip: '1.2.3.4', nested: true) do
          client.publish(TestEvent.new)
          client.with_metadata(deeply_nested: true) do
            client.publish(TestEvent.new)
          end
        end
        client.publish(TestEvent.new)
      end
      client.publish(TestEvent.new)
      published = client.read.limit(100).to_a

      expect(published.size).to eq(5)
      expect(published[0].metadata.keys).to match_array([:timestamp, :request_ip])
      expect(published[0].metadata[:request_ip]).to eq('127.0.0.1')
      expect(published[0].metadata[:timestamp]).to be_a Time
      expect(published[1].metadata.keys).to match_array([:timestamp, :request_ip, :nested])
      expect(published[1].metadata[:request_ip]).to eq('1.2.3.4')
      expect(published[1].metadata[:nested]).to eq true
      expect(published[1].metadata[:timestamp]).to be_a Time
      expect(published[2].metadata.keys).to match_array([:timestamp, :request_ip, :nested, :deeply_nested])
      expect(published[2].metadata[:request_ip]).to eq('1.2.3.4')
      expect(published[2].metadata[:nested]).to eq true
      expect(published[2].metadata[:deeply_nested]).to eq true
      expect(published[2].metadata[:timestamp]).to be_a Time
      expect(published[3].metadata.keys).to match_array([:timestamp, :request_ip])
      expect(published[3].metadata[:request_ip]).to eq('127.0.0.1')
      expect(published[3].metadata[:timestamp]).to be_a Time
      expect(published[4].metadata.keys).to match_array([:timestamp])
      expect(published[4].metadata[:timestamp]).to be_a Time
    end

    specify 'with_metadata is merged when nested' do
      client.with_metadata(remote_ip: '127.0.0.1') do
        client.publish(TestEvent.new)
        client.with_metadata(remote_ip: '192.168.0.1', request_id: '1234567890') do
          client.publish(TestEvent.new)
        end
        client.publish(TestEvent.new)
      end
      published = client.read.limit(100).to_a

      expect(published.size).to eq(3)
      expect(published[0].metadata.keys).to match_array([:timestamp, :remote_ip])
      expect(published[0].metadata[:remote_ip]).to eq('127.0.0.1')
      expect(published[0].metadata[:timestamp]).to be_a Time
      expect(published[1].metadata.keys).to match_array([:timestamp, :remote_ip, :request_id])
      expect(published[1].metadata[:timestamp]).to be_a Time
      expect(published[1].metadata[:remote_ip]).to eq('192.168.0.1')
      expect(published[1].metadata[:request_id]).to eq('1234567890')
      expect(published[2].metadata.keys).to match_array([:timestamp, :remote_ip])
      expect(published[2].metadata[:remote_ip]).to eq('127.0.0.1')
      expect(published[2].metadata[:timestamp]).to be_a Time
    end

    specify "event's  metadata takes precedence over with_metadata" do
      client.with_metadata(request_ip: '127.0.0.1') do
        client.publish(@event = TestEvent.new(metadata: {request_ip: '1.2.3.4'}))
      end
      expect(@event.metadata.fetch(:request_ip)).to eq('1.2.3.4')
    end

    specify 'metadata is bound to the current instance and does not leak to others' do
      client_a = RubyEventStore::Client.new(repository: InMemoryRepository.new)
      client_b = RubyEventStore::Client.new(repository: InMemoryRepository.new)
      client_a.with_metadata(client: 'a') do
        client_b.with_metadata(client: 'b') do
          client_a.publish(TestEvent.new)
          client_b.publish(TestEvent.new)
        end
      end
      published_a = client_a.read.limit(100).to_a
      published_b = client_b.read.limit(100).to_a

      expect(published_a.size).to eq(1)
      expect(published_b.size).to eq(1)
      expect(published_a.last.metadata[:client]).to eq('a')
      expect(published_b.last.metadata[:client]).to eq('b')
    end

    specify 'with_metadata is thread-safe' do
      client.with_metadata(thread1: '1') do
        Thread.new do
          client.with_metadata(thread2: '2') do
            client.publish(@event = TestEvent.new)
          end
        end.join
      end
      expect(@event.metadata[:thread1]).to be_nil
      expect(@event.metadata[:thread2]).to eq('2')
    end

    specify 'timestamp can be overwritten by using with_metadata' do
      client.with_metadata(timestamp: '2018-01-01T00:00:00Z') do
        client.append(event = TestEvent.new)
      end
      published = client.read.limit(100).to_a

      expect(published.size).to eq(1)
      expect(published.first.metadata.to_h.keys).to eq([:timestamp])
      expect(published.first.metadata[:timestamp]).to eq('2018-01-01T00:00:00Z')
    end

    specify 'timestamp is utc time' do
      now = Time.parse('2015-05-04 15:17:11 +0200')
      utc = Time.parse('2015-05-04 13:17:23 UTC')
      allow(Time).to receive(:now).and_return(now)
      allow_any_instance_of(Time).to receive(:utc).and_return(utc)
      client.publish(event = TestEvent.new)
      published = client.read.limit(100).to_a

      expect(published.size).to eq(1)
      expect(published.first.metadata[:timestamp]).to eq(utc)
    end

    specify "correlation_id and causation_id in metadata for sync handlers" do
      client.subscribe(to: [ProductAdded]) do
        client.publish(@two = OrderCreated.new)
      end
      client.subscribe(to: [OrderCreated]) do
        client.publish(@three = TestEvent.new)
        client.publish(@four  = TestEvent.new(metadata:{
          correlation_id: 'COID',
          causation_id:   'CAID',
        }))
      end
      client.publish(one = ProductAdded.new)

      expect(@two.correlation_id).to eq(one.event_id)
      expect(@two.causation_id).to   eq(one.event_id)

      expect(@three.correlation_id).to eq(one.event_id)
      expect(@three.causation_id).to   eq(@two.event_id)

      expect(@four.correlation_id).to eq('COID')
      expect(@four.causation_id).to   eq('CAID')

      client.publish(one = ProductAdded.new(metadata:{
        correlation_id: "COID",
        causation_id:   "CAID",
      }))
      expect(@two.correlation_id).to eq("COID")
      expect(@two.causation_id).to   eq(one.event_id)
    end

    specify 'reading particular event' do
      client.publish(test_event = TestEvent.new, stream_name: 'test')
      expect(client.read.event!(test_event.event_id)).to eq(test_event)
    end

    specify 'reading non-existent event' do
      expect(client.read.event('72922e65-1b32-4e97-8023-03ae81dd3a27')).to be_nil
      expect { client.read.event!('72922e65-1b32-4e97-8023-03ae81dd3a27') }.to raise_error(EventNotFound)
    end

    specify 'deprecation of read_event' do
      spec = instance_double(Specification)
      expect(client).to receive(:read).and_return(spec)
      expect(spec).to receive(:event!).with('72922e65-1b32-4e97-8023-03ae81dd3a27')
      expect { client.read_event('72922e65-1b32-4e97-8023-03ae81dd3a27') }.to output(<<~EOS).to_stderr
        RubyEventStore::Client#read_event(event_id) has been deprecated.
        Use `client.read.event!(event_id)` instead. Also available without
        bang - return nil when no event is found.
      EOS
     end

    specify 'link events' do
      client.subscribe_to_all_events(subscriber = Subscribers::ValidHandler.new)
      client.append(
        [first_event = TestEvent.new, second_event = TestEvent.new],
        stream_name: 'stream'
      )
      client.link(
        [first_event.event_id, second_event.event_id],
        stream_name: 'flow',
        expected_version: -1
      ).link(
        [first_event.event_id],
        stream_name: 'cars',
      )

      expect(client.read.stream("flow").to_a).to eq([first_event, second_event])
      expect(client.read.stream("cars").to_a).to eq([first_event])
      expect(subscriber.handled_events).to be_empty
    end

    specify 'can handle protobuf event class instead of RubyEventStore::Event' do
      begin
        require_relative 'mappers/events_pb.rb'

        client = RubyEventStore::Client.new(
          mapper: RubyEventStore::Mappers::Protobuf.new,
          repository: InMemoryRepository.new
        )
        event = RubyEventStore::Proto.new(
          event_id: "f90b8848-e478-47fe-9b4a-9f2a1d53622b",
          data: ResTesting::OrderCreated.new(
            customer_id: 123,
            order_id: "K3THNX9",
          )
        )
        client.publish(event, stream_name: 'test')

        expect(client.read.event!(event.event_id)).to eq(event)
        expect(client.read.stream("test").to_a).to eq([event])
      rescue LoadError => exc
        skip if exc.message == "cannot load such file -- google/protobuf_c"
      end
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.read.stream(nil).limit(100).to_a }.to raise_error(IncorrectStreamData)
      expect { client.read.stream("").limit(100).to_a }.to raise_error(IncorrectStreamData)
      expect { client.read.backward.stream(nil).limit(100).to_a }.to raise_error(IncorrectStreamData)
      expect { client.read.backward.stream("").limit(100).to_a }.to raise_error(IncorrectStreamData)
    end

    specify 'raise exception if event_id does not exist' do
      expect { client.read.stream("stream_name").from("0").limit(100).to_a }.to raise_error(EventNotFound, /Event not found: 0/)
      expect { client.read.backward.stream("stream_name").from("0").limit(100).to_a }.to raise_error(EventNotFound, /0/)
    end

    specify 'raise exception if event_id is not given or invalid' do
      expect { client.read.stream("stream_name").from(nil).limit(100).to_a }.to raise_error(InvalidPageStart)
      expect { client.read.backward.stream("stream_name").from(:invalid).limit(100).to_a }.to raise_error(InvalidPageStart)
    end

    specify 'fails when page size is invalid' do
      expect { client.read.stream("stream_name").limit(0).to_a }.to raise_error(InvalidPageSize)
      expect { client.read.backward.stream("stream_name").limit(0).to_a }.to raise_error(InvalidPageSize)
      expect { client.read.stream("stream_name").limit(-1).to_a }.to raise_error(InvalidPageSize)
      expect { client.read.backward.stream("stream_name").limit(-1).to_a }.to raise_error(InvalidPageSize)
    end

    specify 'return all events ordered forward' do
      4.times do |index|
        event = OrderCreated.new(event_id: index.to_s)
        client.publish(event, stream_name: 'stream_name')
      end
      events = client.read.stream("stream_name").from("1").limit(3).to_a

      expect(events[0]).to eq(OrderCreated.new(event_id: '2'))
      expect(events[1]).to eq(OrderCreated.new(event_id: '3'))
    end

    specify 'return specified number of events ordered forward' do
      4.times do |index|
        event = OrderCreated.new(event_id: index.to_s)
        client.publish(event, stream_name: 'stream_name')
      end
      events = client.read.stream("stream_name").from("1").limit(1).to_a

      expect(events[0]).to eq(OrderCreated.new(event_id: '2'))
    end

    specify 'return all events ordered backward' do
      4.times do |index|
        event = OrderCreated.new(event_id: index)
        client.publish(event, stream_name: 'stream_name')
      end
      events = client.read.backward.stream("stream_name").from("2").limit(3).to_a

      expect(events[0]).to eq(OrderCreated.new(event_id: '1'))
      expect(events[1]).to eq(OrderCreated.new(event_id: '0'))
    end

    specify 'return specified number of events ordered backward' do
      4.times do |index|
        event = OrderCreated.new(event_id: index)
        client.publish(event, stream_name: 'stream_name')
      end
      events = client.read.backward.stream("stream_name").from("3").limit(2).to_a

      expect(events[0]).to eq(OrderCreated.new(event_id: '2'))
      expect(events[1]).to eq(OrderCreated.new(event_id: '1'))
    end

    specify 'fails when starting event not exists' do
      4.times do |index|
        event = OrderCreated.new(event_id: index)
        client.publish(event, stream_name: 'stream_name')
      end

      expect { client.read.stream("stream_name").from(SecureRandom.uuid).limit(100).to_a }.to raise_error(EventNotFound)
      expect { client.read.backward.stream("stream_name").from(SecureRandom.uuid).limit(100).to_a }.to raise_error(EventNotFound)
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.delete_stream(nil) }.to raise_error(IncorrectStreamData)
      expect { client.delete_stream('') }.to raise_error(IncorrectStreamData)
    end

    specify 'successfully delete streams of events' do
      4.times { client.publish(OrderCreated.new, stream_name: 'test_1') }
      4.times { client.publish(OrderCreated.new, stream_name: 'test_2') }
      all_events = client.read.limit(100).to_a
      expect(all_events.length).to eq 8
      client.delete_stream('test_2')
      all_events = client.read.limit(100).to_a
      expect(all_events.length).to eq 8
      expect(client.read.stream("test_2").to_a).to eq []
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.read.stream(nil).to_a }.to raise_error(IncorrectStreamData)
      expect { client.read.stream("").to_a }.to raise_error(IncorrectStreamData)
      expect { client.read.backward.stream(nil).to_a }.to raise_error(IncorrectStreamData)
      expect { client.read.backward.stream("").to_a }.to raise_error(IncorrectStreamData)
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.append(OrderCreated.new, stream_name: nil) }.to raise_error(IncorrectStreamData)
      expect { client.append(OrderCreated.new, stream_name: '') }.to raise_error(IncorrectStreamData)
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.publish(OrderCreated.new, stream_name: nil) }.to raise_error(IncorrectStreamData)
      expect { client.publish(OrderCreated.new, stream_name: '') }.to raise_error(IncorrectStreamData)
      expect { client.publish([OrderCreated.new], stream_name: nil) }.to raise_error(IncorrectStreamData)
      expect { client.publish([OrderCreated.new], stream_name: '') }.to raise_error(IncorrectStreamData)
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.append(OrderCreated.new, stream_name: nil) }.to raise_error(IncorrectStreamData)
      expect { client.append(OrderCreated.new, stream_name: '') }.to raise_error(IncorrectStreamData)
    end

    specify 'raise exception if stream name is incorrect' do
      expect { client.append(OrderCreated.new, stream_name: nil, expected_version: -1) }.to raise_error(IncorrectStreamData)
      expect { client.append(OrderCreated.new, stream_name: '', expected_version: -1) }.to raise_error(IncorrectStreamData)
    end

    specify 'return all events ordered forward' do
      4.times do |index|
        event = OrderCreated.new(event_id: index.to_s)
        client.publish(event, stream_name: 'stream_name')
      end
      events = client.read.stream("stream_name").to_a
      expect(events[0]).to eq(OrderCreated.new(event_id: '0'))
      expect(events[1]).to eq(OrderCreated.new(event_id: '1'))
      expect(events[2]).to eq(OrderCreated.new(event_id: '2'))
      expect(events[3]).to eq(OrderCreated.new(event_id: '3'))
    end

    specify 'return all events ordered backward' do
      4.times do |index|
        event = OrderCreated.new(event_id: index.to_s)
        client.publish(event, stream_name: 'stream_name')
      end
      events = client.read.backward.stream("stream_name").to_a
      expect(events[0]).to eq(OrderCreated.new(event_id: '3'))
      expect(events[1]).to eq(OrderCreated.new(event_id: '2'))
      expect(events[2]).to eq(OrderCreated.new(event_id: '1'))
      expect(events[3]).to eq(OrderCreated.new(event_id: '0'))
    end

    specify 'return all events ordered forward' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')
      client.publish(OrderCreated.new(data: {order_id: 234}), stream_name: 'order_2')
      response = client.read.limit(100).to_a
      expect(response.length).to eq 2
      expect(response[0].data[:order_id]).to eq 123
      expect(response[1].data[:order_id]).to eq 234
    end

    specify 'return batch of events from the beginging ordered forward' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')
      client.publish(OrderCreated.new(data: {order_id: 234}), stream_name: 'order_2')
      client.publish(OrderCreated.new(data: {order_id: 345}), stream_name: 'order_3')
      response = client.read.from(:head).limit(2).to_a

      expect(response.length).to eq 2
      expect(response[0].data[:order_id]).to eq 123
      expect(response[1].data[:order_id]).to eq 234
    end

    specify 'return batch of events from given event ordered forward' do
      uid = SecureRandom.uuid
      client.publish(OrderCreated.new(event_id: uid, data: {order_id: 123}), stream_name: 'order_1')
      client.publish(OrderCreated.new(data: {order_id: 234}), stream_name: 'order_2')
      client.publish(OrderCreated.new(data: {order_id: 345}), stream_name: 'order_3')
      response = client.read.from(uid).limit(1).to_a

      expect(response.length).to eq 1
      expect(response[0].data[:order_id]).to eq 234
    end

    specify 'return all events ordered backward' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')
      client.publish(OrderCreated.new(data: {order_id: 234}), stream_name: 'order_1')
      response = client.read.backward.limit(100).to_a

      expect(response.length).to eq 2
      expect(response[0].data[:order_id]).to eq 234
      expect(response[1].data[:order_id]).to eq 123
    end

    specify 'return batch of events from the end ordered backward' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')
      client.publish(OrderCreated.new(data: {order_id: 234}), stream_name: 'order_2')
      client.publish(OrderCreated.new(data: {order_id: 345}), stream_name: 'order_3')
      response = client.read.backward.from(:head).limit(2).to_a

      expect(response.length).to eq 2
      expect(response[0].data[:order_id]).to eq 345
      expect(response[1].data[:order_id]).to eq 234
    end

    specify 'return batch of events from given event ordered backward' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')
      client.publish(OrderCreated.new(event_id: uid = SecureRandom.uuid, data: {order_id: 234}), stream_name: 'order_2')
      client.publish(OrderCreated.new(data: {order_id: 345}), stream_name: 'order_3')
      response = client.read.backward.from(uid).limit(1).to_a

      expect(response.length).to eq 1
      expect(response[0].data[:order_id]).to eq 123
    end

    specify 'fails when starting event not exists' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')

      expect { client.read.from(SecureRandom.uuid).limit(100).to_a }.to raise_error(EventNotFound)
      expect { client.read.backward.from(SecureRandom.uuid).limit(100).to_a }.to raise_error(EventNotFound)
    end

    specify 'fails when page size is invalid' do
      client.publish(OrderCreated.new(data: {order_id: 123}), stream_name: 'order_1')

      expect { client.read.limit(0).to_a }.to raise_error(InvalidPageSize)
      expect { client.read.backward.limit(0).to_a }.to raise_error(InvalidPageSize)
      expect { client.read.limit(-1).to_a }.to raise_error(InvalidPageSize)
      expect { client.read.backward.limit(-1).to_a }.to raise_error(InvalidPageSize)
    end

    specify 'create successfully event' do
      client.append(
        event = OrderCreated.new(event_id: 'b2d506fd-409d-4ec7-b02f-c6d2295c7edd'),
        stream_name: 'stream_name'
      )
      saved_events = client.read.stream("stream_name").to_a

      expect(saved_events[0]).to eq(event)
    end

    specify 'generate guid and create successfully event' do
      client.append(event = OrderCreated.new, stream_name: 'stream_name')
      saved_events = client.read.stream("stream_name").to_a

      expect(saved_events[0]).to eq(event)
    end

    specify 'raise exception if expected version incorrect' do
      client.append(event = OrderCreated.new, stream_name: 'stream_name')
      expect { client.publish(event, stream_name: 'stream_name', expected_version: 100) }.to raise_error(WrongExpectedEventVersion)
    end

    specify 'create event with optimistic locking' do
      expect do
        client.append(
          OrderCreated.new(event_id: 'b2d506fd-409d-4ec7-b02f-c6d2295c7edd'),
          stream_name: 'stream_name'
        )
        client.append(
          OrderCreated.new(event_id: '724dd49d-6e20-40e6-bc32-ed75258f886b'),
          stream_name: 'stream_name',
          expected_version: 0
        )
      end.not_to raise_error
    end

    specify 'expect no event handler is called' do
      handler = double(:event_handler)
      expect(handler).not_to receive(:call)
      client.subscribe_to_all_events(handler)
      client.append(event = OrderCreated.new, stream_name: 'stream_name')
      saved_events = client.read.stream("stream_name").to_a

      expect(saved_events[0]).to eq(event)
    end

    specify 'expect publish to call event handlers' do
      handler = double(:event_handler)
      expect(handler).to receive(:call)
      client.subscribe_to_all_events(handler)
      client.publish(event = OrderCreated.new, stream_name: 'stream_name')
      saved_events = client.read.stream("stream_name").to_a

      expect(saved_events[0]).to eq(event)
    end

    specify 'expect publish to call event handlers' do
      handler = double(:event_handler)
      expect(handler).to receive(:call)
      client.subscribe_to_all_events(handler)
      client.publish(event = OrderCreated.new, stream_name: 'stream_name')
      saved_events = client.read.stream("stream_name").to_a

      expect(saved_events[0]).to eq(event)
    end

    specify 'create global event without stream name' do
      client.publish(event = OrderCreated.new)
      saved_events = client.read.limit(100).to_a

      expect(saved_events[0]).to eq(event)
    end

    specify 'append fail if expected version is nil' do

      expect do
        client.append(event = OrderCreated.new, stream_name: 'stream', expected_version: nil)
      end.to raise_error(RubyEventStore::InvalidExpectedVersion)
    end

    specify 'link fail if expected version is nil' do
      client.append(event = OrderCreated.new, stream_name: 'stream', expected_version: :any)

      expect do
        client.link(event.event_id, stream_name: 'stream', expected_version: nil)
      end.to raise_error(RubyEventStore::InvalidExpectedVersion)
    end

    specify 'global stream is unordered, one cannot expect specific version number to work' do
      expect do
        client.append(OrderCreated.new, expected_version: 42)
      end.to raise_error(RubyEventStore::InvalidExpectedVersion)
    end

    specify 'global stream is unordered, one cannot expect :none to work' do
      expect do
        client.append(OrderCreated.new, expected_version: :none)
      end.to raise_error(RubyEventStore::InvalidExpectedVersion)
    end

    specify 'global stream is unordered, one cannot expect :auto to work' do
      expect do
        client.append(OrderCreated.new, expected_version: :auto)
      end.to raise_error(RubyEventStore::InvalidExpectedVersion)
    end

    specify "only :none, :any, :auto and Integer allowed as expected_version" do

      [Object.new, SecureRandom.uuid, :foo].each do |invalid_expected_version|
        expect do
          client.append(
            OrderCreated.new(event_id: SecureRandom.uuid),
            stream_name: "some_stream",
            expected_version: invalid_expected_version
          )
        end.to raise_error(RubyEventStore::InvalidExpectedVersion)
      end
    end

    specify "only :none, :any, :auto and Integer allowed as expected_version when linking" do

      [Object.new, SecureRandom.uuid, :foo].each do |invalid_expected_version|
        client.append(
          OrderCreated.new(event_id: evid = SecureRandom.uuid),
          stream_name: SecureRandom.uuid,
          expected_version: :none
        )
        expect do
          client.link(evid, stream_name: SecureRandom.uuid, expected_version: invalid_expected_version)
        end.to raise_error(RubyEventStore::InvalidExpectedVersion)
      end
    end

    specify "public read" do
      expect(client).to respond_to(:read)
      expect(client.read.to_a).to eq([])
    end

    specify 'can load serialized event when using Default mapper' do
      client = RubyEventStore::Client.new(
        mapper:     RubyEventStore::Mappers::Default.new,
        repository: InMemoryRepository.new
      )
      event = OrderCreated.new(
          event_id: 'f90b8848-e478-47fe-9b4a-9f2a1d53622b',
          data:     { foo: 'bar' },
          metadata: { bar: 'baz' }
      )
      serialized_event = {
        event_type: "OrderCreated",
        event_id:   "f90b8848-e478-47fe-9b4a-9f2a1d53622b",
        data:       "---\n:foo: bar\n",
        metadata:   "---\n:bar: baz\n"
      }
      expect(client.deserialize(serialized_event)).to eq(event)
    end

    specify 'can load serialized event using Protobuf mapper' do
      begin
        require_relative 'mappers/events_pb.rb'

        client = RubyEventStore::Client.new(
          mapper: RubyEventStore::Mappers::Protobuf.new,
          repository: InMemoryRepository.new
        )
        event = RubyEventStore::Proto.new(
          event_id: "f90b8848-e478-47fe-9b4a-9f2a1d53622b",
          data: ResTesting::OrderCreated.new(
            customer_id: 123,
            order_id: "K3THNX9",
          ),
          metadata: {
            time: Time.new(2018, 12, 13, 11),
          }
        )
        serialized_event = {
          event_type: "res_testing.OrderCreated",
          event_id: "f90b8848-e478-47fe-9b4a-9f2a1d53622b",
          data: "\n\aK3THNX9\x10{",
          metadata: "\n\x10\n\x04time\x12\b:\x06\b\xA0\xDB\xC8\xE0\x05"
        }
        expect(client.deserialize(serialized_event)).to eq(event)
      rescue LoadError => exc
        skip if exc.message == "cannot load such file -- google/protobuf_c"
      end
    end

    specify 'raise error when no subscriber' do
      expect { client.subscribe(nil, to: [])}.to raise_error(RubyEventStore::SubscriberNotExist)
      expect { client.subscribe_to_all_events(nil)}.to raise_error(RubyEventStore::SubscriberNotExist)
      expect { client.within{}.subscribe(nil, to: []).call}.to raise_error(RubyEventStore::SubscriberNotExist)
      expect { client.within{}.subscribe_to_all_events(nil).call}.to raise_error(RubyEventStore::SubscriberNotExist)
    end

    describe '#overwrite' do
      specify 'overwrites events data and metadata' do
        client.publish(
          old = OrderCreated.new(event_id: SecureRandom.uuid, data: {customer_id: 44}),
          stream_name: "some_stream",
        )
        old.data[:amount] = 12
        old.metadata[:server] = "eu-west"
        client.with_metadata(nonono: "no") do
          client.overwrite(old)
        end

        new = client.read.backward.limit(1).each.first
        expect(new).to eq(old)
        expect(new.data.fetch(:customer_id)).to eq(44)
        expect(new.data.fetch(:amount)).to eq(12)
        expect(new.metadata.fetch(:server)).to eq("eu-west")
        expect(new.metadata).not_to have_key(:nonono)
      end

      specify 'overwrites event type' do
        client.publish(
          old = OrderCreated.new(event_id: SecureRandom.uuid, data: {customer_id: 44}, metadata: {server: "eu-west"}),
          stream_name: "some_stream",
        )
        client.overwrite([ProductAdded.new(event_id: old.event_id, data: old.data, metadata: old.metadata)])

        new = client.read.backward.limit(1).each.first
        expect(new.class).to eq(ProductAdded)
        expect(new.data).to eq(old.data)
        expect(new.metadata.to_h).to eq(old.metadata.to_h)
        expect(new.data.fetch(:customer_id)).to eq(44)
        expect(new.metadata.fetch(:server)).to eq("eu-west")
      end

      specify 'overwrites is chainable' do
        expect { client.overwrite([]).overwrite([]).overwrite([]) }.not_to raise_error
      end
    end

    describe "#streams_of" do
      specify do
        event_1 = OrderCreated.new(event_id: SecureRandom.uuid, data: {})
        event_2 = OrderCreated.new(event_id: SecureRandom.uuid, data: {})
        event_3 = OrderCreated.new(event_id: SecureRandom.uuid, data: {})
        event_4 = OrderCreated.new(event_id: SecureRandom.uuid, data: {})
        stream_a = Stream.new('Stream A')
        stream_b = Stream.new('Stream B')
        stream_c = Stream.new('Stream C')
        client.append([event_1, event_2], stream_name: stream_a.name)
        client.append([event_3], stream_name: stream_b.name)
        client.link(event_1.event_id, stream_name: stream_c.name)

        expect(client.streams_of(event_1.event_id)).to eq [stream_a, stream_c]
        expect(client.streams_of(event_2.event_id)).to eq [stream_a]
        expect(client.streams_of(event_3.event_id)).to eq [stream_b]
        expect(client.streams_of(event_4.event_id)).to eq []
      end
    end

    specify "#inspect" do
      object_id = client.object_id.to_s(16)
      expect(client.inspect).to eq("#<RubyEventStore::Client:0x#{object_id}>")
    end
  end
end
