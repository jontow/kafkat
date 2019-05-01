module Kafkat
  class Config
    CONFIG_PATHS = [
      '~/.kafkatcfg',
      '/etc/kafkatcfg'
    ]

    class NotFoundError < StandardError; end
    class ParseError < StandardError; end

    attr_reader :kafka_path
    attr_reader :log_path
    attr_reader :zk_path
    attr_reader :implicit_consent
    attr_reader :debug

    def self.load!
      string = nil
      e = nil

      CONFIG_PATHS.each do |rel_path|
        begin
          path = File.expand_path(rel_path)
          string = File.read(path)
          break
        rescue => e
        end
      end

      raise e if e && string.nil?

      json = JSON.parse(string)
      self.new(json)

    rescue Errno::ENOENT
      raise NotFoundError
    rescue JSON::JSONError
      raise ParseError
    end

    def initialize(json)
      @kafka_path = json['kafka_path']
      @log_path = json['log_path']
      @zk_path = json['zk_path']

      # Boolean: controls whether "Proceed? (y/n)" prompts are shown or not
      if json['implicit_consent'].nil?
        @implicit_consent = false
      else
        @implicit_consent = json['implicit_consent']
      end

      # Boolean: controls whether debugging info is printed
      if json['debug'].nil?
        @debug = false
      else
        @debug = json['debug']
      end
    end
  end
end
