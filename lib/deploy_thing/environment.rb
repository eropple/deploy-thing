module DeployThing

  # An `Environment` contains the DeployThing configurations (as opposed to an
  # {Models#Config}, which contains application configs).
  class Environment
    attr_reader :db
    attr_reader :aws_credentials
    attr_reader :s3_bucket

    def initialize(db, aws_credentials, s3_bucket)
      @db = db
      @aws_credentials = aws_credentials
      @s3_bucket = s3_bucket
    end

    def self.from_file(filename)
      Environment::from_hash(YAML.load_file(filename))
    end

    def self.from_hash(hash)
      require 'hashie'
      cfg = Hashie::Mash.new(hash)

      db = Sequel.connect(cfg[:db])

      aws_credentials =
        if cfg[:aws][:iam]
          Aws::InstanceProfileCredentials.new
        elsif cfg[:aws][:shared]
          Aws::SharedCredentials.new(:profile_name => cfg[:aws][:shared].to_s)
        else
          Aws::Credentials.new(:access_key_id => cfg[:aws][:access_key],
                               :secret_access_key => cfg[:aws][:secret_key])
        end

      s3_client = Aws::S3::Client.new(region: cfg[:s3][:region], credentials: aws_credentials)
      s3_resource = Aws::S3::Resource.new(client: s3_client)

      s3_bucket = s3_resource.bucket(cfg[:s3][:bucket])
      raise "No bucket '#{cfg[:s3][:bucket]}' in region '#{cfg[:s3][:region]}'." unless s3_bucket

      Environment.new(db, aws_credentials, s3_bucket)
    end
  end
end