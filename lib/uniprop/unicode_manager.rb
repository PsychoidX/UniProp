module UniProp
  class UnicodeManager
    attr_reader :prop_data

    def initialize(prop_data)
      @prop_data = prop_data
    end

    # @param [String] version バージョン名
    # @return [VersionManager]
    def version_manager(version)
      prop_data.version_manager(version)
    end

    # version_nameのメタデータを検証
    # @param [String] version_name
    def validate_metadata(version_name)
      prop_data.find_version(version_name).version_metadata.version_metadata_validator.run_all_validations
    end

    # initialize時に指定したメタデータを使用し、メタデータを作成
    # @param [Pathname] file_path メタデータを生成するパス
    # @param [String] using_version_name 生成に使用するバージョン名
    # @param [String] generated_version_name 生成するバージョン名
    def generate_metadata(file_path, using_version_name, generated_version_name)
      prop_data.generate_metadata(
        file_path,
        prop_data.find_efficient_version(using_version_name),
        prop_data.find_version(generated_version_name)
      )
    end

    # メタデータに含まれる全バージョンの全プロパティ名を取得
    # @return [Array<String>]
    def properties
      @properties ||= prop_data.version_managers
                                .map { _1.properties }
                                .reduce([], :|)
    end

    # codepointでpropertyのプロパティ値としてvalueが定義されているバージョン名をすべて取得
    # @param [String] property プロパティ名
    # @param [String] char 検索する1文字
    # @param [String] value プロパティ値
    def versions_of(property, char, value)
      warn "Versions prior to 4.0-Update are not included in the results because the metadata does not exist."
      prop_data.version_managers
            .filter { _1.has_value?(property, char.ord, value)}
            .map { _1.version.version_name }
    end

    # text_changed_codepointsの処理に加え、エイリアスの判定を実行し、値が変更されたコードポイントを取得
    # @param [String] property
    # @param [String] version1
    # @param [String] version2
    # @return [Array<Integer>]
    def value_changed_codepoints(property, version1, version2)
      pm1 = version_manager(version1).property_manager(property)
      pm2 = version_manager(version2).property_manager(property)
      vm2 = version_manager(version2)

      # 文字列は変更されているが、別エイリアスに表記が変更されただけのコードポイントを判別
      # 例: "Y"のエイリアスとして"Yes", "T", "True"、"N"のエイリアスとして"No", "F", "False"が存在する時、
      # ["Y", "N"] -> ["False", "True"]が表記の変更だけで、値は変わっていないことを検出する手順
      # ["Y", "N"]の各値のエイリアスを求め、["Yes", "T", "True", "N", "No", "F", "False"]の配列を生成
      # ["False", "True"]から["Yes", "T", "True", "N", "No", "F", "False"]を引き、結果がemptyであれば値の変更は無いと判別
      result = []
      text_changed_codepoints(property, version1, version2).each do |cp|
        values1 = pm1.values_of(cp)
        values2 = pm2.values_of(cp)

        values1 = values1.class==Array ? values1 : [values1]
        values2 = values2.class==Array ? values2 : [values2]

        values1_aliases = values1.map { vm2.value_aliases(property, _1) }
                                 .flatten
        
        result << cp if !(values2-values1_aliases).empty?
      end

      result
    end

    # version1で値が定義済みのコードポイントのうち、version2では他の値が定義されているものを取得
    # version2の方が新しい場合、version1から変更された値のみが取得される。version1の方が新しい場合、version2で追加された値も取得される。
    # @note 単にデータファイルの文字が異なるコードポイントを取得するだけで、エイリアスの判定は行わない(例: Ageプロパティのプロパティ値5.0はエイリアスとしてV5_0を持つが、5.0とV5_0は別の値とみなす)
    # @param [String] property
    # @param [String] version1
    # @param [String] version2
    # @return [Array<Integer>]
    def text_changed_codepoints(property, version1, version2)
      pvg1 = version_manager(version1).property_manager(property).property_value_group
      pvg2 = version_manager(version2).property_manager(property).property_value_group

      result = []
      # Blockプロパティのように、多くのコードポイントに同じ値が定義されるプロパティが存在
      # そのため、すべてのコードポイントの値を比較するのではなく、一度値ごとのコードポイントをまとめた方が効率的
      pvg1.values_to_codepoints.each do |values, cps1|
        cps2 = pvg2.values_to_codepoints[values].to_a
        diff_cps = cps1 - cps2
        result << diff_cps if !diff_cps.empty?
      end

      result.flatten
    end
  end

  class VersionManager
    attr_reader :version

    # versionに含まれる情報を取得するためのオブジェクトを作成
    # @param [EfficientVersion] version
    def initialize(version)
      @version = version
    end

    # PropertyManagerオブジェクトを作成
    # @param [String] property_name
    # @return [PropertyManager]
    def property_manager(property_name)
      @property_managers ||= []
      pm = @property_managers.find { _1.property.has_alias?(property_name) }
      return pm if pm

      pm = PropertyManager.new(version.find_property(property_name))
      @property_managers << pm
      pm
    end

    # propertyプロパティのcodepointのプロパティ値を取得
    # @param [String] property 検索するプロパティ名
    # @param [String] 1文字の文字列
    # @return [String/Array<String>] プロパティ値が1つの場合String、2つ以上の場合Array<String>
    def values_of(property, char)      
      property_manager(property).values_of(char.ord)
    end

    # propertyプロパティが値としてvalueを持つコードポイントを取得
    # @param [String] property プロパティ名
    # @param [String] value プロパティ値
    # @return [Array<Integer>]
    def codepoints_of(property, value)
      property_manager(property).property_value_group.value_including_codepoints(value)
    end

    # propertyがcodepointでプロパティ値としてvalueを持つか判定
    # @param [String] property プロパティ名
    # @param [Integer] codepoint
    # @param [String] value プロパティ値
    def has_value?(property, codepoint, value)
      codepoints_of(property, value).include?(codepoint)
    end

    # codepointでvalueを取るプロパティを取得
    # @param [String] char 1文字の文字列
    # @param [String] value プロパティ値
    # @return [Array<String>] プロパティ名
    def properties_of(char, value)
      properties.filter { has_value?(_1, char.ord, value) }
    end

    # バージョン内の全プロパティ名を取得
    # @return [Array<String>]
    def properties
      # VersionMetaData#property_namesにはUniHanのプロパティが含まれないため、EffcientVersion#propertiesから取得
      @properties ||= version.properties.map { _1.longest_alias }
    end

    # propertyをエイリアスに持つプロパティがバージョン内に存在するか確認
    # @param [String] property
    def has_property?(property)
      version.has_property?(property)
    end

    # propertyにデフォルト値以外の値が割り当てられているコードポイントを取得
    # @param [String] property
    # @return [Array<Integer>]
    def assigned_codepoints(property)
      property_manager(property).property_value_group.codepoints
    end

    # propertyのプロパティ値の中のvalueのエイリアスを全て取得
    # @note propertyが値としてvalueを持たない場合や、プロパティが列挙型でない場合、空の配列が帰る
    # @param [String] property プロパティ名
    # @param [String] value プロパティ値
    # @return [Array<String>]
    def value_aliases(property, value)
      return [] if !version.has_property?(property)
      prop = version.find_property(property)
      
      if prop.has_property_value?(value)
        prop.find_property_value(value).uncanonicaled_aliases
      else
        []
      end
    end
  end
  
  class PropertyManager
    attr_reader :property, :version_metadata, :property_value_group, :version

    # propertyに関する情報を取得するためのオブジェクトを作成
    # @note VersionまたはEfficientVersionはpropertyのProperty#versionが使用されるため、Version/EfficientVersionの使用したい方でPropertyオブジェクトを生成しpropertyとして使用する
    # @param [Property] property
    def initialize(property)
      @property = property
      @version = @property.version
      @version_metadata = @version.version_metadata
      @property_value_group = @version.prop_data.property_metadata.find_version_property_metadata(@version).find_property_data(@property).property_value_group
    end

    # @return [Set<String>]
    def values_of(codepoint)
      value = property_value_group.values_of(codepoint)
      
      if !value || value.empty?
        # 値が存在しない(nil)場合や、値が記述されていない(空文字列)の場合、missingを使用
        missing_value(codepoint)
      else
        value
      end
    end

    # codepointのmissingを取得
    # @param [Integer/String] codepoint
    # @return [String]
    def missing_value(codepoint)
      if codepoint.class==String
        codepoint = UniPropUtils::CodepointConverter.str_to_int(codepoint)
      end
      
      raw_missing_val = raw_missing_value(codepoint)

      case raw_missing_val
      when "<codepoint>" then codepoint.to_s(16).upcase
      when "<script>" then
        if @script || version.has_property?("Script")
          @script ||= PropertyManager.new(version.find_property("Script"))
          return @script.missing_value(codepoint)
        else
          return raw_missing_val
        end
      else raw_missing_val
      end
    end

    # codepointのmissingを取得。<codepoint>などの特殊な値もそのまま返される
    # @param [Integer/String] codepoint
    # @return [String]
    def raw_missing_value(codepoint)
      if codepoint.class==String
        codepoint = UniPropUtils::CodepointConverter.str_to_int(codepoint)
      end

      if version_metadata.property_missing_defs(property)
        version_metadata.property_missing_defs(property).reverse_each do |missing_def|
          if missing_def[:codepoint_range].include?(codepoint)
            return missing_def[:missing_value]
          end
        end
      end
      nil
    end

    # value1とvalue2が同じプロパティ値を表すエイリアスであるかを判定
    # @param [String] value1
    # @param [String] value2
    def same_value?(value1, value2)
      # Propertyがproperty_valuesを1つ以上持つとき、そのプロパティの値はPropertyValueAliasesに記述されており、エイリアスが存在する可能性がある
      if property.property_values.size >= 1 && property.has_property_value?(value1) && property.has_property_value?(value2)
         property.find_property_value(value1) == property.find_property_value(value2)
      else
        value1 == value2
      end
    end
  end
end