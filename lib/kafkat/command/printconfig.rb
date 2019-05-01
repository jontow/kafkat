module Kafkat
  module Command
    class PrintConfig < Base
      register_as 'printconfig'

      usage 'printconfig',
            'Print configuration'

      def run
        p config
      end
    end
  end
end
