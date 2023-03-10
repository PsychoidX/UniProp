module UniString
  class PropSearch
    attr_reader :codepoint

    # @param [Integer] codepoint
    def initialize(codepoint)
      @codepoint = codepoint
    end

    def method_missing(method, *args, &block)
      property = method.to_s
      version = args[0] || latest_version
      UniProp::version(version).values_of(property, codepoint)
    end
  end

  refine String do
    # @param [String] version
    # @param [String] property
    def prop_value(version, property)
      UniProp::version(version).values_of(property, ord)
    end

    def prop
      if size == 1
        @prop_search ||= PropSearch.new(ord)
      else
        raise(SizeError, "The size of String must be 1.")
      end
    end
  end

  class SizeError < StandardError; end 
end