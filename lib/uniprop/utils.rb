module UniPropUtils
  class DownloaderWrapper
    # UNICODE_PUBLIC = "https://sw.it.aoyama.ac.jp/2022/sakaida/UCD/"
    UNICODE_PUBLIC = "https://www.unicode.org/Public/"

    class << self
      # 現在公開されているバージョンの名前をすべて取得
      # @return [Array<String>]
      def get_version_names
        doc = Nokogiri::HTML(URI.open(UNICODE_PUBLIC))

        version_names = []
        doc.css('tr td a').each do |a|
          begin
            version_name = a.content[..-2]
            UniProp::Version.parse(version_name)
            version_names << version_name
          rescue UniProp::ParseError
          end
        end

        version_names
      end

      # URLを指定して1つのUnicodeファイルをダウンロード
      # @note ベータ版ファイルをDownloader::downloadでダウンロードすると、ファイル名が異なる場合に古いファイルが削除されない。その問題を回避するため、ファイル名をprefixのみを使用してダウンロードするメソッド
      # @param [Pathname] url ダウンロードするファイルのURLの絶対パス
      # @param [Pathname] cache_dir_path ダウンロードしたファイルを保存するディレクトリの絶対パス。この下の階層に15.0.0などのバージョン名を表すディレクトリが作成される
      def unicode_download(url, cache_dir_path, unicode_beta: false, since: true)
        relative_url = url.relative_path_from(UNICODE_PUBLIC) # バージョン名より下の階層のパス
        file_cache_path = Pathname.new(cache_dir_path)+relative_url.parent
        
        options = {cache_dir: false}
        if unicode_beta
          options[:unicode_beta] = "YES"
        end
        
        Downloader.download(UNICODE_PUBLIC+relative_url.to_s, FileManager.prefix_path(relative_url).to_s, dir=file_cache_path.to_s, since=since, options=options)
      end

      # version_nameに該当するバージョンのファイルをダウンロードする
      # @param [String] version_name
      # @param [Pathname] cache_dir_path
      # @param [Array<String>] excluded_extensions ダウンロードしない拡張子
      # @param [Array<String>] excluded_directories ダウンロードしないディレクトリの名前。excluded_directoriesに名前が含まれるディレクトリより下の階層にあるファイルは、ダウンロード対象から除外される
      # @param [Array<String>] excluded_files ダウンロードしないファイルの名前
      # @param [Array<String>] included_files excluded系引数に除外されている場合でも、included_filesに名前が含まれるファイルはダウンロードされる
      # @param [Boolean] unicode_beta ダウンロード対象がベータ版ならtrue
      def download_version(version_name, cache_dir_path, excluded_extensions, excluded_directories, excluded_files, included_files, unicode_beta: false, since: true)
        file_urls = FileManager.filter_file(files_in_version(version_name), excluded_extensions, excluded_directories, excluded_files, included_files)

        file_urls.each { unicode_download(_1, cache_dir_path, unicode_beta: unicode_beta, since: since) }
      end

      # version_nameで指定したバージョンに含まれるファイルのパスを取得
      # @param [String] version_name
      # @return [Array<Pathname>] URLのPathnameのArray
      def files_in_version(version_name)
        UniProp::Version.parse(version_name)

        version_path = Pathname.new(UNICODE_PUBLIC) + Pathname.new(version_name)

        files_in(version_path.to_s)
      end

      # urlよりも下の階層にあるファイルのURLをPathnameオブジェクトで主t九
      # @param [String] url URLの絶対パスを表す文字列
      # @return [Array<Pathname>]
      def files_in(url)    
        doc = Nokogiri::HTML(URI.open(url))

        files = []
        doc.css('tr td a').each do |a|
          if a.keys.include?("href") && !a['href'].start_with?("/")
            if a['href'].end_with?("/")
              child_dir_path = Pathname.new(url) + Pathname.new(a['href'])

              files.concat(files_in(child_dir_path.to_s))
            else
              files << Pathname.new(url) + Pathname.new(a.content)
            end
          end
        end
        files
      end

      # prefixがbasename_prefixと一致するファイルを取得
      # @param [String] basename_prefix
      # @param [String] version_name
      # @return [Pathname]
      def find_file_path(basename_prefix, version_name)
        files_in_version(version_name)
          # 例えば4.1.0にはPropList.txtとPropList.htmlの両方が存在
          # txtとzipのみを検索に使用
          .filter { ["txt", "zip"].include?(FileManager.ext_no_dot(_1)) }
          .find { UniProp::Alias.canonical(FileManager.prefix(_1)) == UniProp::Alias.canonical(basename_prefix) }
      end

      # basename_prefixとversion_nameでファイルを指定してダウンロード
      def unicode_basename_download(basename_prefix, version_name, cache_dir_path, unicode_beta: false, since: true)
        path = find_file_path(basename_prefix, version_name)
        
        if path
          unicode_download(path, cache_dir_path, unicode_beta: unicode_beta, since: since)
        else
          raise(UniProp::FileNotFoundError, "#{basename_prefix} is not found in #{version_name}")
        end
      end

      # Unihan.zipをダウンロード
      def download_unihan(version_name, cache_dir_path, unicode_beta: false, since: true)
        unicode_basename_download("unihan", version_name, cache_dir_path, unicode_beta: unicode_beta, since: since)
      end
    end
  end

  class TypeJudgementer
    RE_SINGLE_CODEPOINT = /^[0-9A-Fa-f]{4,6}$/
    RE_RANGE_CODEPOINT = /^[0-9A-Fa-f]{4,6}\.\.[0-9A-Fa-f]{4,6}$/
    # NFKC_CaseFoldの00ADのように、空文字列を値に持つStringプロパティも存在するため、空文字列もRE_STRINGにマッチするような実装にしてある
    RE_STRING = /^([0-9A-Fa-f]{4,6}\s*)*$/
    RE_NUMERIC = /
                    ^-?\d{1,}$| # integer
                    ^-?\d{1,}.\d{1,}$| # float
                    ^-?\d{1,}\/\d{1,}$ # rational
                  /x
    RE_BINARY = /^Yes$|^Y$|^No$|^N$/


    class << self
      # @param [String] str
      def validate_single_codepoint(str)
        str.match?(RE_SINGLE_CODEPOINT)
      end

      # @param [String] str
      def validate_range_codepoint(str)
        str.match?(RE_RANGE_CODEPOINT)
      end

      # @param [String] str
      def validate_codepoint(str)
        str.match?(RE_SINGLE_CODEPOINT) || str.match?(RE_RANGE_CODEPOINT)
      end

      # @param [String] str
      def validate_numeric(str)
        str.match?(RE_NUMERIC)
      end

      # @param [String] str
      def validate_string(str)
        str.match?(RE_STRING)
      end

      # @param [String] str
      # @param [Property] property
      def validate_binary(str, property)
        str.match?(RE_BINARY) || property.has_alias?(str)
      end

      # @param [String] str
      # @param [Property] property
      def validate_enumerative(str, property)
        property.has_property_value?(str)
      end

      def validate_codepoints(array, threshold)
          return (array.filter{validate_codepoint(_1) }.size.to_f / array.size) > threshold
      end

      def validate_numerics(array, threshold)
          return (array.filter{validate_numeric(_1) }.size.to_f / array.size) > threshold
      end

      def validate_strings(array, threshold)
          return (array.filter{validate_string(_1) }.size.to_f / array.size) > threshold
      end

      def validate_binaries(array, properties, threshold)
          return (array.filter{validate_binary(_1, properties) }.size.to_f / array.size) > threshold
      end

      def validate_binaries_for_property(array, property, threshold)
          return (array.filter{validate_binary_for_property(_1, property) }.size.to_f / array.size) > threshold
      end
    end
  end

  class FileRegexp
    class << self
      def matched_positions(text, regexp)
        mp = []
        m = text.match(regexp)

        col_cnt = 0
        while m
          position = {}
          
          position[:match_data] = m
          col_cnt += m.pre_match.count("\n")
          position[:begin_col] = col_cnt
          col_cnt += m[0].count("\n")
          position[:end_col] = col_cnt
          position[:begin_point] = m.begin(0) - m.pre_match.rindex("\n").to_i() - 1
          position[:end_point] = position[:begin_point] + m[0].size - m[0].rindex("\n").to_i() -1
          
          mp << position
          text = m.post_match
          m = text.match(regexp)
        end
        
        mp
      end
    end
  end

  class FileManager
    class << self
      def filter_file(files, excluded_extensions, excluded_directories, excluded_files, included_files)
        files = files.dup
        original_files = files.dup
        excluded_extensions = excluded_extensions.map { _1.downcase }
        excluded_files = excluded_files.map { _1.downcase }
        included_files = included_files.map { _1.downcase }

        # remove files by excluded_extensions
        files = files.reject { excluded_extensions.include? ext_no_dot(downcase_path(_1)).downcase }
        
        # remove files by excluded_directories
        excluded_directories.each do |dir|
          files = files.reject { child?(dir, downcase_path(_1)) }
        end

        # remove files by excluded_files
        files = files.reject { excluded_files.include? prefix(downcase_path(_1)) }

        # remove test files
        files = files.reject { prefix(_1).end_with? "Test" }

        # add files by included_files
        original_files.each do |ori_f|
          included_files.each do |inc_f|
            if (prefix(ori_f).downcase==inc_f || ori_f.basename.to_s.downcase==inc_f) && !files.include?(ori_f)
              files << ori_f
            end
          end
        end

        files
      end

      def child?(parent, child)
        if parent.class == String
          child.descend.any? { _1.basename.to_s == parent }
        elsif parent.class == Pathname
          downcase_path(child).to_s.include? downcase_path(parent).to_s
        end
      end

      # pathの-数字より前の文字列を取得
      # @param [Pathname] path
      # @return [String]
      def prefix(path)
        path = Pathname.new(path)
        m = basename_no_ext(path).match(/^([\.\-0-9a-zA-Z_ ]+)-([\.0-9a-zA-Z_ ]+)$/)

        if m
          before_hyphen = m[1]
          after_hyphen = m[2]

          if after_hyphen.start_with?(/[0-9]/)
            return before_hyphen
          else
            return m[0]
          end
        else
          return basename_no_ext(path)
        end
      end

      # pathのbasename部分をprefixのみに変更したPathnameを取得
      # @param [Pathname] path
      # @return [Pathname]
      def prefix_path(path)
        path.parent + Pathname.new(prefix(path) + path.extname)
      end

      def downcase_path(path)
        Pathname.new(path.cleanpath.to_s.split("/").map { _1.downcase }.join("/")).cleanpath
      end

      def ext_no_dot(path)  
        path = Pathname.new(path)
        ext = path.extname
        if ext.empty?
          return ""
        else
          return ext[1..]
        end
      end

      def basename_no_ext(path)
        name = path.basename.to_s
        name.slice(0..(name.size-path.extname.size-1))
      end

      # pathsの中に含まれるzipファイルを全て展開
      # @param [Iterable<Pathname>] paths
      # @return [Boolean] 1つ以上のファイルが展開された場合true
      def unzip(paths)
        unzipped_f = false # 返り値用フラグ

        paths.each do |path|
          if ext_no_dot(path).downcase == "zip"
            
            # dir/hoge.zipを展開した場合、dir/unzipped/hoge に保存
            unzipped_cache_path = path.parent+Pathname.new("unzipped")+Pathname.new(prefix(path))

            FileUtils.mkdir(unzipped_cache_path.parent) if !unzipped_cache_path.parent.exist?

            # 既に展開済みファイルが存在する場合、展開処理は行わない
            if unzipped_cache_path.exist?
              break
            else
              FileUtils.mkdir(unzipped_cache_path)
            end

            Zip::File.open(path) do |zip_file|
              zip_file.each do |entry|
                zip_file.extract(entry, unzipped_cache_path+Pathname.new(entry.name))
              end
            end
            unzipped_f = true
          end
        end

        unzipped_f
      end

      # pathsの中に含まれるzipファイルを全て展開。zipファイルの中にzipファイルがある場合には再帰的に展開。
      # @param [Iterable<Pathname>] paths
      def recursive_unzip(paths)
        loop do 
          return if !unzip(paths)
        end
      end

      # pathがUnihanのファイルかを判定
      # @note unihan_file_namesでUnihanのファイル名を指定できる。nilの場合、Unihan*のワイルドカードが使用される。
      # @param [Pathname/String] file ファイルのパスまたはbasename_prefixに相当する文字列
      # @param [Array<String>] unihan_file_names
      def unihan_file?(file, unihan_file_names=nil)
        if file.class==Pathname
          file = prefix(file)
        end
        file = UniProp::Alias.canonical(file)

        if unihan_file_names
          unihan_file_names = unihan_file_names.map { UniProp::Alias.canonical(_1) }

          return unihan_file_names.include?(file)
        else
          return file.match?(/unihan.*/)
        end
      end
    end
  end

  class RangeProcessor
    class << self
      # rangesに含まれるRangeオブジェクトを結合した結果を含むArrayを取得
      # @param [Array<Range>] ranges
      # @return [Array<Range>]
      def sum_up(ranges)
        scattered_ranges = []
        ranges.each do |range|
          if range.class==Range
            scattered_ranges << range.to_a
          elsif range.class==Integer
            scattered_ranges << range
          end
        end
        
        array_to_ranges(scattered_ranges.flatten)
      end

      def sub(range_array1, range_array2)
        range_array1 = sum_up(range_array1)
        range_array2 = sum_up(range_array2)

        array1 = (range_array1.map { _1.to_a }).flatten
        array2 = (range_array2.map { _1.to_a }).flatten

        non_dup_array = (Set.new(array1) - Set.new(array2)).to_a
        array_to_ranges(non_dup_array)
      end

      # @param [Array<Integer>] array
      # @return [Array<Range<Integer>>]
      def array_to_ranges(array)
        array = array.uniq.sort << Float::INFINITY

        ranges = []

        pre_elm = nil
        begin_elm = nil

        array.each do |elm|
          if !pre_elm
            pre_elm = elm
            begin_elm = elm
          elsif elm != pre_elm+1
            ranges << Range.new(begin_elm, pre_elm)
            begin_elm = elm
          end
          pre_elm = elm
        end
        ranges
      end
      
      def intersection(range_array)
        if range_array.size==0
          return nil
        else
          common_set = range_array[0].to_set
        end

        range_array.each do |range|
          common_set &= range.to_set
        end

        array_to_ranges(common_set.to_a)[0]
      end

      def intersections_between_range_arrays(*range_arrays)
        common_set_of_range_arrays = nil

        range_arrays.each do |range_array|
          set_of_range_array = Set.new
          range_array.each { set_of_range_array.merge(_1.to_set) }
          
          if common_set_of_range_arrays
            common_set_of_range_arrays &= set_of_range_array
          else
            common_set_of_range_arrays = set_of_range_array
          end
        end

        array_to_ranges(common_set_of_range_arrays.to_a)
      end

      # array内のRangeのいずれかに含まれるIntegerのうち、最小のものを取得
      # @param [Array<Range<Integer>>] array
      # @return [Integer?] arrayが空の場合nil
      def min(array)
        array.min_by { _1.min }&.min
      end

      # array内のRangeのいずれかに含まれるIntegerのうち、最大のものを取得
      # @param [Array<Range<Integer>>] array
      # @return [Integer?] arrayが空の場合nil
      def max(array)
        array.max_by { _1.max }&.max
      end

      # rangeを最小がlower_limit、最大がupper_limitの範囲内で切って返す(範囲の外部を切る)。切った結果、範囲が残らない場合、nilを返す
      # @note 残す範囲にlower_limit, upper_limitも含まれる
      # @param [Range<Integer>?] range
      # @param [Integer] lower_limit
      # @param [Integer] upper_limit
      # @return [Range<Integer>?]
      def cut_external(range, lower_limit, upper_limit)
        return nil if range.max<lower_limit || upper_limit<range.min

        result_min = (range.min<lower_limit) ? lower_limit : range.min
        result_max = (upper_limit<range.max) ? upper_limit : range.max
        result_min..result_max
      end

      # rangeを最小がlower_limit、最大がupper_limitの範囲内になるよう切って返す(範囲の内部を切る)。切った結果、範囲が残らない場合、nilを返す
      # @note 残す範囲にlower_limit, upper_limitは含まれない
      # @param [Array<Range<Integer>>] range
      # @param [Integer] lower_limit
      # @param [Integer] upper_limit
      # @return [Range<Integer>?]
      def cut_internal(range, lower_limit, upper_limit)
        inner_range =  cut_external((lower_limit..upper_limit), range.min, range.max)
        return [range] if !inner_range

        result = []
        if range.min < inner_range.min
          result << (range.min .. (inner_range.min-1))
        end
        if inner_range.max < range.max
          result << ((inner_range.max+1) .. range.max)
        end

        result
      end

      # a..b形式のstrをRange<Integer>に変換
      # @note strはRange<Integer>を表している必要がある
      # @param [String] str
      # @return [Range<Integer>]
      # @raise [ConvertError] strがRange<Integer>を表していない場合発生
      def str_to_range(str)
        m = str.match(/^(\d+)\.\.(\d+)$/)
        if m
          return Range.new(m[1].to_i, m[2].to_i)
        else
          raise ConvertError, "Argument must be parsed as Range of Integer"
        end
      end
    end
  end

  class CodepointConverter
    class << self
      # String型のcodepointをIntegerを使用したオブジェクトに変換
      # @param [String] codepoint_str
      # @return [Range<Integer,Integer>/Integer] 返る値はcodepoint_strの形式による
      def str_to_int(codepoint_str)
        if TypeJudgementer.validate_range_codepoint(codepoint_str)
          m = codepoint_str.match(/^([0-9A-Fa-f]{4,6})\.\.([0-9A-Fa-f]{4,6})$/)

          begin_codepoint = m[1]
          end_codepoint = m[2]

          return Range.new(begin_codepoint.hex, end_codepoint.hex)

        elsif TypeJudgementer.validate_single_codepoint(codepoint_str)
          return codepoint_str.hex
        else
          raise(ConvertError, "#{codepoint_str} is not a codepoint")
        end
      end
    end
  end

  class ConvertError < StandardError; end
end