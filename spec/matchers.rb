require 'rspec/matchers'

RSpec::Matchers.define :have_xpath do |path, value, namespaces, debug|
  match do |actual|
    root = RDF::RDFXML::Reader.new(actual).root
    return false unless root
    namespaces = root.namespaces.inject({}) {|memo, (k,v)| memo[k.to_s.sub(/xmlns:?/, '')] = v; memo}.
      merge(namespaces).
      merge("xhtml" => "http://www.w3.org/1999/xhtml", "xml" => "http://www.w3.org/XML/1998/namespace")
    @result = root.at_xpath(path, namespaces) rescue false
    case value
    when false
      @result.nil?
    when true
      !@result.nil?
    when Array
      @result.to_s.split(" ").include?(*value)
    when Regexp
      @result.to_s =~ value
    else
      @result.to_s == value
    end
  end

  failure_message do |actual|
    msg = "expected that #{path.inspect}\nwould be: #{value.inspect}"
    msg += "\n     was: #{@result}"
    msg += "\nsource:" + actual
    msg +=  "\nDebug:#{Array(debug).join("\n")}" if debug
    msg
  end

  failure_message_when_negated do |actual|
    msg = "expected that #{path.inspect}\nwould not be #{value.inspect}"
    msg += "\nsource:" + actual
    msg +=  "\nDebug:#{Array(debug).join("\n")}" if debug
    msg
  end
end

def normalize(graph)
  case graph
  when RDF::Enumerable then graph
  when IO, StringIO
    RDF::Repository.new.load(graph, :base_uri => @info.about)
  else
    # Figure out which parser to use
    g = RDF::Repository.new
    reader_class = RDF::Reader.for(detect_format(graph))
    reader_class.new(graph, :base_uri => @info.about).each {|s| g << s}
    g
  end
end

Info = Struct.new(:about, :coment, :debug, :input, :result, :action, :expected)

RSpec::Matchers.define :be_equivalent_graph do |expected, info|
  match do |actual|
    @info = if info.respond_to?(:input)
      info
    elsif info.is_a?(Hash)
      identifier = info[:identifier] || info[:about]
      debug = info[:debug]
      if debug.is_a?(Array)
        debug = if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby" && RUBY_VERSION >= "1.9"
          debug.map {|s| s.dup.force_encoding(Encoding::UTF_8)}.join("\n")
        else
          debug.join("\n")
        end
      end
      Info.new(identifier, info[:comment] || "", debug)
    else
      Info.new(expected.is_a?(RDF::Enumerable) ? expected.context : info, info.to_s)
    end
    @expected = normalize(expected)
    @actual = normalize(actual)
    @actual.isomorphic_with?(@expected) rescue false
  end

  failure_message do |actual|
    info = @info.respond_to?(:comment) ? @info.comment : @info.inspect
    if @expected.is_a?(RDF::Graph) && @actual.size != @expected.size
      "Graph entry count differs:\nexpected: #{@expected.size}\nactual:   #{@actual.size}"
    elsif @expected.is_a?(Array) && @actual.size != @expected.length
      "Graph entry count differs:\nexpected: #{@expected.length}\nactual:   #{@actual.size}"
    else
      "Graph differs"
    end +
    "\n#{info + "\n" unless info.empty?}" +
    (@info.action ? "Input file: #{@info.action}\n" : "") +
    (@info.result ? "Result file: #{@info.result}\n" : "") +
    "Unsorted Expected:\n#{@expected.dump(:ttl, :standard_prefixes => true)}" +
    "Unsorted Results:\n#{@actual.dump(:ttl, :standard_prefixes => true)}" +
    (@info.debug ? "\nDebug:\n#{Array(@info.debug).join("\n")}" : "")
  end  
end

RSpec::Matchers.define :produce do |expected, info|
  match do |actual|
    actual == expected
  end
  
  failure_message do |actual|
    "Expected: #{[Array, Hash].include?(expected.class) ? expected.to_json(JSON_STATE) : expected.inspect}\n" +
    "Actual  : #{[Array, Hash].include?(actual.class) ? actual.to_json(JSON_STATE) : actual.inspect}\n" +
    #(expected.is_a?(Hash) && actual.is_a?(Hash) ? "Diff: #{expected.diff(actual).to_json(JSON_STATE)}\n" : "") +
    "Processing results:\n#{info.map {|s| s.force_encoding("utf-8")}.join("\n")}"
  end
end
