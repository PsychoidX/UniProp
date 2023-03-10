module UniProp
  class VersionNotMatchedError < StandardError; end
  class ParseError < StandardError; end
  class PropertyNotFoundError < StandardError
    def initialize(searched_property)
      super("property not found. (searched property: #{searched_property})")
    end
  end
  class PropertyValueTypeNotExistsError < StandardError
    def initialize(type)
      super("#{type} does not exist as property value type.")
    end
  end
  class FileExistsError < StandardError
    def initialize(file_path)
      super("#{file_path} is already exists. Please delete the file and run again.")
    end
  end
  class FileNotFoundError < StandardError; end
  class MetaDataNotFoundError < StandardError; end
  class MetaDataParseError < StandardError; end
  class PropDataDifferentError < StandardError; end
  class MetaDataExistsError < StandardError
    def initialize(version_name)
      super("Metadata for #{version_name} is already exists. Please delete the data and run again.")
    end
  end
  class VersionMetaDataNotExistsError < StandardError; end
  class PropertyValueNotFoundError < StandardError; end
  class VersionDifferentError < StandardError; end
end