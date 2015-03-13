module DeployThing
  module Util
    module Files

      def self.edit_object(body, extension = ".json")
        Tempfile.create(['deploything_editfile', extension]) do |f|
          f.write(body)
          f.close

          if system("#{ENV['EDITOR']} '#{f.path}'")
            IO.read(f.path)
          else
            body
          end
        end
      end
      
    end
  end
end