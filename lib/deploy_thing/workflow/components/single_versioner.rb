module DeployThing
  module Workflow
    module Components
      class SingleVersioner

        def initialize(logger, application_name, thing_type, s3_bucket, subdirectory_name, type_name = Summary, &block)
          @logger = logger
          @application_name = application_name
          @thing_type = thing_type
          @s3_bucket = s3_bucket
          @subdirectory_name = subdirectory_name
          @type_name = Summary

          @parse_block = block;
        end

        def summaries
          s = @s3_bucket.objects(:prefix => "#{@application_name}/#{@subdirectory_name}/").map do |obj|
            @type_name.new(File.basename(obj.key, ".*"), obj.last_modified)
          end
          s.sort! { |a, b| a.id <=> b.id }
          s
        end

        def head
          s = summaries || []
          s.length > 0 ? s.last : nil
        end

        def head_id
          h = head
          h == nil ? 0 : h.id
        end

        def read(id)
          obj = @s3_bucket.object("#{@application_name}/#{@subdirectory_name}/#{id}.json")
          obj.exist? ? obj.get[:body].read : nil
        end

        def put(body)
          id = head_id + 1

          obj = @s3_bucket.object("#{@application_name}/#{@subdirectory_name}/#{id}.json")
          @logger.info "Uploading #{@thing_type} '#{id}'."
          obj.put(:body => body)
        end

        def edit
          raise "EDITOR environment variable must be set." unless ENV["EDITOR"]
          raise "Edit methods must be called from a TTY." unless $stdin.tty?

          body = read(head_id) || ""
          new_body = DeployThing::Util::Files::edit_object(body)

          if body == new_body
            @logger.info "No change to #{@thing_type}; will not upload."
          else
            new_body = @parse_block.call(new_body) unless !@parse_block
            put(new_body)
          end
        end

      end
    end
  end
end