module UniProp
  # 完全なメタデータが存在する事を前提とし、必要なファイルをキャッシュにダウンロードしてVersionと同じ動きをするクラス
  class EfficientVersion < Version    
    # @return [Set<PropFile>]
    def files
      return @files if @files
      @files = version_metadata.propfile_names.map { create_propfile(_1) }

      # PropertyAliases, PropertyValueAliasesはメタデータに記述されない
      @files << property_aliases_file
      @files << property_value_aliases_file
      @files
    end

    # @return [Array<String>?]
    def unihan_file_names
      version_metadata.unihan_file_names
    end

    # @return [Array<Property>]
    def unihan_properties
      version_metadata.unihan_properties
    end
    
    # @return [PropFile]
    def find_file(propfile)
      super(propfile, confirm: false)
    end

    # @param [String] filename basename_prefixに該当するファイル名
    # @return [PropFile]
    def create_propfile(filename)
      if UniPropUtils::FileManager.unihan_file?(filename, unihan_file_names)
        return PropFile::UnihanFile.new(filename, self)
      else
        return PropFile.new(filename, self)
      end
    end
  end
end