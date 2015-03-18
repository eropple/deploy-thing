module DeployThing

  # An `Environment` contains the DeployThing configurations (as opposed to an
  # {Models#Config}, which contains application configs).
  class Environment
    attr_reader :db
    attr_reader :aws_credentials

    def initialize(db, aws_credentials)
      @db = db
      @aws_credentials = aws_credentials
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

      Environment.new(db, aws_credentials)
    end
  end
end