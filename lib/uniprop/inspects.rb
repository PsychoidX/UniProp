# :nocov:
module UniProp
  class PropFile
    # @private
    def inspect
      "#<#{self.class.name} #{basename_prefix}>"
    end
  end

  class Version
    # @private
    def inspect
      "#<#{self.class.name} #{major}.#{minor}.#{tiny}>"
    end
  end
  
  class EfficientVersion < Version
    # @private
    def inspect
      "#<#{self.class} #{version_metadata.version.version_name}>"
    end
  end

  class PropFileValueGroup
    # @private
    def inspect
      "#<#{self.class.name} #{propfile.basename_prefix}>"
    end
  end

  class ActualPropertyValueGroup
      # @private
      def inspect
        property_names = properties.map { _1.longest_alias }
                                    .join(', ')
        "#<#{self.class.name} #{propfile.basename_prefix} (#{property_names})>"
      end
  end

  class RevisingHintGenerator
    # @private
    def inspect
      "#<#{self.class} #{recreator.old_version.version_name},#{recreator.new_version.version_name}>"
    end
  end

  class MetaData
    # @private
    def inspect
      "#<#{self.class.name}>"
    end
  end

  class VersionMetaData
    # @private
    def inspect
      "#<#{self.class.name} #{version.major}.#{version.minor}.#{version.tiny}>"
    end
  end

  class PropFileMetaData
    # @private
    def inspect
      "#<#{self.class.name} #{propfile.basename_prefix}>"
    end
  end

  class VersionMetaDataValidator
    # @private
    def inspect
      "#<#{self.class.name} #{version_metadata.version.major}.#{version_metadata.version.minor}.#{version_metadata.version.tiny}>"
    end
  end

  class PropData
      # @private
      def inspect
        "#<#{self.class.name}>"
      end
  end

  module Alias
    # @private
    def inspect
      "#<#{self.class.name} #{longest_alias}>"
    end
  end

  class BasePropertyValueGroup
    # @private
    def inspect
      "#<#{self.class.name}>"
    end
  end

  class PropertyMetaData
    # @private
    def inspect
      "#<#{self.class.name}>"
    end
  end

  class VersionPropertyMetaData
    # @private
    def inspect
      "#<#{self.class.name}>"
    end
  end

  class UnicodeManager
    def inspect
      "#<#{self.class.name}>"
    end
  end

  class VersionManager
    def inspect
      "#<#{self.class.name} #{version.version_name}>"
    end
  end
end
# :nocov: