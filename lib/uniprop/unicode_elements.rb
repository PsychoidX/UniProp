module UniProp
  module Alias
    attr_reader :longest_alias

    # 文字列を正規化
    # @param [String] str 正規化前の文字列
    # @return [String] strを正規化したもの
    def self.canonical(str)
      str.gsub(/[-_ ]/, '').downcase
    end

    # @note aliasはインスタンス化時にも追加可能だが、add_aliasを使用する事でも追加可能
    # @param [*String] new_aliases 追加するalias(個数任意)
    def initialize(*new_aliases)
      new_aliases.each { add_alias _1 }
    end

    # aliasを追加
    # @param [String] new_alias 追加するalias
    # @note aliasはcanonicalを使用して正規化されて追加される
    def add_alias(new_alias)
      if new_alias.class == String
        if new_alias.size > @longest_alias.to_s.size
          @longest_alias = new_alias
        end
        aliases << Alias.canonical(new_alias)
        uncanonicaled_aliases << new_alias
      end
    end

    # :nocov:
    # @return [Array<String>] 追加済みの正規化済みのalias
    def aliases
      @aliases ||= []
    end

    # @return [Array<String>] 追加済みのalias
    def uncanonicaled_aliases
      @uncanonicaled_aliases ||= []
    end
    # :nocov:

    def has_alias?(alias_str)
      return aliases.include?(Alias.canonical(alias_str))
    end

    # @return [Boolean] self.aliasesとother.aliasesが完全に同じ場合にtrue
    def ==(other)
      aliases==other.aliases
    end

    # @private
    def eql?(other); self==other end
    
    # @private
    def hash
      aliases.sort.join.hash
    end
  end

  class Property
    attr_reader :property_value_type, :version

    include Alias

    def initialize(version, *new_aliases)
      @version = version
      super(*new_aliases)
    end

    def property_value_type=(type)
      type = type.downcase
      if (
        type == "catalog" ||
        type == "enumerated" ||
        type == "binary" ||
        type == "string" ||
        type == "numeric" ||
        type == "miscellaneous"
      )
        @property_value_type = type.to_sym
      else
        raise PropertyValueTypeNotExistsError.new(type)
      end
    end

    # settings.rbのmiscellaneous_formats内のformat_typeを小文字のシンボルで取得。記述されていない場合はnil
    # @return [Symbol?]
    def miscellaneous_format
      version.property_to_miscellaneous_formats.dig(self, :format_type)&.downcase&.to_sym
    end

    # settings.rbのmiscellaneous_formats内のunique_thresholdを取得。記述されていない場合はnil
    # @return [Integer?/Float?]
    def unique_threshold
      version.property_to_miscellaneous_formats.dig(self, :unique_threshold)
    end

    def ==(other)
      # プロパティのエイリアスはバージョン更新時に増えることがあるため、versionの異なるPropertyを比較する場合には、プロパティが増えていてもtrueを返す
      if version > other.version
        return (other.aliases-aliases).empty?
      elsif version < other.version
        return (aliases-other.aliases).empty?
      else
        aliases==other.aliases
      end
    end

    # @return [Array<PropertyValue>]
    def property_values
      version.property_to_property_values[self]
    end

    # :nocov:
    # property_value_aliasをエイリアスに持つPropertyValueをproperty_valuesに持つか判定
    # @param [String] property_value_alias
    def has_property_value?(property_value_alias)
      !!find_property_value(property_value_alias)
    rescue
      false
    end
    # :nocov:

    # property_value_aliasをエイリアスに持つPropertyValueをproperty_valuesの中から取得
    # @param [String] property_value_alias
    # @return [PropertyValue]
    # @raise [PropertyValueNotFoundError] 該当するPropertyValueが存在しない場合に発生
    def find_property_value(property_value_alias)
      pv = property_values.find { _1.has_alias?(property_value_alias)}
      
      if pv
        return pv
      else
        raise(PropertyValueNotFoundError, "#{longest_alias} doesn't have #{property_value_alias} as value.")
      end
    end

    # :nocov:
    # versionに含まれるPropFileの中の、このプロパティが含まれる場所を取得
    # @return [Array<Position>]
    def actual_positions
      @actual_positions ||= version.version_metadata.property_to_actual_positions[self]
    end
    # :nocov:

    # propfile中でプロパティが含まれる列を取得
    # @note プロパティがpropfileに含まれない場合、空の配列を返す
    # @param [PropFile] propfile
    # @return [Array<Integer>]
    def actual_columns(propfile)
      columns = []
      actual_positions.each { columns<<_1.column if _1.propfile==propfile }
      columns
    end

    # Unihanのプロパティか判定
    def is_unihan_property?
      version.unihan_properties.include?(self)
    end
  end

  class PropertyValue
    include Alias
    
    attr_accessor :property
    def initialize(property, *new_aliases)
      @property = property
      new_aliases.each { add_alias _1 }
    end
  end
  
  class PropFile
    attr_accessor :version, :strip_regexp, :split_regexp, :basename_prefix

    # @param [Pathname/String] path キャッシュのPathnameまたはbasename_prefixに相当するString
    # @note fileをPathnameで指定する場合、絶対パスでの指定が必要
    # @param [Regexp] strip_regexp 対応するファイル内で使われる空白文字の正規表現
    # @param [Regexp] split_regexp 対応するファイル内で使われる区切り文字の正規表現
    def initialize(path, version, strip_regexp: /\s+/, split_regexp: /;/)
      if path.class==Pathname
        @cache_path = path
        @basename_prefix = UniPropUtils::FileManager.prefix(@cache_path)
      else
        @basename_prefix = path
      end

      # # strip_regexp, split_regexpが引数で指定されていない場合、settings.rbの記述を使用
      # file_format = version.prop_data.find_settings_value(version.prop_data.unihan_files_information, "file_format", version.version_name)

      # strip_regexp ||= file_format[:strip]
      # split_regexp ||= file_format[:split]

      @version = version
      @strip_regexp = strip_regexp
      @split_regexp = split_regexp
    end

    # @return [Pathname]
    # @raise [FileNotFoundError] キャッシュが存在せず、ダウンロードにも失敗した場合に発生
    def cache_path
      return @cache_path if @cache_path

      # キャッシュの中にbasename_prefixと同名のファイルがある場合、それを使用
      if version.has_cache_file?(basename_prefix)
        @cache_path = version.find_cache_file_path(basename_prefix)
        return @cache_path
      end

      # キャッシュが保存されていない場合、ダウンロードを試みる
      download_myself
      if version.has_cache_file?(basename_prefix)
        @cache_path = version.find_cache_file_path(basename_prefix)
        return @cache_path
      else
        raise FileNotFoundError, "#{basename_prefix} does not exist in cache and download failed."
      end
    end

    # :nocov:
    # versionの、basename_prefixに該当するファイル名のファイルをUnicode.orgからダウンロード
    def download_myself
      version.download_file(basename_prefix)
    end
    # :nocov:

    def is_meta_file?() false end
    
    def is_unihan_file?() false end

    # ファイルコンテンツを改行で区切った配列を取得
    # @return [Array]
    def lines()  @lines ||= cache_path.readlines.map(&:chomp)  end

    # ファイルコンテンツからコメントを削除したものを改行で区切った配列を取得
    # @return [Array]
    # @note コメントのみからなる行は空文字列に変換されるだけであり、要素は削除されない (行数がインデックスと対応)
    def lines_without_comment
      @lines_without_comment ||= lines.map { |l| l.gsub(/#.*/,'') }
    end

    # lines_without_commentのうち、空文字列となった要素を削除した配列を取得
    # @return [Array]
    def netto_lines
      @netto_lines ||= lines_without_comment.reject { |l| l.match(/^\s*$/) }
    end

    # @param [PropFile/Pathname] other
    def ==(other)
      if other.class == self.class
        # cache_pathで判定したほうが簡潔に書けるが、キャッシュにファイルが存在しない場合にも判定を行うため、このような実装にしてある
        return version==other.version && basename_prefix==other.basename_prefix
      elsif other.class == Pathname
        return @cache_path==other
      else
        return false
      end
    end

    # lines_without_commentをstrip_regexpとsplit_regexpで処理した配列を取得
    # @return [Array]
    # @note strip_regexp==/\s+/ の場合であっても、各列の最初と最後の空白しか除去されない。「0000; 1111 2222; 3333;」の、1111と2222の間の空白は除去されない。
    # def values
    def shaped_lines
      return @shaped_lines if @shaped_lines

      @shaped_lines = []

      # String#splitはlimit==0(デフォルト)の場合、配列末尾の空文字列が削除される
      # それを防ぐため、limit==-1としてある。これはlimit<0にする事が目的であり、-1という値に意味は無い
      if strip_regexp == /\s+/
        lines_without_comment.each do |line|
          @shaped_lines << line.split(sep=split_regexp, limit=-1)
                        .map { _1.gsub(/^\s+/, '') }
                        .map { _1.gsub(/\s+$/, '') }
        end
      else
        lines_without_comment.each do |line|
          @shaped_lines << line.split(sep=split_regexp, limit=-1)
                        .map { _1.gsub(strip_regexp, '') }
        end
      end
      @shaped_lines
    end

    # @return [Array] valuesから空の配列を削除したArray
    def netto_shaped_lines
      @netto_shaped_lines ||= shaped_lines.reject { _1.empty? }
    end

    # 各列に含まれる値(codepointを含む)の配列の配列を取得。
    # @note 返り値の配列のインデックスnは、n列目(最初の列を0列目とする)に含まれるすべての値を含む配列。
    # @return [Array<Set<String>>]
    def contents
      return @contents if @contents

      @contents = []

      shaped_lines.each do |shaped_line|
        shaped_line.each_with_index do |col_value, i|
          @contents[i] ||= Set.new
          @contents[i] << Alias.canonical(col_value)
        end
      end

      # valuesでは区切り文字で区切られたそれぞれの部分を列とみなす。(1行に区切り文字がn個あれば、n+1列あるとみなされる)
      # しかし実際には、最後の区切り文字の右側にコメントしか記述されない事が多いので、その場合は最終列を削除。
      # contentsでは、最後の列に実際に値が無い場合(空orコメントのみの場合)には列とみなさない。
      if @contents[-1].empty? || @contents[-1] == Set.new([""])
        @contents = @contents[...-1]
      end
      
      @contents
    end

    # ファイル内に含まれるすべての値(codepointを含む)を取得。
    # @return [Set<String>]
    def values
      @values ||= contents.reduce(Set.new, :merge)
    end

    # :nocov:
    # 引数の列がユニーク列(行数に対し、記述されている値の割合が閾値以上の列。Nameプロパティなど、それぞれのcodepointが異なる値を取る傾向にあるプロパティが該当)であるかを判定
    # @param [Integer] column
    # @param [Float] unique_threshold
    # @return [Boolean] ユニーク列であればtrue
    def unique_column?(column, unique_threshold)
      (contents[column].size.to_f / netto_lines.size) > unique_threshold
    end
    # :nocov:

    # 引数の行・列の値を取得
    # @return [String]
    def value_at(row, column)
      shaped_lines.dig(row, column)
    end

    # rowの中の1つ以上の列に、propのエイリアスが含まれるかを判定
    # @param [Integer] row 検索する行の番号
    # @param [Property] prop
    def has_property_alias?(row, prop)
      !!shaped_lines[row]&.any? { prop.has_alias?(_1) }
    end

    # propのエイリアスが含まれる行の範囲を取得
    # @param [Property] prop
    # @return [Array<Range>]
    def property_alias_including_ranges(prop)
      property_alias_including_rows = []

      lines.size.times do |row|
        property_alias_including_rows << row if has_property_alias?(row, prop)
      end

      UniPropUtils::RangeProcessor.array_to_ranges(property_alias_including_rows)
    end

    # rowがコメントのみから成る行かを判定
    # @note 空行もコメント行とみなす
    # @param [Integer] row
    def comment?(row)
      if 0 <= row && row <= lines.size-1
        lines_without_comment[row].match?(/^\s*$/)
      else
        false
      end
    end

    # コメントのみから成る行の範囲を取得
    # @return [Array<Range>]
    def comment_ranges
      return @comment_ranges if @comment_ranges
      
      comment_rows = []
      lines.size.times do |row|
        comment_rows << row if comment?(row)
      end
      @comment_ranges = UniPropUtils::RangeProcessor.array_to_ranges(comment_rows)

      @comment_ranges
    end

    # missing valueについて記述された行のみを取得
    # @return [Array<String>]
    def missing_value_lines
      @missing_value_lines ||= lines.filter { _1.match?(/@missing/) }
    end

    # 空行・コメントのみ以外の行の範囲を取得
    # @return [Array<Range>]
    def information_containing_ranges
      UniPropUtils::RangeProcessor.sub(Range.new(0, lines.size-1), comment_ranges)
    end

    # row, columnの値がprop.property_value_typeの型にマッチする値かを判定
    # @param [Property] prop
    # @param [Integer] row
    # @param [Integer] column
    # @return [Boolean]
    # @note Miscellaneousプロパティの判定方法はsettings.rbで指定可能
    def property_value_type_match?(row, column, prop)
      if prop.property_value_type == :miscellaneous
        return type_match?(row, column, prop.miscellaneous_format, prop)
      else
        return type_match?(row, column, prop.property_value_type, prop)
      end
    end

    # row, columnの値がtypeの型にマッチする値かを判定
    # @param [Integer] row
    # @param [Integer] column
    # @param [Symbol] type
    # @param [Property] prop
    # @return [Boolean]
    def type_match?(row, column, type, prop)
      # データファイルには、一番右の;の右側に情報が記述されるフォーマットと、コメントのみが記述されるフォーマットが存在
      # row行目だけを取り出し、一番右側の列が値を持たない(value_atがnil)場合、たまたまrow行目に値が記述されていない(値が空文字列)だけか、ファイル全体として一番右の列に値が記述されていないのか、判定不可能
      # そのため、ここでは値が存在しない列に対しては、空文字列を値として持つと仮定して判定を行う
      value = value_at(row, column) || ""

      case type
      when :catalog, :enumerated
        return UniPropUtils::TypeJudgementer.validate_enumerative(value, prop)
      when :binary
        return UniPropUtils::TypeJudgementer.validate_binary(value, prop)
      when :string
        return UniPropUtils::TypeJudgementer.validate_string(value)
      when :numeric
        return UniPropUtils::TypeJudgementer.validate_numeric(value)
      when :jamo_short_name
        # Jamo_Short_Nameは、プロパティ値のエイリアス1つか、空文字列(missing)を値として取る(15.0.0でコードポイント110Bの値が空文字列として明示的に記述されている)
        return prop.property_values.any? { _1.has_alias?(value) } || value.empty?
      when :script_extensions
        # Script_Extensionsは1つ以上のScriptプロパティのプロパティ値を取る。2つ以上取る場合、ファイル内では半角スペース区切りで記述される。
        return value.split.all? { version.find_property("Script").has_property_value?(_1) }
      when :text
        # 任意の文字列(空文字列も含む)である事を表すtextでは常にtrueを返す
        return true
      else
        return false
      end
    end

    # column列目の中で、propが取りうる値の範囲を取得
    # @param [Integer] column
    # @param [Property] prop
    # @return [Array<Range>]
    def property_value_type_match_ranges(column, prop)
      # miscellanesou_format==unqueの場合、ファイル内の全範囲をreturn
      if prop.property_value_type==:miscellaneous && prop.miscellaneous_format==:unique
        if unique_column?(column, prop.unique_threshold)
          return information_containing_ranges
        else
          return []
        end
      end

      # それ以外の場合、property_value_type_match? がtrueとなる行の範囲をreturn
      property_value_including_rows = []

      lines.size.times do |row|
        if property_value_type_match?(row, column, prop)
          property_value_including_rows << row
        end
      end

      UniPropUtils::RangeProcessor.array_to_ranges(property_value_including_rows)
    end

    # row行目の列数を取得
    # @param [Integer] row
    # @return [Integer]
    def column_size(row)
      shaped_line = shaped_lines[row].to_a
      shaped_line[-1]&.empty? ? shaped_line.size-1 : shaped_line.size
    end

    # rangeで指定された行の範囲内のうち、最大の列数を取得
    # @param [Range<Integer>]
    # @return [Integer]
    def max_column_size(range)
      range.map{column_size(_1)}.max
    end

    # property_value_type_match_rangesの最小値を下限、最大値を上限とする範囲の中で、空行、コメント行、column列目の値がpropの行のいずれかに該当する範囲を取得
    # @return [Array<Range<Integer>>]
    def verbose_property_value_type_match_ranges(column, prop)
      prop_ranges = property_value_type_match_ranges(column, prop)

      if prop_ranges.empty?
        return prop_ranges
      else
        prop_begin_col = UniPropUtils::RangeProcessor.min(prop_ranges)
        prop_end_col = UniPropUtils::RangeProcessor.max(prop_ranges)

        return UniPropUtils::RangeProcessor.sum_up(
          comment_ranges.map { UniPropUtils::RangeProcessor.cut_external(_1, prop_begin_col, prop_end_col) }.compact + prop_ranges
        )
      end
    end    
    
    # 修正済みメタデータを参照し、ファイル内に含まれるプロパティを取得
    # @return [Set<Property>]
    def actual_properties
      @actual_properties ||= version.version_metadata.propfile_to_actual_properties[self]
    end

    # @return [Array<Array<String>>]
    def shaped_missing_value_lines
      @shaped_missing_value_lines ||= missing_value_lines.map {
        _1.gsub(/\s/, '')
          .split(/;/)
      }
    end

    # @return [PropFileValueGroup]
    def propfile_value_group
      @propfile_value_group ||= PropFileValueGroup.new(self)
    end

    def is_derived?
      basename_prefix.start_with?(/Derived/)
    end

    class PropertyAliases < self
      def is_meta_file?() true; end

      # PropertyAliasesを解析し、タイプとプロパティの関係を取得
      # @return [Hash<String, Set<Array<String>>>]
      def property_value_type_to_shaped_lines
        return @property_type_to_shaped_lines if @property_type_to_shaped_lines

        @property_type_to_shaped_lines = Hash.new { |hash, key| hash[key]=Set.new }
        mps = UniPropUtils::FileRegexp.matched_positions(cache_path.read, /#\s*={10,}\n#\s(.+)\sProperties\n#\s*={10,}/)

        mps.size.times do |i|
          mp = mps[i]
          next_mp = mps[i+1]
         
          begin_i = mp[:end_col] + 1
          end_i = next_mp ? next_mp[:begin_col] : lines.size
          
          property_type = mp[:match_data][1]

          (begin_i...end_i).each { @property_type_to_shaped_lines[property_type] << shaped_lines[_1] if !shaped_lines[_1].empty?}
        end

        @property_type_to_shaped_lines
      end
    end

    class PropertyValueAliases < self
      def is_meta_file?() true; end

      # このPropertyValueAliasesに含まれる、プロパティ値のエイリアスの一覧を取得。
      # @return [Set]
      def property_value_aliases
        return @property_value_aliases if @property_value_aliases

        @property_value_aliases = Set.new

        contents[1..].each { @property_value_aliases.merge(_1) }

        @property_value_aliases
      end
    end

    class UnihanFile < self
      def initialize(cache_path, version, strip_regexp: nil, split_regexp: nil)
        if !strip_regexp || !split_regexp
          # strip_regexp, split_regexpが引数で指定されていない場合、settings.rbの記述を使用
          file_format = version.prop_data.settings.unihan_file_format(version.version_name)
          
          strip_regexp ||= file_format[:strip]
          split_regexp ||= file_format[:split]
        end
        super(cache_path, version, strip_regexp: strip_regexp, split_regexp: split_regexp)
      end

      # Unihanの場合はファイル名とパスが一致せず、Unihan.zipに記述されているため、Unihan.zipをダウンロード・展開
      def download_myself
        UniPropUtils::DownloaderWrapper.download_unihan(version.version_name, version.cache_path.parent)
        UniPropUtils::FileManager.recursive_unzip(version.file_cache_paths)
      end

      def is_unihan_file?() true end
    end
  end

  class Version
    include Comparable
    attr_accessor :directory, :cache_path
    attr_reader :major, :minor, :tiny, :prop_data, :version_name, :unicode_beta, :excluded_extensions, :excluded_directories, :excluded_files, :included_files, :property_aliases_file_name, :property_value_aliases_file_name

    def initialize(prop_data, version_name)
      @prop_data = prop_data
      @version_name = version_name
      @major, @minor, @tiny = self.class.parse(@version_name).values
      @cache_path = @prop_data.cache_path + Pathname.new(@version_name)
      @unicode_beta = @prop_data.settings.unicode_beta(@version_name)
      @excluded_extensions = @prop_data.settings.excluded_extensions(@version_name).map { _1.downcase }
      @excluded_directories = @prop_data.settings.excluded_directories(@version_name).map { _1.downcase }
      @excluded_files = @prop_data.settings.excluded_files(@version_name).map { _1.downcase }
      @included_files = @prop_data.settings.included_files(@version_name).map { _1.downcase }
      @property_aliases_file_name = "propertyaliases"
      @property_value_aliases_file_name = "propertyvaluealiases"
    end

    # バージョン名を対応するx.y.z形式に変換する
    # @param [String] version_name
    # @return [Hash<Symbol,Integer>] Symbolはmajor,minor,tiny
    def self.parse(version_name)
      case version_name
      when /^(\d+)\.(\d+)\.(\d+)$/,  /^(\d+)\.(\d+)-Update(\d+)$/
        return {major: $1.to_i, minor: $2.to_i, tiny: $3.to_i}
      when /^(\d+)\.(\d+)-Update$/
        return {major: $1.to_i, minor: $2.to_i, tiny: 0}
      else
        raise ParseError
      end
    end

    # バージョン名からweightを算出
    # @param [String] version_name
    # @return [Integer]
    def self.name_to_weight(version_name)
      parsed_version_name = parse(version_name)
      parsed_version_name[:major]*10000 + parsed_version_name[:minor]*100 + parsed_version_name[:tiny]
    end

    # Versionに含まれるファイルのうち、settings.rbの記述に一致するファイルを全件unicode.orgからダウンロード
    def download_version_files(since: true)
      UniPropUtils::DownloaderWrapper.download_version(version_name, cache_path.parent, excluded_extensions, excluded_directories, excluded_files, included_files, unicode_beta: unicode_beta, since: since)
    end

    # ファイル名を指定してversionのファイルをダウンロード
    # @param [String] file_name Unicodeファイルのbasename_prefixに一致するファイル名
    def download_file(file_name, since: true)
      if UniPropUtils::FileManager.unihan_file?(file_name)
        UniPropUtils::DownloaderWrapper.download_unihan(version_name, cache_path.parent, unicode_beta: unicode_beta, since: since)
        UniPropUtils::FileManager.recursive_unzip(file_cache_paths)
      else
        UniPropUtils::DownloaderWrapper.unicode_basename_download(file_name, version_name, cache_path.parent, unicode_beta: unicode_beta, since: since)
      end
    end

    # Versionに含まれるPropFile一覧を取得する
    # @param [Boolean] reconfirm unicode.orgからファイルをダウンロードする処理は最初の1回のみ行われ、2回目以降はローカルキャッシュを参照するが、reconfirm==trueの場合、ローカルキャッシュの参照は行わず、再度unicode.orgからファイルをダウンロードする。
    # @return [Set<PropFile>]
    def files(reconfirm: false, since: true, reload: false)
      if @files && !reconfirm && !reload
        return @files
      end

      if !cache_path.exist? || reconfirm
        download_version_files(since: since)
      end

      @files = cache_files(since: since, reload: reload)
      @files
    end

    # キャッシュに保存されているファイルを取得
    # @note キャッシュに該当するディレクトリが存在しない場合、空のSetが返る
    # @param [Boolean] reconfirm unicode.orgにアクセスし、キャッシュのファイルを全て最新バージョンに更新する
    # @param [Boolean] reload trueの場合、メモ化した値を使用せず、キャッシュを再読み込みする
    # @return [Set<PropFile>]
    def cache_files(reconfirm: false, since: true, reload: false)
      return @cache_files if @cache_files && !reconfirm && !reload
    
      # キャッシュを最新バージョンに更新
      if reconfirm
        cache_files(since: since).each { download_file(_1.basename_prefix, since: since)}
      end

      # Unihan.zipを展開
      UniPropUtils::FileManager.recursive_unzip(file_cache_paths)

      @cache_files = Set.new

      file_cache_paths.each do |path|
        # 4.1.0ではUnihan.zipの中のUnihan.txtと、そうでないUnihan.txtが存在し、ファイルの内容は同一
        # そのような場合に対処するため、basename_prefixが同一のPropFileオブジェクトが既に作成されている場合、オブジェクトの作成を行わない
        next if @cache_files.any? { _1.basename_prefix==UniPropUtils::FileManager.prefix(path) }

        propfile = create_propfile(path)
        @cache_files << propfile if propfile
      end

      @cache_files
    end

    # cache_pathに保存されているファイルのうち、settings.rbで使用する事にされているファイルのパスを取得
    # @note プログラム実行中にキャッシュの内容は変更されるため、メモ化は行わず、都度探索を行う
    # @return [Array<Pathname>]
    def file_cache_paths
      UniPropUtils::FileManager.filter_file(cache_path.glob('**/*'), excluded_extensions, excluded_directories, excluded_files, included_files)
    end

    # settings.rbの内容を考慮しながらPathnameオブジェクトからPropFileオブジェクトを作成
    # @param [Pathname] file_path
    # @return [PropFile]
    def create_propfile(path)
      return if UniPropUtils::FileManager.ext_no_dot(path).downcase != "txt" 
      
      # pathがPropertyAliases.txt, PropertyValueAliases.txtの場合、それらのクラスのインスタンスをreturn
      if UniPropUtils::FileManager.prefix(path).downcase == property_aliases_file_name
        return property_aliases_file
      elsif UniPropUtils::FileManager.prefix(path).downcase == property_value_aliases_file_name
        return property_value_aliases_file
      
      # UnihanのファイルにはUnihanFileのインスタンスをreturn
      elsif UniPropUtils::FileManager.unihan_file?(path, unihan_file_names)
        return PropFile::UnihanFile.new(path, self)
      else
        return PropFile.new(path, self)
      end
    end

    # file_nameに対応するファイルのキャッシュのパスを取得
    # @param [String] file_name Unicodeファイルのprefixに一致するファイル名
    # @return [Pathname] file_nameに対応するキャッシュのローカルのパス
    # @raise [FileNotFoundError] ファイルがキャッシュに存在しない場合発生
    def find_cache_file_path(file_name)
      path = file_cache_paths.find { Alias.canonical(UniPropUtils::FileManager.prefix(_1)) == Alias.canonical(file_name) }

      if path
        return path
      else
        raise(FileNotFoundError, "#{file_name} has not yet been downloaded.")
      end
    end

    # キャッシュにfile_nameが表すファイルが存在するかを判定
    def has_cache_file?(file_name)
      return !!find_cache_file_path(file_name)
    rescue
      false
    end

    # ファイル名/ファイルパスを指定してバージョン内のPropFileオブジェクトを取得
    # @param [String/Pathname] propfile
    # @param [Boolean] confirm trueの場合、ファイルが存在しない際にUnicode.orgからのダウンロードを試みる
    # @raise [FileNotFoundError] ファイルが存在しない場合に発生
    # @return [PropFile]
    def find_file(propfile, confirm: true)
      if propfile.class==String
        file = files.find { |f| Alias.canonical(f.basename_prefix) == Alias.canonical(UniPropUtils::FileManager.prefix(propfile)) }
      elsif propfile.class==Pathname
        file = files.find { |f| f==propfile }
      end
      
      if file
        return file
      else
        if confirm==true
          if propfile.class==Pathname
            propfile = propfile.basename
          end
          download_file(UniPropUtils::FileManager.prefix(propfile))
          # ダウンロード後、キャッシュを再読み込みして再度検索を行う
          files(reload: true)
          return find_file(propfile, confirm: false)
        end

        raise(FileNotFoundError, "#{propfile} is not found.")
      end
    end

    # @param [String/Pathname] propfile
    def has_file?(propfile)
      !!find_file(propfile)
    rescue
      false
    end

    # ProeprtyAliasesに該当するPropFileを取得
    # @return [PropertyAliases]
    def property_aliases_file
      return @property_aliases_file if @property_aliases_file

      if !has_cache_file?(property_aliases_file_name)
        download_file(property_aliases_file_name)
      end

      property_aliases_file_path = find_cache_file_path(property_aliases_file_name)
        
      if property_aliases_file_path
        @property_aliases_file = PropFile::PropertyAliases.new(property_aliases_file_path, self)
      end

      @property_aliases_file
    end

    # ProeprtyValueAliasesに該当するPropFileを取得
    # @return [PropertyValueAliases]
    def property_value_aliases_file
      return @property_value_aliases_file if @property_value_aliases_file

      if !has_cache_file?(property_value_aliases_file_name)
        download_file(property_value_aliases_file_name)
      end

      property_value_aliases_file_path = find_cache_file_path(property_value_aliases_file_name)
        
      if property_value_aliases_file_path
        @property_value_aliases_file = PropFile::PropertyAliases.new(property_value_aliases_file_path, self)
      end

      @property_value_aliases_file
    end

    # PropertyAliasesに記述されているProperty一覧を取得
    # @note exclude_unihan==falseの場合であっても、PropertyAliasesに記述されていないUnihanのプロパティは取得されない
    # @param [Boolean] exclude_unihan trueの場合、Unihanのプロパティを除外
    # @return [Set<Property>]
    def properties(exclude_unihan: false)
      if !@properties
        @properties = Set.new

        # PropertyAliasesをもとに、全プロパティのPropertyオブジェクトを作成
        property_aliases_file.property_value_type_to_shaped_lines.each do |property_value_type, shaped_lines|
          shaped_lines.each do |shaped_line|
            new_prop = Property.new(self, *shaped_line)
            new_prop.property_value_type = property_value_type.downcase
            @properties << new_prop
          end
        end
      end

      if exclude_unihan
        return @properties - unihan_properties
      else
        return @properties + unihan_properties
      end
    end

    def has_unihan?
      unihan_files.size!=0
    end

    # @return [UnihanProp]
    def unihanprop
      @unihanprop ||= UnihanProp.new(unihan_files)
    end

    # return [Array<Property>]
    def unihan_properties
      unihanprop.unihan_properties
    end

    # @return [Hash<Property, Array<PropertyValue>>]
    def property_to_property_values
      return @property_to_property_values if @property_to_property_values

      @property_to_property_values = Hash.new { |hash, key| hash[key]=[] }

      property_value_aliases_file.netto_shaped_lines.each do |shaped_line|
        prop = find_property(shaped_line[0])
        @property_to_property_values[prop] << PropertyValue.new(prop, *shaped_line[1..])
      end

      @property_to_property_values
    end

    # Version内に存在する、property_nameをaliasとして持つPropertyオブジェクトを取得
    # @param [String/Property] property
    # @return [Property]
    # @raise [PropertyNotFoundError] プロパティが存在しない場合に発生
    def find_property(property)
      if property.class==String
        prop = properties.find { _1.has_alias?(property) }
      elsif property.class==Property
        # エイリアス名が長いほど、正しい答えを得られる可能性が高い
        # エイリアス名が短いほど、複数のプロパティが同じエイリアス名を持っている可能性が高い
        property.aliases.sort_by{ _1.size }.reverse_each do |prop_alias|
          return find_property(prop_alias) if has_property?(prop_alias)
        end
      end
      
      if prop
        return prop
      else
        raise PropertyNotFoundError.new(property)
      end
    end

    # @param [Property/String] prop
    def has_property?(prop)
      !!find_property(prop)
    rescue
      false
    end

    # @param [String] property_name
    # @param [String/Property] property
    # @return [Property]
    # @raise [PropertyNotFoundError] プロパティが存在しない場合に発生
    def find_unihan_property(property)
      if property.class==String
        prop = unihan_properties.find { _1.has_alias?(property) }
      elsif property.class==Property
        # エイリアス名が長いほど、正しい答えを得られる可能性が高い
        # エイリアス名が短いほど、複数のプロパティが同じエイリアス名を持っている可能性が高い
        property.aliases.sort_by{ _1.size }.reverse_each do |prop_alias|
          return find_unihan_property(prop_alias) if has_unihan_property?(prop_alias)
        end
      end
      
      if prop
        return prop
      else
        raise PropertyNotFoundError.new(property)
      end
    end

    # @param [String/Property] property
    def has_unihan_property?(property)
      !!find_unihan_property(property)
    rescue
      false
    end

    # contentを対応するPropertyオブジェクトに変換して返す。対応するPropertyオブジェクトが無い場合にはnilを返す。contentがArrayの場合、再帰的に変換を実行。
    # @param [String/Array<String>] content
    # @return [Property?/Array<Property?>]
    def convert_property(content)
      if content.class==Array
        return content.map { convert_property(_1) }
      else
        return find_property(content) rescue nil
      end
    end

    # @return [Array<Property>] Versionに含まれるUnihanファイル
    def unihan_files
      @unihan_files ||= files.filter { _1.is_unihan_file? }
    end

    # @return [Array<String>?] settings.rbに記述されているUnihanファイル名
    def unihan_file_names
      return @unihan_file_names if @unihan_file_names

      # キャッシュにUnihanファイルが無い場合、ダウンロードを試みる
      if file_cache_paths.all? { !UniPropUtils::FileManager.unihan_file?(_1) }
        begin
          UniPropUtils::DownloaderWrapper.download_unihan(version_name, cache_path.parent)
          UniPropUtils::FileManager.recursive_unzip(file_cache_paths)
        rescue FileNotFoundError
          # Unicode.orgの対象バージョンにもUnihan.zip, Unihan.txtが存在しない場合(FileNotFoundError)は処理を継続
          # downloader.rbに関する例外などはrescueしない
        end
      end

      @unihan_file_names = Set.new
      file_cache_paths.each { @unihan_file_names << UniPropUtils::FileManager.prefix(_1) if UniPropUtils::FileManager.unihan_file?(_1) }
      @unihan_file_names = @unihan_file_names.to_a
      @unihan_file_names
    end
    
    # @return [VersionMetadata]
    # @raise [MetadataNotFoundError] Versionに対応するメタデータが存在しない場合に発生
    def version_metadata
      @version_metadata ||= VersionMetaData.new(self, prop_data.metadata.find_raw_version_metadata(version_name))
    end

    def has_version_metadata?
      !!version_metadata
    rescue
      false
    end

    # settings.rbのPROPERTIES_INFORMATIONのmiscellaneous_formatsを、Propertyオブジェクトをキーとして整理する
    # @note settings.rbに定義が無いプロパティをキーに指定すると、空のハッシュを返す
    # @return [Hash<Property,Hash<Symbol,String>>]
    def property_to_miscellaneous_formats
      return @property_to_miscellaneous_formats if @property_to_miscellaneous_formats
      @property_to_miscellaneous_formats = Hash.new { |hash,key| hash[key]={} }

      properties.each do |prop|
        prop.uncanonicaled_aliases.each do |als|
          fmt = prop_data.settings.miscellaneous_format(version_name, als)

          if fmt
            @property_to_miscellaneous_formats[prop] = fmt
            break
          end
        end
      end

      @property_to_miscellaneous_formats
    end
    
    def <=>(other)  weight <=> other.weight  end

    def weight()  major*10000 + minor*100 + tiny  end
  end
end