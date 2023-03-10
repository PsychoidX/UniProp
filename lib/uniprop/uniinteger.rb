module UniInteger
  refine Integer do
    # selfをU+xxxx形式の文字列に変換
    def to_cp
      "U+%04X" % self
    end
  end

  refine Range do
    def to_cp
      if first.class==Integer && last.class==Integer
        "#{"U+%04X" % first}..#{"%04X" % last}"
      end
    end
  end
end