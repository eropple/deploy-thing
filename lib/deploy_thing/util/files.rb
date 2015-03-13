module DeployThing
  module Util
    module Files

      def self.edit_interactively(body, extension = ".json")
        raise "EDITOR must be set." unless ENV['EDITOR']
        raise "Must be at a TTY." unless $stdin.tty?

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