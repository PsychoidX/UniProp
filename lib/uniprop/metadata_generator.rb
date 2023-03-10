module UniProp
  class PropData
    # メタデータを生成する
    # @param [Pathname] output_path メタデータを生成するパス
    # @param [Version] generated_version 作成するメタデータのバージョン
    # @param [Version/EfficientVersion] using_version generated_versionのメタデータの生成に使用されるバージョン
    # @raise [FileExistsError] pathに既にファイルが存在している場合に発生。生成されたメタデータを修正した後に再度メソッドを実行してしまい、メタデータが上書きされる事を防ぐための措置。
    # @raise [MetaDataExistsError] generated_versionのメタデータが既に存在する場合に発生
    def generate_metadata(output_path, using_version, generated_version)
      if output_path.exist?
        raise FileExistsError.new(output_path)
      end

      generated_metadata = {}
      generated_metadata["version_names"] = metadata.version_names
      generated_metadata["version_metadatas"] = metadata.raw_version_metadatas
      generated_metadata["version_metadatas"] << generate_version_metadata(using_version, generated_version)

      generated_metadata["version_metadatas"].sort_by! { Version.name_to_weight(_1["version_name"]) }
      
      output_path.write(JSON.pretty_generate(generated_metadata))
    end

    # @return [Hash<String,Object>] version_metadataに相当するHash
    def generate_version_metadata(using_version, generated_version)
      if using_version.prop_data != generated_version.prop_data
        raise PropDataDifferentError, "Unable to recreate metadata because the PropData objects of two versions passed when initialized are different."
      end

      prop_data = using_version.prop_data

      if prop_data.metadata.has_raw_version_metadata?(generated_version.version_name)
        raise MetaDataExistsError.new(generated_version.version_name)
      end

      recreator = VersionMetaDataRecreator.new(using_version, generated_version)

      version_metadata = {}
      version_metadata["version_name"] = generated_version.version_name
      version_metadata["file_formats"] = recreator.generate_file_formats

      if generated_version.has_unihan?
        version_metadata["unihan_files"] = generated_version.unihanprop.unihan_files.map { _1.basename_prefix }
        version_metadata["unihan_properties"] = generated_version.unihanprop.unihan_properties.map { _1.longest_alias }
      end

      version_metadata
    end

    # PropDataオブジェクト作成時に渡したメタデータを使用し、プロパティ中心のメタデータを生成
    # @param [EfficientVersion] version 生成するバージョン
    # @param [Pathname] output_path メタデータを生成するパス
    def generate_property_metadata(output_path, version)
      if property_metadata.has_raw_version_metadata?(version.version_name)
        return
      end

      md = property_metadata.raw_version_metadatas

      if metadata.has_raw_version_metadata?(version.version_name)
        puts "generating property metadata for #{version.version_name} ... "
        md << generate_vsn_property_metadata(version)
      else
        raise MetaDataNotFoundError, "metadata for #{version.version_name} is not found."
      end

      output_path.write(JSON.pretty_generate(md))
    end

    # バージョン内のすべてのプロパティに対し、プロパティ中心のメタデータを生成
    # @param [EfficientVersion] version
    # @return [Hash<String,Object>] versionのプロパティ中心のメタデータ
    def generate_vsn_property_metadata(version)
      version_property_metadata = {}
      version_property_metadata["version_name"] = version.version_name
      version_property_metadata["properties"] = version.properties.map { generate_prop_property_metadata(version, _1) }
      version_property_metadata
    end

    # プロパティに関するメタデータを生成
    # @param [EfficientVersion] version
    # @param [Property] property version内のプロパティ
    # @return [Hash<String,Object>] プロパティに関するメタデータ
    def generate_prop_property_metadata(version, property)
      property_metadata = {}
      property_metadata["property_name"] = property.longest_alias
      
      property_metadata["positions"] = []
      positions = property.actual_positions.to_a
      
      positions.each do |position|
        property_metadata["positions"] << {
          "file_name" => position.propfile.basename_prefix,
          "block" => position.block,
          "range" => position.range.to_s,
          "columns" => position.columns.size==1 ? position.columns[0] : position.columns
        }
      end

      property_metadata["unihan"] = property.is_unihan_property?
      property_metadata["type"] = property.property_value_type.to_s
      property_metadata["derived"] = positions.any? { _1.propfile.is_derived? }
      
      property_metadata
    end
  end

  class VersionMetaDataRecreator
    attr_reader :using_version, :using_version_metadata, :generated_version
    # using_versionのメタデータを使用してgenerated_versionのメタデータを作成するためのオブジェクトを生成
    # @param [Version] using_version
    # @param [Version/EfficientVersion] generated_version
    def initialize(using_version, generated_version)
      @using_version = using_version
      @using_version_metadata = using_version.version_metadata
      @generated_version = generated_version
    end

    # メタデータのfile_formats項を生成
    # @return [Array<Hash<String,Object>>]
    def generate_file_formats
      return @file_formats if @file_formats
      @file_formats = []

      using_version.files.each_with_index do |file, i|
        puts "recreating metadata for #{file.basename_prefix} (#{i+1}/#{using_version.files.size})"

        next if !using_version_metadata.has_propfile_metadata?(file)
        next if !generated_version.has_file?(file.basename_prefix)

        @file_formats << { "file_name"=>file.basename_prefix, "blocks"=>generate_blocks(file) }
      end

      @file_formats
    end

    # メタデータのblocks項を生成
    # @param [PropFile] using_file
    def generate_blocks(using_file)
      using_filename = using_file.basename_prefix
      generated_file = generated_version.find_file(using_filename)
      using_file_metadata = using_version_metadata.find_propfile_metadata(using_file)

      block_generator = BlockGenerator.new(using_file, generated_file, using_file_metadata)
      
      result_blocks = []

      block_generator.generate_raw_blocks.each do |raw_block|
        result_block = {}
        result_block["content"] = raw_block.content
        result_block["range"] = raw_block.range
        result_blocks << result_block
      end

      result_blocks
    end
  end

  # BlockGenerator で使用するStruct
  # @param [Symbol] type propertyのproperty_value_type
  # @param [Property] property
  Format = Struct.new(:type, :property)

  # 既存のメタデータを使用し、メタデータ未知のPropFileに関するblocksを作成するクラス
  class BlockGenerator
    attr_reader :using_file, :generated_file, :using_file_metadata, :using_version_metadata, :generated_version

    # @param [PropFile] using_file
    # @param [PropFile] generated_file
    # @param [PropFileMetaData] using_file_metadata using_fileのPropFileMetaData
    def initialize(using_file, generated_file, using_file_metadata)
      @using_file = using_file
      @generated_file = generated_file
      @generated_version = generated_file.version
      @using_file_metadata = using_file_metadata
      @using_version_metadata = using_file.version.version_metadata
    end

    # generated_fileのblocksに相当するArray<RawBlock>を作成
    # @return [Array<RawBlock>]
    def generate_raw_blocks
      return @raw_blocks if @raw_blocks
      @raw_blocks = []
      
      using_file_metadata.blocks.size.times do |block_no|
        range = matched_ranges[block_no]

        if range
          content = using_file_metadata.raw_blocks[block_no].content
          @raw_blocks << RawBlock.new(content, range.to_s)
        end
      end

      @raw_blocks
    end

    # using_fileのblocksのフォーマットを取得
    # @return [Array<Array<Object>>]
    # @note 返り値のn番目の要素はblocks内のn番目のblockのフォーマットに対応
    def block_format_types
      @block_format_types ||= using_file_metadata.blocks.map { block_format_type(_1.content) }
    end

    # using_fileに、binary,enumerated,catalog以外の型のプロパティを含むブロックが2つ以上存在するか判定
    # @return [Boolean] 存在する場合true
    def has_multiple_free_value_block?
      return @multiple_free_value_block_f if @multiple_free_value_block_f

      free_value_exist_f = []
      using_file_metadata.blocks.each do |block|
        block_properties = block.content.reject { _1.class == Array }
                                        .compact
        
        free_value_exist_f << !block_properties.all? { _1.property_value_type==:binary ||
                                                       _1.property_value_type==:enumerated ||
                                                      _1.property_value_type==:catalog }
      end
                     
      @multiple_free_value_block_f = free_value_exist_f.filter { _1 }.size > 1
      @multiple_free_value_block_f
    end

    # blockの再生成に使用するフォーマットとして最も適切なものを取得
    # @param [Array<Property?>/Array<Array<Property?>>]] Block.contentの値
    # @return [Array<Object>]
    def block_format_type(content)
      content.map { column_format_type(_1) }
    end

    def column_format_type(column)
      # columnがArrayの場合、その列には固有の表記法が使用されており、一様に判定を行う事はできないため、:text を返す
      return Format.new(:text, column) if column.class == Array
      
      # columnがnilの場合、nil (その列には判定を行わない)
      return nil if !column

      if has_multiple_free_value_block?
        # 列挙型以外のプロパティを取るブロックが2つ以上存在する場合、
        # コードポイントと値の対応を調べないと、同じプロパティに関する記述かの判定が不可能
        return column
      else
        # 列挙型以外のプロパティを取るブロックが1つだけの場合、
        # 記述されている値の型を調べるだけで、同じプロパティに関する記述かの判定が可能
        type =  (column.property_value_type==:miscellaneous) ? column.miscellaneous_format : column.property_value_type

        # type==:uniqueの場合、判定時には:textと同様に扱いたいため、:textに変更
        type = :text if type==:unique

        return Format.new(type, column)
      end
    end
    
    # generated_fileの各行が、何番目のブロックのblock_format_typeにマッチするか判定
    # @return [Array<Integer?>] m行目がblocks内のn番目のblockのフォーマットに一致する場合、m番目の要素はn。どのブロックにもマッチしない場合、nil。
    def lines_format
      return @lines_format if @lines_format
      @lines_format = []

      generated_file.lines.size.times do |row|
        # n行目がコメントの場合、line_formatによる判定は行わずnilを追加
        if generated_file.comment?(row)
          @lines_format << nil
          next
        end
        @lines_format << line_format(row)
      end

      @lines_format
    end

    # @param [Integer] row
    # @return [Array<Integer>] n番目のblockのフォーマットに一致する場合、n。どのブロックにもマッチしない場合、nil。
    def line_format(row)
      matched_blocks = []
      using_file_metadata.blocks.size.times do |block_no|
        codepoint_col_no = using_file_metadata.codepoint_column_nos[block_no]

        matched_blocks << block_no if match_format?(row, codepoint_col_no, block_no)
      end
      
      if matched_blocks.size == 1
        # line_formatの結果のサイズが1の場合
        # row行目がマッチするブロックが一意に絞れているため、結果として使用
        return matched_blocks[0]
      else
        # row行目がマッチするブロックが一意に絞れていない場合
        # この場合、ある行がどのプロパティについて記述されているか、データファイルに記述されている場合が多い
        # そのため、row行目の中に含まれるプロパティ名で判定
        
        prop_including_blocks = []
        using_file_metadata.blocks.size.times do |block_no|
          using_file_metadata.blocks[block_no].content.compact.each do |prop|
            next if prop.class == Array
            prop_including_blocks << block_no if generated_file.has_property_alias?(row, prop)
          end
        end

        if prop_including_blocks.size == 1
          return prop_including_blocks[0]
        else
          # プロパティ名を使用しても一意に絞れない場合、nil
          return nil
        end
      end
    end

    # row行目がformat_typeの形式に一致するか判定
    # @param [Integer] row
    # @param [Integer] codepoint_column_no
    # @param [Integer] block_no
    def match_format?(row, codepoint_column_no, block_no)
      shaped_line = generated_file.shaped_lines[row]
      format_type = block_format_types[block_no]

      # row行目の中にcol_formatと異なるフォーマットの列が存在する場合、その時点でfalseを返す
      format_type.each_with_index do |col_format, col_no|
        next if !col_format # formatがnilの場合には判定を行わない

        if col_format.class == Format
          if [:enumerated, :catalog, :binary].include?(col_format.type) && generated_version.has_property?(col_format.property)
            # 列挙型のプロパティ(enumerated, catalog, binary)の場合、 prop.version == generated_version でないと、propに新しいバージョンで追加された値が含まれず、プロパティの範囲の正確な推測が不可能
            prop = generated_version.find_property(col_format.property)
          else
            prop = col_format.property
          end
          
          if generated_file.type_match?(row, col_no, col_format.type, prop)
            next
          else
            return false
          end

        else
          # col_format.class==Property の場合、型での判定はできない
          # generated_fileのrow行目のcodepointがusing_fileで取っている値が、generated_fileと同じであるかを判定する
          bvg = using_version_metadata.find_propfile_metadata(using_file).block_value_group(block_no)
          shaped_line_dup = shaped_line.dup
          codepoint = shaped_line_dup.delete_at(codepoint_column_no)

          # codepointがnnnn..mmmm形式の場合、最初のnnnnのみを比較に使用
          # nnnn..mmmmの範囲では同じ値を持つため、nnnnのみを使用すれば十分
          codepoint = codepoint.split("..")[0]
          generated_file_value = generated_file.value_at(row, col_no)
          using_file_value = bvg.values_of(codepoint)
          
          if using_file_value.class==String && using_file_value==generated_file_value || 
            using_file_value.class==Array && using_file_value.include?(generated_file_value)
            next
          else
            return false
          end

        end
      end
      true
    end

    # 各ブロックがgenerated_fileにおいてマッチした行数の範囲を取得
    # @return [Array<Range<Integer>>]
    # @note n番目の要素はn番目のブロックがマッチした範囲
    def matched_ranges
      return @matched_ranges if @matched_ranges

      block_no_to_ranges = Hash.new { |hash,key| hash[key]=[] }

      measured_block_no = nil # 範囲を計測中のblock_no
      start_idx = nil # measured_block_noが最初に現れたidx
      end_idx = nil # measured_block_noが最後に現れたidx
      pre_idx = nil # 前回のblock_no(nil以外のInteger)が現れたidx

      lines_format_dup = lines_format.dup
      lines_format_dup << Float::NAN # 最後の要素まで処理を行うため、最後にNANを入れておく

      lines_format_dup.each_with_index do |block_no, i|
        next if !block_no # i行目がコメント行などの場合

        if block_no != measured_block_no
          # 前回までのmeasured_block_noの計測を終了
          end_idx = pre_idx
          if measured_block_no && start_idx && end_idx
            block_no_to_ranges[measured_block_no] << Range.new(start_idx, end_idx)
          end

          # measured_block_noをblock_noに切り替え
          measured_block_no = block_no
          start_idx = i
        end

        pre_idx = i
      end

      # 同一ブロックが2つ以上に分かれた範囲に記述されていると判定されている場合、
      # 最初の範囲だけをn番目のブロックの範囲として採用
      # その場合、誤ったメタデータが生成されることになるが、検証メソッドにより検出され、ユーザに修正される
      @matched_ranges = []
      using_file_metadata.blocks.size.times do |block_no|
        @matched_ranges[block_no] = block_no_to_ranges[block_no][0]
      end        

      @matched_ranges
    end
  end
end