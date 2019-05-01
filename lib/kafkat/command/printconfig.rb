module Kafkat
  module Command
    class PrintConfig < Base
      register_as 'printconfig'

      usage 'printconfig',
            'Print configuration'

      def run
        pp config
      end
    end
  end
end
