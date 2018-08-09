module AnyStyle
  class Document < Wapiti::Sequence
    class << self
      include PDFUtils

      def parse(string, delimiter: /\r?\n/, tagged: false)
        current_label = ''
        new(string.split(delimiter).map { |line|
          if tagged
            label, line = line.split(/\s*\| /, 2)
            current_label = label unless label.empty?
          end
          Wapiti::Token.new line, label: current_label.to_s
        })
      end

      def open(path, format: File.extname(path), tagged: false, layout: true, **opts)
        raise ArgumentError,
          "cannot open tainted path: '#{path}'" if path.tainted?
        raise ArgumentError,
          "document not found: '#{path}'" unless File.exist?(path)

        path = File.absolute_path(path)

        case format.downcase
        when '.pdf'
          meta = pdf_meta path if opts[:parse_meta]
          info = pdf_info path if opts[:parse_info]
          input = pdf_to_text path, layout: layout
        when '.ttx'
          tagged = true
          input = File.read(path, encoding: 'utf-8')
        when '.txt'
          input = File.read(path, encoding: 'utf-8')
        end

        doc = parse input, tagged: tagged
        doc.path = path
        doc.meta = meta
        doc.info = info
        doc
      end
    end

    include StringUtils

    attr_accessor :meta, :info, :path, :pages, :tokens
    alias_method :lines, :tokens

    def pages
      @pages ||= Page.parse(lines)
    end

    def each
      if block_given?
        pages.each.with_index do |page, pn|
          page.lines.each.with_index do |line, ln|
            yield line, ln, page, pn
          end
        end
        self
      else
        to_enum
      end
    end

    def each_section
      if block_given?
        current = []
        lines.each do |ln|
          case ln.label
          when 'title'
            unless current.empty?
              yield current
              current = []
            end
          when 'ref', 'text'
            current << ln
          else
            # ignore
          end
        end
        unless current.empty?
          yield current
        end
        self
      else
        to_enum
      end
    end

    def label(other)
      doc = dup
      doc.tokens = lines.map.with_index { |line, idx|
        Wapiti::Token.new line.value,
          label: other[idx].label.to_s,
          observations: other[idx].observations.dup
      }
      doc
    end

    def to_s(delimiter: "\n", encode: false, tagged: false, **opts)
      if tagged
        prev_label = nil
        lines.map { |ln|
          label = (ln.label == prev_label) ? '' : ln.label
          prev_label = ln.label
          '%.14s| %s' % ["#{label}              ", ln.value]
        }.join(delimiter)
      else
        super(delimiter: delimiter, encode: encode, tagged: tagged, expanded: false, **opts)
      end
    end

    def to_a(encode: true, **opts)
      super(encode: encode, **opts)
    end

    def to_h(**opts)
      {
        info: info,
        meta: meta,
        sections: sections(**opts),
        title: title(**opts),
        references: references(**opts)
      }
    end

    def references(**opts)
      Refs.parse(lines).to_a
    end

    def sections(delimiter: "\n", **opts)
      []
    end

    def title(delimiter: " ", **opts)
      lines.drop_while { |ln|
        ln.label != 'title'
      }.take_while { |ln|
        ln.label == 'title'
      }.map(&:value).join(delimiter)
    end

    def inspect
      "#<AnyStyle::Document lines={#{size}}>"
    end
  end
end
