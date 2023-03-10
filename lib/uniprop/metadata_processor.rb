module UniProp
  class MetaData
    attr_reader :prop_data, :raw_metadata, :metadata_path

    # @param [PropData] prop_data
    # @param [Pathname] metadata_path
    def initialize(prop_data, metadata_path)
      @prop_data = prop_data
      @metadata_path = metadata_path

      if @metadata_path.exist?
        @raw_metadata = JSON.parse(File.read(@metadata_path))
      else
        raise FileNotFoundError, "#{@metadata_path} is not found."
      end
    end

    # メタデータのversion_names項目の値を取得。メタデータにこの項目が記述されていない場合、Unicode.orgからバージョン一覧を取得
    # @param [Boolean] update_metadata trueの場合、取得した情報がメタデータと異なる際に、メタデータを更新
    # @param [Boolean] confirm trueの場合、Unicode.orgからバージョン名一覧を取得する。メタデータにバージョン一覧が記述されている場合にも、Unicord.orgから取得した情報を優先して返す。メタデータにversion_names項目が無い場合、confirm==falseでもUnicode.orgから情報を取得する
    # @return [Array<String>]
    def version_names(update_metadata: false, confirm: false)
      if confirm || raw_metadata["version_names"].nil? || raw_metadata["version_names"].empty?
        actual_version_names = UniPropUtils::DownloaderWrapper.get_version_names

        if update_metadata
          raw_metadata["version_names"] = actual_version_names
          prop_data.update_metadata(raw_metadata)
        end
        
        return actual_version_names
      else
        return raw_metadata["version_names"]
      end
    end

    # @return [Array<Hash<String,Object>>]
    def raw_version_metadatas
      @raw_version_metadatas ||= raw_metadata["version_metadatas"].sort { Version.name_to_weight(_1["version_name"]) }
    end

    # メタデータから、version_nameと同じweightのバージョンに関する記述を取得
    # @param [String] version_name
    # @return [Hash<String,Object>]
    def find_raw_version_metadata(version_name)
      weight = Version.name_to_weight(version_name)

      result = raw_version_metadatas.find { Version.name_to_weight(_1["version_name"])==weight }

      if result
        return result
      else
        raise MetaDataNotFoundError, "metadata for #{version_name} is not found."
      end
    end

    def has_raw_version_metadata?(version_name)
      !!find_raw_version_metadata(version_name)
    rescue
      false
    end

    # @return [MetaDataValidator]
    def metadata_validator
      @metadata_validator ||= MetaDataValidator.new(self)
      @metadata_validator
    end
  end

  class VersionMetaData
    attr_reader :version, :raw_metadata

    def initialize(version, raw_metadata)
      @version = version
      @raw_metadata = raw_metadata
    end

    # メタデータを元に、各Propertyと、そのPositionを取得
    # @return [Hash<Property,Array<Position>>]
    def property_to_actual_positions
      return @property_to_actual_positions if @property_to_actual_positions

      @property_to_actual_positions = {}

      actual_propfiles.each do |propfile|
        if has_propfile_metadata?(propfile)
          propfile_metadata = find_propfile_metadata(propfile)
        else
          next
        end

        propfile_metadata.blocks.each_with_index do |block, block_no|
          block.content.each_with_index do |col, col_no|
            props = [] # この回のループのblock_no, col_noの箇所に存在するプロパティ
            
            if col.class==Array
              props.concat(col)
            else
              props << col
            end
            
            props.compact.uniq.each do |prop|
              @property_to_actual_positions[prop] ||= []
              add_f = false # col_noをPositionオブジェクトに追加した時点でtrueに変更

              # propfile, block_noが同じPositionが存在している場合、列を追加する (新しいPositionオブジェクトは生成しない)
              @property_to_actual_positions[prop].each do |position|
                if position.propfile==propfile && position.block==block_no
                  position.columns << col_no
                  add_f = true
                  break
                end
              end
              if !add_f
                @property_to_actual_positions[prop] << Position.new(propfile, block.range, block_no, [col_no])
              end

            end
          end
        end
      end

      @property_to_actual_positions
    end

    # メタデータを元に、各PropFileと、それに含まれるPropertyを取得
    # @return [Hash<PropFile,Array<Property>>]
    def propfile_to_actual_properties
      return @propfile_to_actual_properties if @propfile_to_actual_properties

      @propfile_to_actual_properties = Hash.new { |hash,key| hash[key]=[] }

      actual_propfiles.each do |propfile|
        if has_propfile_metadata?(propfile)
          propfile_metadata = find_propfile_metadata(propfile)
        else
          next
        end

        propfile_metadata.blocks.each do |block|
          block.content.flatten.each do |col_prop| # 一部ファイルではblockの中に配列が含まれるためflattenにする
            @propfile_to_actual_properties[propfile] << col_prop if version.has_property?(col_prop)
          end
        end
      end

      @propfile_to_actual_properties
    end
    
    # メタデータに含まれるプロパティ名を取得
    # @return [Array<String>]
    def property_names
      return @property_names if @property_names

      @property_names = []
      propfile_metadatas.each do |propfile_metadata|
        propfile_metadata.raw_blocks.each { @property_names.concat(_1.content.flatten) }
      end

      @property_names.uniq!
      @property_names
    end

    # メタデータ内に含まれるプロパティを取得
    # @return [Array<Property>]
    def actual_properties
      return @actual_properties if @actual_properties

      @actual_properties = propfile_to_actual_properties.values.flatten
      @actual_properties.concat(unihan_properties)

      @actual_properties
    end

    # @return [VersionMetaDataValidator]
    def version_metadata_validator
      @version_metadata_validator ||= VersionMetaDataValidator.new(self)
      @version_metadata_validator
    end

    # メタデータに記述されているfile_formats内の記述を、加工せずそのまま取得
    # @return [Hash<String,Object>] 値の形式はキーによって異なる。
    def find_raw_file_format(propfile)
      raw_metadata["file_formats"].each do |file_format|
        if version.has_file?(file_format["file_name"])
          f = version.find_file(file_format["file_name"])
          return file_format if f==propfile
        end
      end
      raise(MetaDataNotFoundError, "Metadata for #{propfile.basename_prefix} is not found.")
    end

    # 結び付いているPropFileのフォーマットに関する情報がメタデータにあるかを判定
    # @param [PropFile] propfile
    def has_file_format?(propfile)
      return !!find_raw_file_format(propfile)
    rescue
      return false
    end

    # バージョンに属する各Propertyと、そのPropertyが実際に記述されているPropFileの関係のHashを取得
    # @return [Hash<Property,Set<PropFile>]
    def property_to_actual_propfiles
      return @property_to_actual_propfiles if @property_to_actual_propfiles

      @property_to_actual_propfiles = Hash.new { |hash,key| hash[key]=Set.new }

      propfile_to_actual_properties.each do |propfile, actual_props|
        actual_props.each { @property_to_actual_propfiles[_1] << propfile }
      end

      @property_to_actual_propfiles
    end

    # fileのMissingDefオブジェクトを取得
    # @param [PropFile] propfile
    # @return [Array<MissingDef>]
    # @note codepointによって複数のmissingが定義されている場合には返り値は複数のMissingDefオブジェクトになる
    def propfile_missing_defs(propfile)
      @propfile_to_missing_defs ||= {}
      return @propfile_to_missing_defs[propfile] if @propfile_to_missing_defs[propfile]

      missing_defs = []
      
      propfile.shaped_missing_value_lines.each do |shaped_missing_value_line|
        m = shaped_missing_value_line[0].match(/([0-9A-F]{4,6})\.\.([0-9A-F]{4,6})|([0-9A-F]{4,6})/)

        if m
          # cp..cpでマッチ
          if m && m[2]
            begin_cp = m[1].hex
            end_cp = m[2].hex
          # cpでマッチ
          elsif m && m[1]
            begin_cp = m[1].hex
            end_cp = m[1].hex
          end
          codepoint_range = Range.new(begin_cp, end_cp)

          # missingについて記述される行は、以下のどちらかの形式を取る
          # (1) @missing: codepoint; property; missing
          # (2) @missing: codepoint; missing
  
          # (1) の場合
          if shaped_missing_value_line.size==3
            property_name = shaped_missing_value_line[1]
            missing_value = shaped_missing_value_line[2]
  
            if version.has_property?(property_name)
              prop = version.find_property(property_name)
              missing_defs << MissingDef.new(codepoint_range, prop, missing_value)
            end
  
          # (2) の場合
          # missingが記述されているファイルからPropertyを特定し使用
          elsif shaped_missing_value_line.size==2
            # ファイルに含まれるプロパティが1種類でない場合、プロパティを特定できない
            next if propfile_to_actual_properties[propfile].size!=1

            missing_value = shaped_missing_value_line[1]
            prop = propfile_to_actual_properties[propfile].to_a[0]
            missing_defs << MissingDef.new(codepoint_range, prop, missing_value)
          end
        end
      end
  
      @propfile_to_missing_defs[propfile] = missing_defs
      @propfile_to_missing_defs[propfile]
    end

    # propertyのMissingDefオブジェクトを取得
    # @param [Property] property
    # @return [Array<MissingDef>]
    # @note codepointによって複数のmissingが定義されている場合には返り値は複数のMissingDefオブジェクトになる
    def property_missing_defs(property)
      @property_to_missing_defs ||= {}
      return @property_to_missing_defs[property] if @property_to_missing_defs[property]

      # binaryプロパティのデフォルト値はFalse
      if property.property_value_type==:binary
        @property_to_missing_defs[property]=[MissingDef.new(CODEPOINT_RANGE,property,"False")]
        return @property_to_missing_defs[property]
      end

      # 最小限のファイルで動くよう、PropertyValueAliases.txtとプロパティが記述されているファイルのみからmissingの記述を探す
      # プロパティ記述ファイルとPropertyValueAliasesのうち、定義されているmissingの種類が最も多い値を返す
      search_files = property_to_actual_propfiles[property]
      search_files << version.property_value_aliases_file

      # 15.0.0のEastAsianWidth.txtとDerivedEastAsianWidth.txtのように、@missingから始まる定義の内容が異なる場合がある
      # ファイル内で定義される@missingの個数が最も多いファイルの定義を使用する
      search_files.each do |file|
        missing_defs = propfile_missing_defs(file).filter { _1.property==property }

        if !@property_to_missing_defs[property] || missing_defs.size > @property_to_missing_defs[property].size
          @property_to_missing_defs[property] = missing_defs
        end
      end

      @property_to_missing_defs[property]
    end

    # メタデータに記述のあるPropFileを取得
    # @return [Array<PropFile>]
    def actual_propfiles
      return @actual_propfiles if @actual_propfiles

      @actual_propfiles = []
      propfile_names.each { @actual_propfiles<<version.find_file(_1) if version.has_file?(_1) }

      @actual_propfiles
    end

    # メタデータに記述されているPropFileの名前を取得
    # @return [Set<String>]
    def propfile_names
      return @propfile_names if @propfile_names
      
      @propfile_names = raw_metadata["file_formats"].map { _1["file_name"] }.to_a
      @propfile_names += unihan_file_names
      @propfile_names
    end

    # @return [Array<PropFileMetaData>]
    def propfile_metadatas
      return @propfile_metadatas if @propfile_metadatas

      @propfile_metadatas = []
      actual_propfiles.each { @propfile_metadatas<<PropFileMetaData.new(_1, find_raw_file_format(_1)) if has_file_format?(_1) }

      @propfile_metadatas
    end

    # versionに含まれるUnihanのファイル名を取得
    # @return [Array<String>]
    def unihan_file_names
      @unihan_file_names ||= raw_metadata["unihan_files"].to_a
    end

    # versionに含まれるUnihanのプロパティ名を取得
    # @return [Array<Property>]
    def unihan_property_names
      @unihan_property_names ||= raw_metadata["unihan_properties"].to_a
    end

    # @return [Array<Property>]
    def unihan_properties
      return @unihan_properties if @unihan_properties

      @unihan_properties = []
      unihan_property_names.each do |prop_name|
        if version.has_property?(prop_name)
          prop = version.find_property(prop_name)
        else
          prop = UniProp::Property.new(version, prop_name)
        end
        @unihan_properties << prop
      end

      @unihan_properties
    end

    # @return [VersionMetaData]
    def find_propfile_metadata(propfile)
      propfile_metadata = propfile_metadatas.find { _1.propfile==propfile }

      if propfile_metadata
        return propfile_metadata
      else
        raise MetaDataNotFoundError, "metadata for #{propfile} is not found."
      end
    end

    def has_propfile_metadata?(propfile)
      !!find_propfile_metadata(propfile)
    rescue
      false
    end
  end

  class PropFileMetaData
    attr_reader :propfile, :raw_file_format

    def initialize(propfile, raw_file_format)
      @propfile = propfile
      @raw_file_format = raw_file_format
    end

    # raw_file_formatからRawBlockオブジェクトを作成
    # @return [Array<RawBlock>]
    def raw_blocks
      return @raw_blocks if @raw_blocks
      @raw_blocks = []
      raw_file_format["blocks"].each { @raw_blocks << RawBlock.new(_1["content"], _1["range"])}
      @raw_blocks
    end

    # @return [Array<Block>]
    def blocks
      return @blocks if @blocks
      @blocks = []
      
      raw_blocks.each do |raw_block|
        content = version.convert_property(raw_block.content)
        range = UniPropUtils::RangeProcessor.str_to_range(raw_block.range)
        @blocks << Block.new(content, range)
      end

      @blocks
    end

    # ファイル内に含まれるプロパティを取得
    # @return [Array<Property>]
    def actual_properties
      return @actual_properties if @actual_properties
      @actual_properties = []

      blocks.each { @actual_properties.concat(_1.content.flatten.compact) }

      @actual_properties.uniq!
      @actual_properties
    end

    # プロパティが記述されている範囲を取得
    # @return [Array<Range<Integer>>]
    def property_written_ranges
      @property_written_ranges ||= blocks.map { _1.range }
    end

    # :nocov:
    # ファイル内にプロパティが1つ以上含まれるかを判定
    def has_any_properties?
      !actual_properties.empty?
    end
    # :nocov:

    # 各ブロックの、codepointが記述されている列番号を取得
    # @return [Array<Integer?>] selfのブロック数と同じサイズのArray。n番目の要素にはn番目のブロックにおいてcodepointが記述されている列数を表すIntegerが入る。n番目のブロックにcodepointが記述されていない場合、n番目の要素はnil
    def codepoint_column_nos
      return @codepoint_column_nos if @codepoint_column_nos
      @codepoint_column_nos = Array.new(raw_blocks.size)
      
      raw_blocks.each_with_index do |raw_block, block_no|
        raw_block.content.each_with_index do |col, col_no|
          if (
            col.class==Array && col.map{Alias.canonical(_1)}.include?("codepoint") ||
            col.class==String && Alias.canonical(col)=="codepoint"
            )
            @codepoint_column_nos[block_no] = col_no
          end
        end
      end

      @codepoint_column_nos
    end

    # 各ブロックの、propが記述されている列番号を取得
    # @param [Property] prop
    # @return [Array<Array<Integer>>] selfのブロック数と同じサイズのArray。n番目の要素にはn番目のブロックにおいてpropが記述されている列数を表すIntegerが入る。
    def property_column_nos(prop)
      property_column_nos = Array.new(blocks.size) { [] }

      blocks.each_with_index do |block, block_no|
        block.content.each_with_index do |col, col_no|
          if (
            col.class==Array && col.include?(prop) ||
            col.class==Property && col==prop
            )
            property_column_nos[block_no] << col_no
          end
        end
      end

      property_column_nos
    end

    # propfile内に複数のプロパティを含む列が存在するかを判定
    def has_multiple_properties_column?
      blocks.each do |block|
        return true if block.content.any? { _1.class==Array }
      end
      return false
    end

    # block_no番目のブロックに関するBlockValueGroupオブジェクトを取得
    # @param [Integer] block_no
    def block_value_group(block_no)
      return nil if block_no<0 || blocks.size<=block_no
      @block_value_groups ||= {}
      @block_value_groups[block_no] ||= BlockValueGroup.new(propfile, block_no)
      @block_value_groups[block_no]
    end

    # :nocov:
    # @return [VersionMetaData]
    def version_metadata
      propfile.version.version_metadata
    end
    # :nocov:

    # :nocov:
    # @return [Version]
    def version
      propfile.version
    end
    # :nocov:
  end

  class PropertyMetaData
    attr_reader :prop_data, :raw_metadata, :metadata_path

    # @param [PropData] prop_data
    # @param [Pathname] metadata_path
    def initialize(prop_data, metadata_path)
      @prop_data = prop_data
      @metadata_path = metadata_path

      if @metadata_path.exist?
        @raw_metadata = JSON.parse(File.read(@metadata_path))
      else
        raise FileNotFoundError, "#{@metadata_path} is not found."
      end
    end

    # @return [Array<Hash<String,Object>>]
    def raw_version_metadatas
      @raw_version_metadatas ||= raw_metadata.sort { Version.name_to_weight(_1["version_name"]) }
    end

    # メタデータから、version_nameと同じweightのバージョンに関する記述を取得
    # @param [String] version_name
    # @return [Hash<String,Object>]
    def find_raw_version_metadata(version_name)
      weight = Version.name_to_weight(version_name)
      result = raw_version_metadatas.find { Version.name_to_weight(_1["version_name"])==weight }

      if result
        return result
      else
        raise MetaDataNotFoundError, "metadata for #{version_name} is not found."
      end
    end

    def has_raw_version_metadata?(version_name)
      !!find_raw_version_metadata(version_name)
    rescue
      false
    end

    # @param [EfficientVersion] version
    # @return [Hash<String,Object>]
    def find_version_property_metadata(version)
      @version_property_metadatas ||= []

      vpm = @version_property_metadatas.find { _1.version==version }
      return vpm if vpm

      # プロパティ中心のメタデータが存在しない場合、生成を試みる
      if !has_raw_version_metadata?(version.version_name)
        prop_data.generate_property_metadata(metadata_path, version)
      end

      vpm = VersionPropertyMetaData.new(version, find_raw_version_metadata(version.version_name))
      @version_property_metadatas << vpm
      vpm
    end
  end

  class VersionPropertyMetaData
    attr_reader :version, :raw_metadata

    # @param [EfficientVersion] version
    # @param [Array<Hash<String,Object>>] プロパティ中心のメタデータのproperties項
    def initialize(version, raw_metadata)
      @version = version
      @raw_metadata = raw_metadata
    end

    # プロパティ中心のメタデータのproperties項をUniPropのデータ構造に変換して取得
    # @return [Array<Hash<String,Object>>]
    def property_datas
      return @property_datas if @property_datas

      @property_datas = []
      raw_metadata["properties"].each do |raw_prop_data|

        positions = []
        raw_prop_data["positions"].each do |raw_position|
          positions << Position.new(
            version.find_file(raw_position["file_name"]),
            UniPropUtils::RangeProcessor.str_to_range(raw_position["range"]),
            raw_position["block"],
            raw_position["columns"],
          )
        end
          
        @property_datas << PropertyData.new(
          version.find_property(raw_prop_data["property_name"]),
          positions,
          raw_prop_data["unihan"],
          raw_prop_data["derived"],
        )
      end
      
      @property_datas
    end

    # @param [Property] property
    # @return [PropertyData]
    def find_property_data(property)      
      prop = property_datas.find { _1.property==property }
      if prop
        return prop
      else
        raise MetaDataNotFoundError, "MetaData for #{property.longest_alias} is not found."
      end
    end
  end

  class PropertyData
    attr_reader :property, :positions, :version

    # プロパティメタデータに含まれる、プロパティ1つあたりのデータ
    # @param [Property] property
    # @param [Array<Position>] positions
    # @param [Boolean] unihan
    # @param [Boolean] derived
    def initialize(property, positions, unihan, derived)
      @property = property
      @version = @property.version
      @positions = positions
      @unihan = unihan
      @derived = derived
    end

    def is_unihan?
      @unihan
    end

    def is_derived?
      @derived
    end

    def type
      property.property_value_type
    end

    # プロパティの解析に最も適したPositionオブジェクトをを取得
    # @return [Position]
    def position
      if is_derived?
        # Derivedファイルが存在する場合、使用
        return positions.find { _1.propfile.basename_prefix=~/Derived/ }
      else
        # Derivedファイルが存在しない場合、
        # 記述される列が最も小さいファイルが解析しやすいため使用
        return positions.sort { _1.columns.size }.first
      end
    end

    # propertyの情報を取得するのに最適なPropertyValueGroupオブジェクトを生成
    # @return [PropertyValueGroup/UnihanValueGroup]
    def property_value_group
      return @property_value_group if @property_value_group

      if is_unihan?
        @property_value_group = version.unihanprop.unihan_value_group(property)
      else
        @property_value_group = PropertyValueGroup.new(position.propfile, property, position.block)
      end
    end
  end
end