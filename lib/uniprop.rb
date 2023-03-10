# frozen_string_literal: true

require_relative "uniprop/version"
require_relative "uniprop/inspects"
require_relative "uniprop/downloader"
require_relative "uniprop/propdata"
require_relative "uniprop/unicode_elements"
require_relative "uniprop/efficient_elements"
require_relative "uniprop/utils"
require_relative "uniprop/metadata_processor"
require_relative "uniprop/value_group"
require_relative "uniprop/metadata_generator"
require_relative "uniprop/metadata_validator"
require_relative "uniprop/unicode_manager"
require_relative "uniprop/unihanprop"
require_relative "uniprop/errors"
require_relative "uniprop/dsl"
require_relative "uniprop/unistring"
require_relative "uniprop/uniinteger"
require_relative "uniprop/consts"

module Uniprop
  class Error < StandardError; end
  # Your code goes here...
end
