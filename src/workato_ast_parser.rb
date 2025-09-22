#!/usr/bin/env ruby

require 'ripper'
require 'json'
require 'csv'
require 'optparse'

class WorkatoASTParser
  attr_reader :components, :relationships

  def initialize(connector_code)
    @source = connector_code
    @components = {}
    @relationships = []
    @current_context = []
    @ast = Ripper.sexp(connector_code)
  end

  def analyze
    return unless @ast
    
    # Parse the AST to find main sections
    parse_connector(@ast)
    
    # Analyze dependencies for each component
    @components.each do |name, component|
      analyze_dependencies(component)
    end
    
    # Build relationship map
    build_relationships
    
    @components
  end

  private

  def parse_connector(node, context = [])
    return unless node.is_a?(Array)
    
    case node[0]
    when :hash
      parse_hash(node, context)
    when :method_add_block
      parse_method_block(node, context)
    when :call
      parse_call(node, context)
    when :command_call
      parse_command_call(node, context)
    when :assoc_new
      parse_association(node, context)
    else
      # Recursively parse child nodes
      node.each do |child|
        parse_connector(child, context) if child.is_a?(Array)
      end
    end
  end

  def parse_hash(node, context)
    # Look for main sections like actions:, methods:, etc.
    node.each do |child|
      next unless child.is_a?(Array)
      
      if child[0] == :assoclist_from_args
        child.each do |assoc|
          next unless assoc.is_a?(Array) && assoc[0] == :assoc_new
          
          key = extract_symbol_or_string(assoc[1])
          next unless key
          
          case key
          when 'actions', 'triggers'
            parse_actions_or_triggers(assoc[2], key)
          when 'methods'
            parse_methods_section(assoc[2])
          when 'object_definitions'
            parse_object_definitions(assoc[2])
          when 'pick_lists'
            parse_picklists(assoc[2])
          when 'connection'
            parse_connection(assoc[2])
          when 'test'
            parse_test_connection(assoc[2])
          when 'webhooks', 'webhook_notifications'
            parse_webhooks(assoc[2], key)
          end
        end
      else
        parse_connector(child, context)
      end
    end
  end

  def parse_actions_or_triggers(node, type)
    return unless node
    
    extract_hash_items(node).each do |name, definition|
      @components[name] = {
        name: name,
        type: type.chomp('s'), # 'actions' -> 'action'
        code: extract_code_block(definition),
        dependencies: {
          methods: [],
          objects: [],
          picklists: [],
          connections: []
        },
        metadata: analyze_metadata(definition)
      }
    end
  end

  def parse_methods_section(node)
    return unless node
    
    extract_hash_items(node).each do |name, definition|
      @components[name] = {
        name: name,
        type: 'method',
        code: extract_code_block(definition),
        dependencies: {
          methods: [],
          objects: [],
          picklists: [],
          connections: []
        },
        metadata: analyze_metadata(definition)
      }
    end
  end

  def parse_object_definitions(node)
    return unless node
    
    extract_hash_items(node).each do |name, definition|
      @components[name] = {
        name: name,
        type: 'object_def',
        code: extract_code_block(definition),
        dependencies: {
          methods: [],
          objects: [],
          picklists: [],
          connections: []
        },
        metadata: analyze_metadata(definition)
      }
    end
  end

  def parse_picklists(node)
    return unless node
    
    extract_hash_items(node).each do |name, definition|
      @components[name] = {
        name: name,
        type: 'picklist',
        code: extract_code_block(definition),
        dependencies: {
          methods: [],
          objects: [],
          picklists: [],
          connections: []
        },
        metadata: analyze_metadata(definition)
      }
    end
  end

  def parse_connection(node)
    @components['connection'] = {
      name: 'connection',
      type: 'connection',
      code: extract_code_block(node),
      dependencies: {
        methods: [],
        objects: [],
        picklists: [],
        connections: []
      },
      metadata: analyze_metadata(node)
    }
  end

  def parse_test_connection(node)
    @components['test_connection'] = {
      name: 'test_connection',
      type: 'test',
      code: extract_code_block(node),
      dependencies: {
        methods: [],
        objects: [],
        picklists: [],
        connections: []
      },
      metadata: analyze_metadata(node)
    }
  end

  def parse_webhooks(node, type)
    return unless node
    
    extract_hash_items(node).each do |name, definition|
      @components[name] = {
        name: name,
        type: 'webhook',
        code: extract_code_block(definition),
        dependencies: {
          methods: [],
          objects: [],
          picklists: [],
          connections: []
        },
        metadata: analyze_metadata(definition)
      }
    end
  end

  def extract_hash_items(node)
    items = {}
    return items unless node
    
    find_all_associations(node).each do |assoc|
      key = extract_symbol_or_string(assoc[1])
      value = assoc[2]
      items[key] = value if key
    end
    
    items
  end

  def find_all_associations(node, associations = [])
    return associations unless node.is_a?(Array)
    
    if node[0] == :assoc_new
      associations << node
    else
      node.each do |child|
        find_all_associations(child, associations) if child.is_a?(Array)
      end
    end
    
    associations
  end

  def extract_symbol_or_string(node)
    return nil unless node.is_a?(Array)
    
    case node[0]
    when :@label
      node[1].chomp(':')
    when :symbol_literal
      extract_symbol_or_string(node[1])
    when :@ident
      node[1]
    when :string_literal
      extract_string_content(node)
    else
      nil
    end
  end

  def extract_string_content(node)
    return nil unless node.is_a?(Array)
    
    if node[0] == :string_content && node[1].is_a?(Array)
      if node[1][0] == :@tstring_content
        return node[1][1]
      end
    elsif node[0] == :string_literal
      return extract_string_content(node[1])
    end
    
    nil
  end

  def extract_code_block(node)
    # For simplicity, convert the AST back to a string representation
    # In a real implementation, you might want to keep the AST
    node.inspect
  end

  def analyze_dependencies(component)
    code = component[:code]
    
    # Extract method calls
    component[:dependencies][:methods] = extract_method_calls(code)
    
    # Extract object definition references
    component[:dependencies][:objects] = extract_object_refs(code)
    
    # Extract picklist references
    component[:dependencies][:picklists] = extract_picklist_refs(code)
    
    # Extract connection references
    component[:dependencies][:connections] = extract_connection_refs(code)
  end

  def extract_method_calls(code)
    methods = []
    
    # Pattern: call('method_name', ...) or call(:method_name, ...)
    methods.concat(code.scan(/call\(['":](\w+)/).flatten)
    
    # Pattern: execute('method_name')
    methods.concat(code.scan(/execute\(['"](\w+)/).flatten)
    
    # Pattern: invoke('method_name')
    methods.concat(code.scan(/invoke\(['"](\w+)/).flatten)
    
    methods.uniq
  end

  def extract_object_refs(code)
    objects = []
    
    # Pattern: object_definitions['name'] or object_definitions[:name]
    objects.concat(code.scan(/object_definitions\[['":](\w+)/).flatten)
    
    # Pattern: fields('object_name')
    objects.concat(code.scan(/fields\(['"](\w+)/).flatten)
    
    # Pattern: get_object_definition('name')
    objects.concat(code.scan(/get_object_definition\(['"](\w+)/).flatten)
    
    objects.uniq
  end

  def extract_picklist_refs(code)
    picklists = []
    
    # Pattern: pick_list: :name or pick_list: 'name'
    picklists.concat(code.scan(/pick_list[:\s]+['":](\w+)/).flatten)
    
    # Pattern: pick_lists['name']
    picklists.concat(code.scan(/pick_lists\[['"](\w+)/).flatten)
    
    picklists.uniq
  end

  def extract_connection_refs(code)
    connections = []
    
    # Pattern: connection['field']
    connections.concat(code.scan(/connection\[['"](\w+)/).flatten)
    
    # Pattern: connection.field
    connections.concat(code.scan(/connection\.(\w+)/).flatten)
    
    connections.uniq
  end

  def analyze_metadata(node)
    metadata = {
      calls_external_api: false,
      uses_cache: false,
      has_pagination: false,
      uses_streaming: false,
      error_handling: 'none',
      retry_logic: 'none'
    }
    
    code = node.inspect
    
    # API detection
    api_patterns = [
      /\b(get|post|put|patch|delete)\s*\(/,
      /\.request\(/,
      /https?:\/\//,
      /\.after_response/
    ]
    metadata[:calls_external_api] = api_patterns.any? { |p| code.match?(p) }
    
    # Cache detection
    cache_patterns = [
      /workato\.cache/,
      /lookup_table/,
      /get_cached/,
      /set_cached/
    ]
    metadata[:uses_cache] = cache_patterns.any? { |p| code.match?(p) }
    
    # Pagination detection
    pagination_patterns = [
      /next_page/,
      /page_size/,
      /limit/,
      /offset/,
      /cursor/,
      /has_more/
    ]
    metadata[:has_pagination] = pagination_patterns.any? { |p| code.match?(p) }
    
    # Streaming detection
    metadata[:uses_streaming] = code.match?(/stream|chunk/i)
    
    # Error handling
    if code.match?(/after_error_response|error_handler/)
      metadata[:error_handling] = 'custom'
    elsif code.match?(/rescue/)
      metadata[:error_handling] = 'rescue'
    elsif code.match?(/circuit_breaker/)
      metadata[:error_handling] = 'circuit_breaker'
    end
    
    # Retry logic
    if code.match?(/exponential_backoff/)
      metadata[:retry_logic] = 'exponential_backoff'
    elsif code.match?(/rate_limit/)
      metadata[:retry_logic] = 'rate_limit'
    elsif code.match?(/\bretry\b|max_retries/)
      metadata[:retry_logic] = 'retry'
    end
    
    metadata
  end

  def build_relationships
    @relationships = []
    
    @components.each do |source_name, source_comp|
      # Method call relationships
      source_comp[:dependencies][:methods].each do |target|
        if @components[target]
          @relationships << {
            source: source_name,
            target: target,
            type: "#{source_comp[:type]}_calls_#{@components[target][:type]}",
            edge_type: 'method_call'
          }
        end
      end
      
      # Object reference relationships
      source_comp[:dependencies][:objects].each do |target|
        if @components[target]
          @relationships << {
            source: source_name,
            target: target,
            type: "#{source_comp[:type]}_uses_object_def",
            edge_type: 'object_ref'
          }
        end
      end
      
      # Picklist reference relationships
      source_comp[:dependencies][:picklists].each do |target|
        if @components[target]
          @relationships << {
            source: source_name,
            target: target,
            type: "#{source_comp[:type]}_uses_picklist",
            edge_type: 'picklist_ref'
          }
        end
      end
      
      # Connection reference relationships
      source_comp[:dependencies][:connections].each do |field|
        @relationships << {
          source: source_name,
          target: "connection.#{field}",
          type: "#{source_comp[:type]}_uses_connection",
          edge_type: 'connection_ref'
        }
      end
    end
  end

  def export_csv(filename)
    CSV.open(filename, 'w') do |csv|
      csv << [
        'component', 'component_type', 'dep_methods', 'dep_objects',
        'dep_picklists', 'dep_connections', 'calls_external_api',
        'uses_cache', 'has_pagination', 'uses_streaming',
        'error_handling', 'retry_logic'
      ]
      
      @components.each do |name, comp|
        csv << [
          name,
          comp[:type],
          comp[:dependencies][:methods].join(';'),
          comp[:dependencies][:objects].join(';'),
          comp[:dependencies][:picklists].join(';'),
          comp[:dependencies][:connections].join(';'),
          comp[:metadata][:calls_external_api],
          comp[:metadata][:uses_cache],
          comp[:metadata][:has_pagination],
          comp[:metadata][:uses_streaming],
          comp[:metadata][:error_handling],
          comp[:metadata][:retry_logic]
        ]
      end
    end
  end

  def export_json(filename)
    analysis = {
      metadata: {
        analyzed_at: Time.now.iso8601,
        total_components: @components.size,
        component_types: @components.values.map { |c| c[:type] }.uniq.size
      },
      components: @components,
      relationships: @relationships,
      summary: generate_summary
    }
    
    File.write(filename, JSON.pretty_generate(analysis))
  end

  def generate_summary
    {
      component_counts: @components.values.group_by { |c| c[:type] }
                                           .transform_values(&:size),
      relationship_counts: @relationships.group_by { |r| r[:type] }
                                        .transform_values(&:size),
      api_components: @components.select { |_, c| c[:metadata][:calls_external_api] }
                                 .keys,
      cached_components: @components.select { |_, c| c[:metadata][:uses_cache] }
                                    .keys,
      complex_components: find_complex_components,
      circular_dependencies: find_circular_dependencies
    }
  end

  def find_complex_components(threshold = 5)
    @components.select do |_, comp|
      total_deps = comp[:dependencies].values.flatten.size
      total_deps > threshold
    end.keys
  end

  def find_circular_dependencies
    circular = []
    visited = Set.new
    
    @components.each do |name, _|
      next if visited.include?(name)
      
      path = []
      stack = [[name, []]]
      
      while stack.any?
        current, current_path = stack.pop
        
        if current_path.include?(current)
          # Found a cycle
          cycle_start = current_path.index(current)
          cycle = current_path[cycle_start..-1] + [current]
          circular << cycle unless circular.any? { |c| c.sort == cycle.sort }
          next
        end
        
        visited.add(current)
        new_path = current_path + [current]
        
        if @components[current]
          @components[current][:dependencies][:methods].each do |dep|
            stack.push([dep, new_path]) if @components[dep]
          end
        end
      end
    end
    
    circular
  end
end

# Command-line interface
if __FILE__ == $0
  options = {
    output_dir: 'analysis_output',
    format: 'both'
  }
  
  OptionParser.new do |opts|
    opts.banner = "Usage: ruby workato_ast_parser.rb [options] connector.rb"
    
    opts.on("-o", "--output DIR", "Output directory") do |dir|
      options[:output_dir] = dir
    end
    
    opts.on("-f", "--format FORMAT", "Output format (csv, json, both)") do |format|
      options[:format] = format
    end
    
    opts.on("-h", "--help", "Show this message") do
      puts opts
      exit
    end
  end.parse!
  
  if ARGV.empty?
    puts "Error: Please provide a connector file"
    puts "Usage: ruby workato_ast_parser.rb connector.rb"
    exit 1
  end
  
  connector_file = ARGV[0]
  
  unless File.exist?(connector_file)
    puts "Error: File not found: #{connector_file}"
    exit 1
  end
  
  # Create output directory
  FileUtils.mkdir_p(options[:output_dir])
  
  # Read and parse connector
  puts "Reading connector: #{connector_file}"
  connector_code = File.read(connector_file)
  
  puts "Parsing connector structure..."
  parser = WorkatoASTParser.new(connector_code)
  components = parser.analyze
  
  if components.nil? || components.empty?
    puts "Error: Failed to parse connector or no components found"
    exit 1
  end
  
  puts "Found #{components.size} components"
  
  # Export results
  base_name = File.basename(connector_file, '.rb')
  
  if options[:format] == 'csv' || options[:format] == 'both'
    csv_file = File.join(options[:output_dir], "#{base_name}_components.csv")
    parser.export_csv(csv_file)
    puts "Exported CSV: #{csv_file}"
  end
  
  if options[:format] == 'json' || options[:format] == 'both'
    json_file = File.join(options[:output_dir], "#{base_name}_analysis.json")
    parser.export_json(json_file)
    puts "Exported JSON: #{json_file}"
  end
  
  # Print summary
  summary = parser.generate_summary
  
  puts "\n" + "="*60
  puts "ANALYSIS SUMMARY"
  puts "="*60
  
  puts "\nComponent Types:"
  summary[:component_counts].each do |type, count|
    puts "  #{type}: #{count}"
  end
  
  puts "\nRelationship Types:"
  summary[:relationship_counts].each do |type, count|
    puts "  #{type}: #{count}"
  end
  
  puts "\nAPI Components: #{summary[:api_components].size}"
  puts "Cached Components: #{summary[:cached_components].size}"
  puts "Complex Components (>5 deps): #{summary[:complex_components].size}"
  
  if summary[:circular_dependencies].any?
    puts "\n⚠️  Circular Dependencies Found: #{summary[:circular_dependencies].size}"
    summary[:circular_dependencies].first(3).each_with_index do |cycle, i|
      puts "  #{i+1}. #{cycle.join(' -> ')}"
    end
  end
  
  puts "\n" + "="*60
end
