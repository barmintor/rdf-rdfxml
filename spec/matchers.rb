require 'rspec/matchers'

RSpec::Matchers.define :have_xpath do |xpath, value, namespaces, trace|
  match do |actual|
    @doc = Nokogiri::XML.parse(actual)
    @doc.should be_a(Nokogiri::XML::Document)
    @doc.root.should be_a(Nokogiri::XML::Element)
    @namespaces = @doc.namespaces.inject({}) {|memo, (k,v)| memo[k.to_s.sub(/xmlns:?/, '')] = v; memo}.
      merge(namespaces).
      merge("xhtml" => "http://www.w3.org/1999/xhtml", "xml" => "http://www.w3.org/XML/1998/namespace")
    @result = @doc.root.at_xpath(xpath, @namespaces) rescue false
    case value
    when false
      @result.should be_nil
    when true
      @result.should_not be_nil
    when Array
      @result.to_s.split(" ").should include(*value)
    when Regexp
      @result.to_s.should =~ value
    else
      @result.to_s.should == value
    end
  end
  
  failure_message_for_should do |actual|
    msg = "expected to that #{xpath.inspect} would be #{value.inspect} in:\n" + actual.to_s
    msg += "was: #{@result}"
    msg +=  "\nDebug:#{trace.join("\n")}" if trace
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

Info = Struct.new(:about, :coment, :trace, :input, :result, :action, :expected)

RSpec::Matchers.define :be_equivalent_graph do |expected, info|
  match do |actual|
    @info = if info.respond_to?(:input)
      info
    elsif info.is_a?(Hash)
      identifier = info[:identifier] || expected.is_a?(RDF::Enumerable) ? expected.context : info[:about]
      trace = info[:trace]
      if trace.is_a?(Array)
        trace = if defined?(RUBY_ENGINE) && RUBY_ENGINE == "jruby" && RUBY_VERSION >= "1.9"
          trace.map {|s| s.dup.force_encoding(Encoding::UTF_8)}.join("\n")
        else
          trace.join("\n")
        end
      end
      Info.new(identifier, info[:comment] || "", trace)
    else
      Info.new(expected.is_a?(RDF::Enumerable) ? expected.context : info, info.to_s)
    end
    @expected = normalize(expected)
    @actual = normalize(actual)
    @actual.isomorphic_with?(@expected) rescue false
  end

  failure_message_for_should do |actual|
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
    "Unsorted Expected:\n#{@expected.dump(:ntriples, :standard_prefixes => true)}" +
    "Unsorted Results:\n#{@actual.dump(:ntriples, :standard_prefixes => true)}" +
    (@info.trace ? "\nDebug:\n#{@info.trace}" : "")
  end  
end

RSpec::Matchers.define :produce do |expected, info|
  match do |actual|
    actual.should == expected
  end
  
  failure_message_for_should do |actual|
    "Expected: #{[Array, Hash].include?(expected.class) ? expected.to_json(JSON_STATE) : expected.inspect}\n" +
    "Actual  : #{[Array, Hash].include?(actual.class) ? actual.to_json(JSON_STATE) : actual.inspect}\n" +
    #(expected.is_a?(Hash) && actual.is_a?(Hash) ? "Diff: #{expected.diff(actual).to_json(JSON_STATE)}\n" : "") +
    "Processing results:\n#{info.map {|s| s.force_encoding("utf-8")}.join("\n")}"
  end
end
