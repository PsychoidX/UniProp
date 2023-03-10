module UniProp
  # codepointと値の関係の集合を扱うためのmodule
  module ValueGroup
    # @param [String/Integer] codepoint codepointを表す16進数のString、もしくはそれを10進数に変換したInteger 
    # @return [String/Array<String>]
    def values_of(codepoint)
      if codepoint.class == String
        if UniPropUtils::TypeJudgementer.validate_codepoint(codepoint)
          codepoint = codepoint.hex
        else
          return
        end
      end

      codepoint_to_values[codepoint]
    end

    # オブジェクトに保存されているcodepointの種類を取得
    # @return [Array<Integer>]
    def codepoints
      @codepoints ||= codepoint_to_values.keys
    end

    # @return [Hash<Object,Array<Integer>>]
    # @note 複数の値を持つが、その中に特定のプロパティ値を含むコードポイントを探す場合、values_including_codepointsを使用
    def values_to_codepoints
      @values_to_codepoints ||= codepoints.group_by { |cp| codepoint_to_values[cp] }
    end

    private
    # @return [Hash<Integer,String/Array<String>>]
    # @note 扱いやすさの観点から、keyであるcodepointはStringではなくIntegerに変換して格納する(値を使用する頻度は値を追加する頻度に比べて多いので、String->Integerの変換を値の追加時に行う)
    def codepoint_to_values
      @codepoint_to_values ||= {}
    end

    # codepoint_to_valuesに値を定義。すでに値が存在する場合、値の形式をArrayに変換して値を追加。
    # @param [Integer] codepoint codepointを10新数に変換したInteger
    # @param [String] value
    def add_single_value(codepoint, value)
      if codepoint_to_values[codepoint]
        # あるコードポイントに対応する値が1つの場合はStringで、2つ以上の場合はArray<String>で管理
        if codepoint_to_values[codepoint].class==String
          codepoint_to_values[codepoint] = [codepoint_to_values[codepoint]]
        end
        codepoint_to_values[codepoint] << value
      else
        codepoint_to_values[codepoint] = value
      end
    end

    # @param [String] codepoint nnnnまたはnnnn..nnnn形式のString
    # @param [String] value
    # @note このmoduleのオブジェクトの使用方法として、「インスタンス化処理と全ての値の追加処理を同時に行う」事を想定しているため、値の追加処理はprivateとしてある。
    def add_value(codepoint, value)
      codepoint = codepoint.gsub(/U\+/, '')
      value = value.gsub(/U\+/, '')

      if UniPropUtils::TypeJudgementer.validate_codepoint(codepoint)
        cp = UniPropUtils::CodepointConverter.str_to_int(codepoint)

        if cp.class==Range
          cp.each { add_single_value(_1, value) }
        else
          add_single_value(cp, value)
        end
      end
    end

    # 複数の値を一気に追加する
    # @param [String] codepoint nnnnまたはnnnn..nnnn形式のString
    # @param [Array<String>/String] values Arrayの場合はvaluesの要素それぞれに、Stringの場合はvaluesに対し、add_valueが呼ばれる
    def add_values(codepoint, values)
      if values.class==Array
        values.each { add_value(codepoint, _1) }
      elsif values.class==String
        add_value(codepoint, values)
      end
    end
  end

  class BasePropertyValueGroup
    include ValueGroup
    
    # valueをプロパティ値に持つコードポイントを取得
    # @note プロパティ値のエイリアスは考慮せず、単なる文字列の一致を確かめる
    # @param [String] value
    # @return [Array<Integer>]
    def string_value_including_codepoints(value)
      result = []
      values_to_codepoints.each do |values, codepoints|
        if values.include?(value)
          result.concat(codepoints)
        end
      end
      result
    end

    # valueをプロパティ値に持つコードポイントを取得
    # @note プロパティ値のエイリアスも加味して探索
    # @param [String] value
    # @return [Array<Integer>]
    def value_including_codepoints(value)
      # プロパティが列挙型の場合、プロパティ値の全エイリアスを確かめる
      pvs = []
      properties.each { pvs<<_1.find_property_value(value) if _1.has_property_value?(value) }
      
      if pvs.empty?
        string_value_including_codepoints(value)
      else
        # propertiesのプロパティに結びつくPropertyValueのうち
        # valueをエイリアスに持つPropertyValueの全エイリアスに対し
        # string_value_including_codepointsを実行して和集合を取る
        result = []
        pvs.each do |pv|
          result |= pv.uncanonicaled_aliases
                      .map { string_value_including_codepoints(_1) }
                      .reduce([], :|)
        end
        result
      end
    end
    
    # @return [Array<Property>]
    def properties
      @properties ||= []
    end

    # @param [Property] property
    def has_property?(property)
      properties.include?(property)
    end

    private
    # @param [Property] property
    def add_property(property)
      properties << property if property.class==Property
    end
  end

  class PropertyValueGroup < BasePropertyValueGroup
    # propfile内の特定のプロパティのcodeopintと値の対応を管理するためのオブジェクトを生成
    # @param [PropFile] propfile
    # @param [Array<Property>] props ブロックに含まれるプロパティ
    # @param [Integer] block_no 一番最初のブロックを0とした時の、ブロックの番号
    def initialize(propfile, props, block_no)
      @propfile = propfile
      @propfile_metadata = @propfile.version.version_metadata.find_propfile_metadata(@propfile)

      if props.class==Array
        props.each { add_property(_1) }
      elsif props.class==Property
        add_property(props)
      end
      
      block_range = @propfile_metadata.blocks[block_no].range
      raw_block_content = @propfile_metadata.raw_blocks[block_no].content
      codepoint_col_no = @propfile_metadata.codepoint_column_nos[block_no]

      value_col_nos = []
      properties.each { value_col_nos.concat(@propfile_metadata.property_column_nos(_1)[block_no]) }
      
      add_block_values(
        propfile.shaped_lines[block_range].to_a, 
        raw_block_content, 
        codepoint_col_no, 
        value_col_nos.uniq.sort
      )
    end

    private
    # add_block_valuesで使用するメソッド名を決定
    # @param [Array<Object>] raw_content メタデータのraw_content項の値
    # @param [Integer] codepoint_column_no codepointが記述されている列の番号
    # @param [Array<Integer>] value_column_nos プロパティ値が記述されている列の番号
    # @return [Symbol]
    # @note codepoint_column_no,value_column_nosはどちらも最初の列を0列目としてカウントする
    def value_add_method(raw_content, codepoint_column_no, value_column_nos)
      # ブロックの形による使用メソッドの選択
      case raw_content.values_at(*value_column_nos)
      when ([
        ["codepoint", "Composition_Exclusion"]
      ])
        return :adv_composition_exclusion
      end

      # プロパティの型による使用メソッドの選択
      if properties.size==1
        case properties[0].property_value_type
        when :binary
          return :adv_binary_property
        end
      end
      
      # 特殊なメソッドを使用しない場合、デフォルトの値追加メソッドを使用
      :default_add_block_values
    end

    # ブロックの構成によって追加方法を変えながら、ブロック内の全ての値を追加する
    # @param [Array<Array<String>>] shaped_lines PropFile#shaped_linesのうち、hashの生成に使用する行の範囲の値
    # @param [Array<Object>] raw_content
    # @param [Integer] codepoint_column_no
    # @param [Array<Integer>] value_column_nos
    def add_block_values(shaped_lines, raw_content, codepoint_column_no, value_column_nos)
      method_name = value_add_method(raw_content, codepoint_column_no, value_column_nos)
      send(method_name, shaped_lines, codepoint_column_no, value_column_nos)
    end

    def default_add_block_values(shaped_lines, codepoint_column_no, value_column_nos)
      shaped_lines.each do |shaped_line|
        codepoint = shaped_line[codepoint_column_no]
        values = shaped_line.values_at(*value_column_nos)

        # codepoint, valuesともにnilを含まない場合、値を追加
        if codepoint && values.all? { _1 }
          add_values(codepoint, values)
        end
      end
    end

    def adv_composition_exclusion(shaped_lines, codepoint_column_no, value_column_nos)
      # CompositionExclusions.txtでは、BinaryプロパティComposition_ExclusionがTrueであるコードポイントだけが列挙されている
      # そのため、ファイル内に記述のあるプロパティに対しては"True"の値をセットする(それ以外の値はmissingとして"False"が取得される)
      shaped_lines.each do |shaped_line|
        if shaped_line.size==1
          add_value(shaped_line[0], "True")
        end
      end
    end

    def adv_binary_property(shaped_lines, codepoint_column_no, value_column_nos)
      # binaryプロパティはデータファイルにプロパティ名が記述される
      # そのため、データファイル内の値(プロパティ名)ではなく、"True"を値として追加
      shaped_lines.each do |shaped_line|
        codepoint = shaped_line[codepoint_column_no]
        add_value(codepoint, "True") if codepoint
      end
    end
  end

  class UnihanValueGroup < BasePropertyValueGroup
    # @param [Property] property
    # @param [Array<Array<String>>] shaped_lines Unihanの中の、propertyに関するshaped_lines
    def initialize(property, shaped_lines)
      add_property(property)
      shaped_lines.each { add_values(_1[0], _1[2..]) }
    end
  end

  class BlockValueGroup
    include ValueGroup

    attr_reader :propfile

    # propfile内の特定のブロックのcodeopintと値の対応を管理するためのオブジェクトを生成
    # @param [PropFile] propfile
    # @param [Integer] block_no 一番最初のブロックを0とした時の、ブロックの番号
    def initialize(propfile, block_no)
      @propfile = propfile
      propfile_metadata = @propfile.version.version_metadata.find_propfile_metadata(@propfile)
      
      block_range = propfile_metadata.blocks[block_no].range
      codepoint_col_no = propfile_metadata.codepoint_column_nos[block_no]

      @propfile.shaped_lines[block_range].each do |shaped_line|
        shaped_line_dup = shaped_line.dup
        codepoint = shaped_line_dup.delete_at(codepoint_col_no)
        values = shaped_line_dup

        if codepoint && values
          add_values(codepoint, values)
        end
      end
    end
  end
end