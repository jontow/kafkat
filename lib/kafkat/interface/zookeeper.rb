require 'thread'
require 'zk'

module Kafkat
  module Interface
    class Zookeeper
      class NotFoundError < StandardError; end
      class WriteConflictError < StandardError; end

      attr_reader :zk_path

      def initialize(config)
        @zk_path = config.zk_path
        @debug = config.debug
      end

      def get_broker_ids
        zk.children(brokers_path)
      end

      def get_brokers(ids=nil)
        brokers = {}
        ids ||= zk.children(brokers_path)

        threads = ids.map do |id|
          id = id.to_i
          Thread.new do
            begin
              brokers[id] = get_broker(id)
            rescue
            end
          end
        end
        threads.map(&:join)

	pp brokers if @debug
        brokers
      end

      def get_broker(id)
        path = broker_path(id)
        string = zk.get(path).first
        json = JSON.parse(string)
        host, port = json['host'], json['port']
        Broker.new(id, host, port)
      rescue ZK::Exceptions::NoNode
        raise NotFoundError
      end

      def get_topic_names()
        return zk.children(topics_path)
      end

      def get_topics(names=nil)
        error_msgs = {}
        topics = {}

        if names == nil
          pool.with_connection do |cnx|
            names = cnx.children(topics_path)
          end
        end

        names.each do |name|
          begin
            topics[name] = get_topic(name)
          rescue => e
            error_msgs[name] = e
          end
        end

        unless error_msgs.empty?
          STDERR.print "ERROR: zk cmds failed on get_topics: \n#{error_msgs.values.join("\n")}\n"
          exit 1
        end

	pp topics if @debug
        topics
      end

      def get_topic(name)
        partition_queue = Queue.new
        path1 = topic_path(name)
        path2 = topic_partitions_path(name)

        partitions = []
        topic_string = pool.with_connection { |cnx| cnx.get(path1).first }
        partition_ids = pool.with_connection { |cnx| cnx.children(path2) }

        p name if @debug

        topic_json = JSON.parse(topic_string)

        threads = partition_ids.map do |id|
          id = id.to_i

          Thread.new do
            path3 = topic_partition_state_path(name, id)
            partition_string = pool.with_connection { |cnx| cnx.get(path3).first }
            partition_json = JSON.parse(partition_string)
            replicas = topic_json['partitions'][id.to_s]
            leader = partition_json['leader']
            isr = partition_json['isr']

            partition_queue << Partition.new(name, id, replicas, leader, isr)
          end
        end
        threads.map(&:join)

        until partition_queue.empty? do
          partitions << partition_queue.pop
        end

        partitions.sort_by!(&:id)
        Topic.new(name, partitions)
      rescue ZK::Exceptions::NoNode
        raise NotFoundError
      end

      def get_controller
        string = zk.get(controller_path).first
        controller_json = JSON.parse(string)
        controller_id = controller_json['brokerid']
        get_broker(controller_id)
      rescue ZK::Exceptions::NoNode
        raise NotFoundError
      end

      def write_leader(partition, broker_id)
        path = topic_partition_state_path(partition.topic_name, partition.id)
        string, stat = zk.get(path)

        partition_json = JSON.parse(string)
        partition_json['leader'] = broker_id
        new_string = JSON.dump(partition_json)

        unless zk.set(path, new_string, version: stat.version)
          raise ChangedDuringUpdateError
        end
      end

      private

      def pool
        @pool ||= ZK.new_pool(zk_path, :min_clients => 10, :max_clients => 300, :timeout => 1)
      end

      def zk
        @zk ||= ZK.new(zk_path)
      end

      def brokers_path
        '/brokers/ids'
      end

      def broker_path(id)
        "/brokers/ids/#{id}"
      end

      def topics_path
        '/brokers/topics'
      end

      def topic_path(name)
        "/brokers/topics/#{name}"
      end

      def topic_partitions_path(name)
        "/brokers/topics/#{name}/partitions"
      end

      def topic_partition_state_path(name, id)
        "/brokers/topics/#{name}/partitions/#{id}/state"
      end

      def controller_path
        "/controller"
      end
    end
  end
end
