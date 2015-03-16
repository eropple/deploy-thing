Sequel.migration do
  change do
    create_table(:applications) do
      primary_key :id
      column      :name, String
      index [:name], :unique => true
    end

    create_table(:config_files) do
      primary_key :id
      foreign_key :application_id, :applications
      column      :ordinal, Fixnum
      column      :name, String
      index [:application_id, :ordinal, :name], :unique => true

      column      :created_at, Time
      column      :updated_at, Time
      column      :content, String
    end

    create_table(:configs) do
      primary_key :id
      foreign_key :application_id, :applications
      column      :ordinal, Fixnum
      index [:application_id, :ordinal], :unique => true

      column      :created_at, Time
      column      :updated_at, Time
    end

    create_table(:config_file_mapping) do
      primary_key :id
      foreign_key :config_id, :configs
      foreign_key :config_file, :config_files
    end

    create_table(:deploys) do
      primary_key :id
      foreign_key :application_id, :applications
      column      :ordinal, Fixnum
      index [:application_id, :ordinal], :unique => true

      column      :created_at, Time
      column      :updated_at, Time
      column      :artifact_version, String
      foreign_key :config_id, :configs
    end
end