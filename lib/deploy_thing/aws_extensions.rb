require 'aws-sdk'

module Aws
  module S3
    module ObjectExtensions
      def exist?
        begin
          self.last_modified
          true
        rescue Aws::S3::Errors::NotFound
          false
        end
      end
    end

    class Object
      include ObjectExtensions
    end

    class ObjectSummary
      include ObjectExtensions
    end
  end
end