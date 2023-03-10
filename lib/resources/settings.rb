DOWNLOADER_SETTINGS = {
  default: {
    cache_path: Pathname.new(__dir__) / "UCD",
    excluded_extensions: %w{zip gz Z pdf ps gif jpg C html},
    excluded_directories: %w{MAPPINGS PROGRAMS UCA cldr idna math reconstructed security vertical zipped charts ucdxml },
    excluded_files: [
      "Index",
      "CJKXREF",
      "StandardizedVariants",
      "TangutSources",
      "NushuSources",
      "USourceData",
      "NamedSequencesProv",
      "ReadMe",

      # files don't have property
      "NormalizationCorrections",
      "NamedSequences",
      "CJKRadicals",
      "NamesList",
      "emoji-variation-sequences",
      "EmojiSources",
    ],
    included_files: [
      "Unihan",
    ],
    unicode_beta: false,
  },

  # can override settings for each version if need
  # "15.0.0": {
  #     unicode_beta: true,
  # },
}

FILES_INFORMATION = {
  default: {
    property_aliases_file_name: "PropertyAliases",
    property_value_aliases_file_name: "PropertyValueAliases",

    default_file_format: {
      strip: "\s",
      split: ";",
    },

    file_formats: [
      {
          file_name: "NushuSources",
          strip: "",
          split: "\s",
      },
    ],

    unihan_file_format: {
      strip: "",
      split: "\s",
    }
  },

  "15.0.0": {
    file_formats: [
      {
          file_name: "NushuSources",
          strip: "",
          split: "\s",
      },
    ],

  }
}

PROPERTIES_INFORMATION = {
  default: {
    miscellaneous_formats: [
      {
        property_name: "Bidi_Mirroring_Glyph",
        format_type: "String"
      },
      {
        property_name: "Bidi_Paired_Bracket",
        format_type: "String"
      },
      {
        property_name: "Equivalent_Unified_Ideograph",
        format_type: "String"
      },
      {
        property_name: "Jamo_Short_Name",
        format_type: "Jamo_Short_Name"
      },
      {
        property_name: "Name",
        format_type: "Unique",
        unique_threshold: 0.9
      },
      {
        property_name: "Name_Alias",
        format_type: "Unique",
        unique_threshold: 0.9
      },
      {
        property_name: "Script_Extensions",
        format_type: "Script_Extensions"
      },
      {
        property_name: "Unicode_1_Name",
        format_type: "text"
      },
      {
        property_name: "ISO_Comment",
        format_type: "text"
      }
    ]
  },

  # "15.0.0": {
  #   miscellaneous_formats: [
  #   ]
  # }
}