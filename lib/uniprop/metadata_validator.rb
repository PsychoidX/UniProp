module UniProp
  class MetaDataValidator
    attr_reader :metadata

    # @param [MetaData] metadata
    def initialize(metadata)
      @metadata = metadata
    end

    # メタデータが記述されているバージョンすべてで検証を実行
    def validate
      metadata.prop_data.versions.each do |version|
        if version.has_version_metadata?
          version.version_metadata.version_metadata_validator.run_all_validations
        end
      end
    end
  end

  class VersionMetaDataValidator
    attr_reader :version_metadata, :version

    def initialize(version_metadata)
      @version_metadata = version_metadata
      @version = @version_metadata.version

      # validate_files_shortage, validate_files_excessでは、実際のキャッシュとメタデータを照らし合わせて検証を行う必要があるため、@versionはEfficientVersionではなくVersionでなければならない。
      if @version.class != Version
        raise TypeError, "The argument must be a VersionMetaData object associated with Version object (not EfficientVersion)"
      end
    end

    # 全ての検証を実行
    def run_all_validations
      puts "== validation results for version #{version.version_name} =="
      validate_files_shortage(reconfirm: true)
      validate_files_excess(reconfirm: false)
      validate_properties_shortage
      validate_properties_excess
      validate_row_perfection
      validate_column_perfection
      validate_type

      if version.has_unihan?
        validate_unihan_properties_shortage
        validate_unihan_properties_excess
      end
    end
    
    # メタデータの記述が不足しているファイルを取得
    # @return [Set<PropFile>]
    def metadata_insufficient_files
      return @metadata_insufficient_files if @metadata_insufficient_files

      @metadata_insufficient_files = version.files.reject{_1.is_meta_file?} - version_metadata.actual_propfiles

      @metadata_insufficient_files
    end

    # メタデータ内で記述が不足しているファイルを標準出力に出力
    def validate_files_shortage(reconfirm: false)
      version.files(reconfirm: reconfirm, reload: reconfirm) if reconfirm
      
      if metadata_insufficient_files.empty?
        puts "All files are described in the metadata"
      else
        puts "Files that are not described in the metadata"
        metadata_insufficient_files.each { puts "・#{_1.basename_prefix}" }
      end
    end

    # メタデータ内に余分に記述されたファイル(実際には存在しないにも関わらず、メタデータに記述されたファイル)を標準出力に出力
    def validate_files_excess(reconfirm: false)
      version.files(reconfirm: reconfirm, reload: reconfirm) if reconfirm

      nonexist_files = version_metadata.propfile_names.filter { !version.has_file?(_1) }

      if nonexist_files.empty?
        puts "There are no excessive files in the metadata."
      else
        puts "Files that are described in the metadata even though it does not actually exist"
        nonexist_files.each { puts "・#{_1}" }
      end
    end

    # メタデータ内で記述が不足しているプロパティを標準出力に出力
    def validate_properties_shortage
      metadata_insufficient_properties = version.properties - version_metadata.actual_properties

      if metadata_insufficient_properties.empty?
        puts "All properties are described in the metadata"
      else
        puts "Properties that not described in the metadata"
        metadata_insufficient_properties.each { puts "・#{_1.longest_alias}" }
      end
    end

    # メタデータ内に余分に記述されたプロパティ(実際には存在しないにも関わらず、メタデータに記述されたプロパティ)を標準出力に出力
    def validate_properties_excess
      nonexist_props = version_metadata.property_names
        .reject { _1=="" || _1=="codepoint" }
        .reject { version.has_property?(_1) }
      
      if nonexist_props.empty?
        puts "There are no excessive properties in the metadata."
      else
        puts "Properties that's described in the metadata even though it does not actually exist"
        nonexist_props.each { puts "・#{_1}" }
      end
    end

    # information_containing_rangesのうち、block_rangesに含まれていない範囲を返す
    # @param [Array<Range<Integer>>] block_ranges
    # @param [Array<Range<Integer>>] information_containing_ranges
    # @return [Array<Range<Integer>>]
    def metadata_insufficient_ranges(block_ranges, information_containing_ranges)
      result = information_containing_ranges
      block_ranges.each do |block_range|
        pre_result = result
        result = []
        pre_result.each { result.concat(UniPropUtils::RangeProcessor.cut_internal(_1, block_range.begin, block_range.end)) }
      end      
      result
    end

    # 各PropFileの、メタデータに記述されていない行の範囲を取得
    # @return [Hash<PropFile,Array<Range>]
    def propfile_to_metadata_insufficient_ranges
      return @propfile_to_metadata_insufficient_ranges if @propfile_to_metadata_insufficient_ranges

      @propfile_to_metadata_insufficient_ranges = Hash.new { |hash,key| hash[key]=[] }

      version_metadata.propfile_metadatas.each do |propfile_metadata|
        propfile = propfile_metadata.propfile

        @propfile_to_metadata_insufficient_ranges[propfile] = metadata_insufficient_ranges(propfile_metadata.property_written_ranges, propfile.information_containing_ranges)
      end
      
      @propfile_to_metadata_insufficient_ranges
    end

    # メタデータに記述されていない行の範囲が存在するファイルを標準出力に出力(Unihan, メタデータが記述されていないファイルを除く)
    def validate_row_perfection      
      if propfile_to_metadata_insufficient_ranges.all? { _2.empty? }
        puts "There are no files for which a file name is described in the metadata but for which this information is missing."
      else
        puts "Ranges where metadata is missing in propfiles"
        propfile_to_metadata_insufficient_ranges.each do |propfile, insufficient_ranges|
          if !insufficient_ranges.empty?
            puts "・#{propfile.basename_prefix}"
  
            insufficient_ranges.each do |range|
              if range.size==1
                puts "\t#{range.begin}"
              else
                puts "\t#{range.begin} to #{range.end}"
              end
            end
          end
        end
      end
    end

    # 実際の列数とメタデータに記述されている列数に違いがあるファイルを標準出力に出力
    def validate_column_perfection
      error_logs = []
      version_metadata.propfile_metadatas.each do |propfile_metadata|
        propfile_metadata.blocks.each_with_index do |block, block_no|
          metadata_col_size = block.content.size
          actual_col_size = propfile_metadata.propfile.max_column_size(block.range)

          if metadata_col_size != actual_col_size
            error_logs << "#{propfile_metadata.propfile.basename_prefix} (in block #{block_no})\n\tmetadata column size: #{metadata_col_size}\n\tactual column size: #{actual_col_size}"
          end
        end
      end

      if error_logs.empty?
        puts "There are no difference in column size between the metadata and the actual description in all files"
      else
        puts "Files that the number of columns differs between the metadata and the actual description"
        error_logs.each { puts _1 }
      end
    end

    # validate_typeで出力するための理想の型の名称を取得
    # @param [Property] prop
    # @return [String]
    def expected_type(prop)
      type = prop.property_value_type

      case type
      when :string, :numeric
        return type
      when :binary, :catalog, :enumerated
        return "#{type} (#{prop.longest_alias})"
      when :miscellaneous
        return prop.miscellaneous_format
      end
    end
    
    # メタデータと実際のファイルで、記述されているべき値の型に違いがある箇所を出力
    MismatchPosition = Struct.new(:propfile, :column, :expected_type, :row_ranges)
    def validate_type
      # 違いがある箇所を検出
      mismatches = []

      version_metadata.propfile_metadatas.each do |propfile_metadata|
        propfile = propfile_metadata.propfile

        propfile_metadata.blocks.each do |block|
          block.content.each_with_index do |prop, col|
            # 列の値がArrayを使用して記述されている場合、検証をスキップする
            next if !prop || prop.class==Array

            mismatch_row_ranges = UniPropUtils::RangeProcessor.sub(
              block.range,
              propfile.verbose_property_value_type_match_ranges(col, prop)
            )
            
            if !mismatch_row_ranges.empty?
              mismatches << MismatchPosition.new(propfile, col, expected_type(prop), mismatch_row_ranges)
            end
          end
        end
      end

      # 検出結果を出力
      if mismatches.empty?
        puts "In all blocks in the metadata, the type of the property described in the block matches the type of the values in the actual file."
      else
        mismatches.each do |mismatch|
          puts "According to the metadata, column #{mismatch.column} in #{mismatch.propfile.basename_prefix} should be #{mismatch.expected_type} value, but the following line is wrong."

          mismatch.row_ranges.each do |range|
            if range.size==1
              puts "\t#{range.begin}"
            else
              puts "\t#{range.begin} to #{range.end}"
            end
          end
        end
      end
    end

    # メタデータに記述が不足しているUnihanプロパティを出力
    def validate_unihan_properties_shortage
      metadata_insufficient_properties = []

      version.unihanprop.unihan_properties.each do |prop|
        if version_metadata.unihan_property_names.all? { !prop.has_alias?(_1) }
          metadata_insufficient_properties << prop
        end
      end

      if metadata_insufficient_properties.empty?
        puts "All Unihan properties are described in the metadata"
      else
        puts "Unihan properties that's not described in the metadata"
        metadata_insufficient_properties.each { puts "・#{_1.longest_alias}" }
      end
    end

    # メタデータ内に余分に記述されたUnihanプロパティ(実際には存在しないにも関わらず、メタデータに記述されたUnihanプロパティ)を出力
    def validate_unihan_properties_excess
      nonexist_prop_names = []

      version_metadata.unihan_property_names.each do |prop_name|
        if version.unihanprop.unihan_properties.all? { !_1.has_alias?(prop_name) }
          nonexist_prop_names << prop_name
        end
      end
    
      if nonexist_prop_names.empty?
        puts "There are no excessive Unihan properties in the metadata."
      else
        puts "Unihan properties that's described in the metadata even though it does not actually exist"
        nonexist_prop_names.each { puts "・#{_1}" }
      end
    end
  end
end