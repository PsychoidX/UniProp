module UniProp
  class PropData
    attr_reader :excluded_extensions, :excluded_directories, :excluded_files, :metadata_path
    attr_accessor :cache_path, :settings
    
    # @note VersionMetaDataRecreator#output_metadata_revising_hintsなど、2つ以上のメタデータを使用して処理を行う場合がある。そのような場合に対応するため、PropDataは1つのsettings.rbと1つのメタデータを使用し、Unicodeのファイル全体を扱うためのクラスとした。
    def initialize(settings_path, metadata_path=nil)
      @settings = Settings.new(settings_path)
      cache_path_str = ENV["UniPropCache"] || @settings.cache_path
      @cache_path = Pathname.new(cache_path_str).cleanpath.expand_path
      @metadata_path = metadata_path
    end

    # unicode.orgから存在するバージョンの一覧を取得し、それを元にVersionオブジェクトを作成する
    # @note メタデータが紐づけられていればその情報を使用し、紐づけられていなければUnicode.orgから情報を取得
    # @param [Boolean] update trueの場合バージョン一覧を再取得
    # @return [Set<Version>]
    def versions(update: false)
      return @versions if @versions && !update

      @versions = Set.new

      if has_metadata?
        metadata.version_names(update_metadata: true, confirm: update).each { @versions << Version.new(self, _1) }
      else
        UniPropUtils::DownloaderWrapper.get_version_names.each { @versions << Version.new(self, _1) }
      end

      @versions
    end

    # @return [EfficientVersion]
    def find_efficient_version(version_name)
      weight = Version.name_to_weight(version_name)
      @weight_to_efficient_version ||= {}
      return @weight_to_efficient_version[weight] if @weight_to_efficient_version[weight]

      if metadata.version_names.map { Version.name_to_weight(_1) }.include?(weight)
        @weight_to_efficient_version[weight] = EfficientVersion.new(self, version_name)
      else
        raise VersionNotMatchedError, "version #{version_name} is not exists"
      end

      @weight_to_efficient_version[weight]
    end

    # @param [String] version_name
    # @param [Boolean] reconfirm trueの場合、version_nameに対応するバージョンが見つからない時にバージョン一覧を取得する
    # @return [Version]
    def find_version(version_name, reconfirm: true)
      parsed_version_name = Version.parse(version_name)
          
      versions.each do |version|
        if version.major == parsed_version_name[:major] && version.minor == parsed_version_name[:minor] && version.tiny == parsed_version_name[:tiny] 
          return version
        end
      end

      # 一致するバージョンが見つからなかった場合
      if reconfirm
        versions(update: true) # バージョン一覧を更新
        find_version(version_name, reconfirm: false)
      else
        raise VersionNotMatchedError
      end
    end

    # vesionsのうち、最も古いバージョンを取得
    # @return [Version]
    def oldest_version
      versions.sort_by { _1.weight } .first
    end

    # versionsのうち、最も新しいバージョンを取得
    # @return [Version]
    def latest_version
      versions.sort_by { _1.weight } .last
    end

    # @return [Metadata]
    # @raise [MetaDataNotFoundError] PropDataのinitialize時にmetadata_pathを指定していない場合に発生
    def metadata
      return @metadata if @metadata

      if metadata_path
        @metadata = MetaData.new(self, metadata_path)
        return @metadata
      else
        raise(MetaDataNotFoundError, "This PropData object doesn't have metadata path.")
      end
    end

    # @return [EfficientMetadata]
    # @raise [MetaDataNotFoundError] PropDataのinitialize時にmetadata_pathを指定していない場合に発生
    def efficient_metadata
      return @efficient_metadata if @efficient_metadata

      if metadata_path
        @efficient_metadata = EfficientMetaData.new(self, metadata_path)
        return @efficient_metadata
      else
        raise(MetaDataNotFoundError, "This PropData object doesn't have metadata path.")
      end
    end

    # PropDataがメタデータに紐づけられているかを判定
    def has_metadata?
      !!metadata rescue false
    end

    # version1とversion2の間で、ファイル名(basename_prefix)が同じPropFileのハッシュを作成
    # @param [Version] version1 キーとされるバージョン
    # @param [Version] version2 値とされるバージョン
    # @return [Hash<PropFile, PropFile>]
    def file_correspondence(version1, version2)
      return @file_correspondences[version1][version2] if @file_correspondences&&@file_correspondences[version1]&&@file_correspondences[version1][version2]

      propfile_to_same_name_propfile = {}
      version1.files.each do |f1|
        version2.files.each do |f2|
          if Alias.canonical(f1.basename_prefix)==Alias.canonical(f2.basename_prefix)
            propfile_to_same_name_propfile[f1] = f2
            break # 1つのバージョン内にbasename_prefixが同じファイルは2つ以上無いので、1つ見つかった段階でbreakする
          end
        end
      end

      @file_correspondences ||= {}
      @file_correspondences[version1] ||= {}
      @file_correspondences[version1][version2] = propfile_to_same_name_propfile

      @file_correspondences[version1][version2]
    end

    # metadata_pathのファイルをnew_metadataの内容に上書き
    # @param [Array/Hash] new_metadata JSONとして解釈できるオブジェクト
    # @raise [MetaDataNotFoundError] PropDataがメタデータに関連付けられていない場合に発生
    def update_metadata(new_metadata)
      if metadata_path && metadata_path.exist?
        metadata_path.write(JSON.pretty_generate(new_metadata))
      else
        raise MetaDataNotFoundError
      end
    end

    # @return [UnicodeManager]
    def unicode_manager
      @unicode_manager ||= UnicodeManager.new(self)
    end

    # @param [String] version_name
    # @return [VersionManager]
    def version_manager(version_name)
      vm = version_managers.find { _1.version.weight==Version.name_to_weight(version_name) }
      
      vm || raise(MetaDataNotFoundError, "MetaData for #{version_name} is not found.")
    end

    # メタデータに含まれる全バージョンのVersionManagerを作成
    # @return [Array<VersionManager>]
    def version_managers
      return @version_managers if @version_managers
      
      @version_managers = metadata.version_names
                            .filter { metadata.has_raw_version_metadata?(_1) }
                            .map { find_efficient_version(_1) }
                            .map { VersionManager.new(_1) }

      @version_managers
    end

    # @param [Pathname] path
    # @note pathが指定されていない場合、メタデータの先頭にproperty_をつけたファイルを使用
    # @return [PropertyMetadata]
    # @raise [MetaDataNotFoundError] pathが指定されているがそのpathが存在しない場合に発生
    def property_metadata(path=nil)
      return @property_metadata if @property_metadata

      select_path = !!path
      path ||= metadata_path.parent / ("property_"+metadata_path.basename.to_s)

      if !path.exist?
        if select_path
          raise MetaDataNotFoundError, "#{path} is not found."
        else
          path.write([])
        end
      end

      @property_metadata = PropertyMetaData.new(self, path)
    end
  end

  # 設定ファイルから値を取得するためのクラス
  class Settings
    attr_reader :setting_names
  
    # @param [Pathname] path 設定ファイルの絶対パス
    def initialize(path)
      require path
      @setting_names = {
        downloader_settings: DOWNLOADER_SETTINGS,
        files_information: FILES_INFORMATION,
        properties_information: PROPERTIES_INFORMATION
      }
    end
  
    # @param [Symbol] setting_name 検索する設定項目名
    # @param [String] version 検索するバージョン名
    # @note version==nilの場合、デフォルト値を取得
    # @param [keys] 検索を行う経路
    def search(setting_name, version, *keys)
      if version
        result = setting_names.dig(setting_name, version.to_sym, *keys)
        return result if result
      end
      setting_names.dig(setting_name, :default, *keys)
    end
  
    # @param [String] version
    # @return [Pathname]
    def cache_path(version=nil)
      search(:downloader_settings, version, :cache_path)
    end
  
    # @param [String] version
    # @return [Array<String>]
    def excluded_extensions(version=nil)
      search(:downloader_settings, version, :excluded_extensions)
    end
  
    # @param [String] version
    # @return [Array<String>]
    def excluded_directories(version=nil)
      search(:downloader_settings, version, :excluded_directories)
    end
  
    # @param [String] version
    # @return [Array<String>]
    def excluded_files(version=nil)
      search(:downloader_settings, version, :excluded_files)
    end
  
    # @param [String] version
    # @return [Array<String>]
    def included_files(version=nil)
      search(:downloader_settings, version, :included_files)
    end
  
    # @param [String] version
    # @return [Boolean]
    def unicode_beta(version=nil)
      search(:downloader_settings, version, :unicode_beta)
    end
  
    # @param [String] version
    # @param [String] file
    # @return [Hash<Symbol,String>]
    def file_format(version, file)
      # 優先順位
      # (1) version, fileが両方一致する結果にマッチ
      result = search(:files_information, version, :file_formats).find { _1[:file_name]==file }
  
      # (2) defaultの中でfileが一致する結果にマッチ
      result ||= search(:files_information, nil, :file_formats).find { _1[:file_name]==file }
  
      # (3) default_file_formatを取得
      result ||= search(:files_information, nil, :default_file_format)
      result
    end
  
    # @param [String] version
    # @return [Hash<Symbol,String>]
    def unihan_file_format(version=nil)
      search(:files_information, version, :unihan_file_format)
    end
  
    # @param [String] version
    # @param [String] property
    # @return [Hash<Symbol,Object>?]
    def miscellaneous_format(version, property)
      # 優先順位
      # (1) version, propertyが両方マッチ
      result = search(:properties_information, version, :miscellaneous_formats).find { _1[:property_name]==property }
  
      # (2) defaultのうち、propertyがマッチ
      result ||= search(:properties_information, nil, :miscellaneous_formats).find { _1[:property_name]==property }
      
      # (2)までにマッチする値が存在しない場合、nilをそのまま返す
      result
    end
  end
end