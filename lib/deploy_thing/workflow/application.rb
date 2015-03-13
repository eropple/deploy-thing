module DeployThing
  module Workflow
    class Application
      attr_reader :name
      attr_reader :policies
      attr_reader :userdata
      attr_reader :deploys

      def initialize(logger, s3_bucket, name)
        @logger = logger

        @s3_bucket = s3_bucket
        @name = name.to_s.downcase.strip
        @policies =
          Components::SingleVersioner.new(logger, @name, "policy", s3_bucket, "policies") do |body|
            JSON.pretty_generate(JSON.parse(body))
          end
        @userdata = Components::SingleVersioner.new(logger, @name, "userdata", s3_bucket, "userdata")
        @deploys = Components::DeployVersioner.new(self, logger, s3_bucket)

        raise "Application name must be non-empty." unless @name.length > 0
      end



      def config_summaries
        configs = {}

        @s3_bucket.objects(:prefix => "#{@name}/configs").map do |obj|
          tokens = obj.key.split("/", 4)

          id = tokens[2].to_i
          hash = configs[id] || { :id => id, :time => obj.last_modified, :files => [] }
          hash[:time] = [ hash[:time], obj.last_modified ].max
          hash[:files] << tokens[3]

          configs[id] = hash
        end

        configs.map { |cfg| ConfigSummary.new(cfg[1][:id], cfg[1][:time], cfg[1][:files]) }
      end

      def head_config
        configs = config_summaries
        configs.length > 0 ? configs.last : nil
      end

      def head_config_id
        c = head_config
        c == nil ? 0 : c.id
      end

      def config_files(id)
        @s3_bucket.objects(:prefix => "#{@name}/configs/#{id}").map do |obj|
          obj.key.split("/", 4)[3]
        end
      end

      def read_config(id, key)
        obj = @s3_bucket.object("#{@name}/configs/#{id}/#{key}")
        obj.exist? ? obj.get[:body].read : nil
      end

      def put_config(key, body)
        new_id = clone_config
        upload_config_no_bump(new_id, key, body)

        @logger.info "Uploaded '#{key}', creating config version '#{new_id}'."
      end

      def edit_config(key)
        binding.pry
        body = read_config(head_config_id, key) || ""
        new_body = edit_object(body, File.extname(key))

        if body == new_body
          @logger.info "No change to config; will not upload."
        else
          put_config(key, new_body)
        end
      end

      def delete_config(key)
        current_id = head_config.id
        if !@s3_bucket.object("#{@name}/configs/#{current_id}/#{key}").exist?
          raise "'#{key}' not a valid config key (file not in S3."
        end

        new_id = clone_config
        del_obj = @s3_bucket.object("#{@name}/configs/#{new_id}/#{key}")

        if del_obj.exist?
          del_obj.delete
          @logger.info "Deleted '#{del_obj.key}', creating config version '#{new_id}'."
        end
      end


      def deploy_summaries
        deploys = @s3_bucket.objects(:prefix => "#{@name}/deploys/").map do |obj|
          Summary.new(File.basename(obj.key, ".json"), obj.last_modified)
        end
        deploys.sort! { |a, b| a.id <=> b.id }

        deploys
      end






      private
      def clone_config
        current = head_config

        if current != nil
          next_id = current.id + 1

          cloning_objects = @s3_bucket.objects(:prefix => "#{@name}/configs/#{current.id}/")
          cloning_objects.each do |obj|
            binding.pry
            new_obj = @s3_bucket.object("#{@name}/configs/#{next_id}/#{File.basename(obj.key)}")
            @logger.debug "Copying '#{obj.key}' to '#{new_obj.key}'."

            new_obj.put(:body => obj.get[:body].read)
          end

          next_id
        else
          1
        end
      end

      def upload_config_no_bump(id, key, body)
        put_obj = @s3_bucket.object("#{@name}/configs/#{id}/#{key}")
        put_obj.put(:body => body)
      end
    end
  end
end