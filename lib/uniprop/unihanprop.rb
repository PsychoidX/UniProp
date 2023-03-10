module UniProp
  class UnihanProp
    attr_reader :unihan_files, :version
    
    # @param [Set<PropFile>] unihan_files UnihanのPropFileオブジェクト
    def initialize(unihan_files)
      @unihan_files = unihan_files

      versions = @unihan_files.map { _1.version }.uniq
      if versions.size <= 1
        @version = versions[0]
      else
        raise VersionDifferentError, "All versions of files in unihan_files should be the same."
      end
    end

    # unihan_filesに含まれるすべてのPropFileのshaped_linesを連結したオブジェクトを取得
    # @return [Array<Array<String>>]
    def shaped_lines
      @shaped_lines ||= unihan_files.map { _1.shaped_lines }
                                    .reject { _1.empty? || !_1 }
                                    .reduce([], :+)
    end

    # Unihanに含まれるプロパティ名を取得
    # @note Unihanのファイルは必ず2列目にプロパティ名が記述されている
    # @return [Set<String>]
    def property_names
      @property_names ||= shaped_lines.map { _1[1] }
                                      .reject { !_1 }
                                      .to_set
    end

    # Unihanに含まれるプロパティを取得
    # @return [Set<Property>] 
    def unihan_properties
      return @unihan_properties if @unihan_properties

      @unihan_properties = Set.new
      return if !version

      property_names.each do |property_name|
        if version.has_property?(property_name)
          # Unihanのプロパティの一部はPropertyAliases.txtにも記述されている
          # PropertyAliasesの方がプロパティのエイリアスなど、掲載されている情報が多いため、PropertyAliasesの記述を優先して使用
          @unihan_properties << version.find_property(property_name)
        else
          @unihan_properties << UniProp::Property.new(version, property_name)
        end
      end

      @unihan_properties
    end

    # @return [Hash<String,Array<String>>]
    def property_name_to_shaped_lines
      return @property_nameto_shaped_lines if @property_name_to_shaped_lines
      @property_name_to_shaped_lines = shaped_lines.group_by { _1[1] }
      @property_name_to_shaped_lines.delete(nil)
      @property_name_to_shaped_lines
    end

    # @return [Hash<Property,Array<String>>]
    def property_to_shaped_lines
      return @property_to_shaped_lines if @property_to_shaped_lines

      @property_to_shaped_lines = Hash.new

      property_name_to_shaped_lines.each do |property_name, lines|
        if version.has_unihan_property?(property_name)
          prop = version.find_unihan_property(property_name)
          @property_to_shaped_lines[prop] = lines
        end
      end

      @property_to_shaped_lines
    end

    # @return [UnihanValueGroup]
    def unihan_value_group(property)
      return @property_to_unihan_value_group[property] if @property_to_unihan_value_group && @property_to_unihan_value_group[property]

      @property_to_unihan_value_group ||= {}

      unihan_value_group = UnihanValueGroup.new(property, property_to_shaped_lines[property])

      @property_to_unihan_value_group[property] = unihan_value_group
      @property_to_unihan_value_group[property]
    end
  end
end