module UniProp
  RE_CODEPOINT = /[0-9A-F]{4,6}\.\.[0-9A-F]{4,6}|[0-9A-F]{4,6}/
  MIN_CODEPOINT = 0x0000
  MAX_CODEPOINT = 0x10ffff
  CODEPOINT_RANGE = MIN_CODEPOINT..MAX_CODEPOINT

  # プロパティの記述箇所を管理するためのStruct
  # @param [PropFile] propfile
  # @param [Integer] block
  # @param [Range<Integer>] range
  # @param [Integer] column
  Position = Struct.new(:propfile, :range, :block, :columns)

  # missingコメント1行を解析した結果を格納するためのStruct
  # @param [Range<Integer>] codepoint_range
  # @param [Property] property
  # @param [String] missing_value
  MissingDef = Struct.new(:codepoint_range, :property, :missing_value)

  # メタデータに記述された1つのブロックを管理するためのStruct
  # @note 主にメタデータの再作成時に使用。メタデータの内容をそのままStringで管理
  # @param [Array<String>/Array<Array<String>>] content
  # @param [String] range
  RawBlock = Struct.new(:content, :range)

  # メタデータに記述された1つのブロックを管理するためのStruct
  # @note 主にメタデータの利用時に使用。メタデータを解析した結果、適したオブジェクトで管理
  # @param [Array<Property?>/Array<Array<Property?>>] content
  # @param [Range<Integer>]
  Block = Struct.new(:content, :range)
end