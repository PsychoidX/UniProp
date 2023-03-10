module UniPropDSLMethods
  def prop_data
    @@prop_data ||= UniProp::PropData.new(
      Pathname.new(__dir__) / "../resources/settings.rb",
      Pathname.new(__dir__) / "../resources/metadata.json"
    )
  end

  # @param [String] version_name
  # @return [VersionManager]
  def version(version_name)
    prop_data.version_manager(version_name)
  end

  # @return [UnicodeManager]
  def unicode_manager
    prop_data.unicode_manager
  end

  # 最新バージョンの名前を取得
  # @param [Boolean] update_metadata trueの場合、バージョン名を取得し、メタデータを更新する
  # @return [String]
  def latest_version(update_metadata: false)
    version_names = prop_data.metadata.version_names(update_metadata: update_metadata, confirm: update_metadata)
    
    version_names.sort_by { UniProp::Version.name_to_weight(_1) }.last
  end
end

module UniPropDSL
  extend UniPropDSLMethods
end

class Module
  alias_method :const_missing_orig, :const_missing
  def const_missing(const, *args, &block)
    # VersionManager
    if const =~ /^V([\d_]+)$/
      # A_B_C -> A.B.C
      version_nums = $1.split(/_/)
      version_nums[1] ||= "0"
      version_nums[2] ||= "0"
      version_name = version_nums.join(".")
      UniPropDSL::prop_data.version_manager(version_name)
    elsif const =~ /^V(\d+)_(\d+)_Update(\d+)$/
      # A_B_C -> A.B-UpdateC
      version_name = "#{$1}.#{$2}-Update#{$3}"
      UniPropDSL::prop_data.version_manager(version_name)
    
    # UnicodeManager
    elsif const =~ /UNICODE/
      UniPropDSL::prop_data.unicode_manager
    else
      const_missing_orig(const, *args, &block)
    end
  end
end
