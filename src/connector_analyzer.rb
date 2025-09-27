# frozen_string_literal: true
#
# connector_analyzer.rb
#
# Parses a Workato-style Ruby connector, builds an IR + call-graph, surfaces issues,
# and emits a "clean" IR (ir_clean.json) in a curated rendering style.
#
# Usage:
#   ruby connector_analyzer.rb path/to/connector.rb [-o out_dir]
#
# Outputs (default out_dir: ./out):
#   out/ir.json
#   out/call_graph.json
#   out/issues.json
#   out/ir_clean.json
#
require 'json'
require 'optparse'
require 'fileutils'
require 'set'
require 'shellwords'

# -------------------------------
# Preprocessing
# -------------------------------
module Preprocess
  module_function

  # Strip single-line (# ...) comments outside strings, preserving length.
  def strip_line_comments_preserve_length(src)
    out = src.dup
    i = 0
    n = src.length
    in_s = false
    in_d = false
    escaped = false
    while i < n
      ch = src[i]

      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        case ch
        when "'"
          in_s = true
          i += 1
          next
        when '"'
          in_d = true
          i += 1
          next
        when '#'
          j = i
          j += 1 while j < n && src[j] != "\n"
          (i...j).each { |k| out[k] = ' ' }
          i = j
          next
        else
          i += 1
        end
      end
    end
    out
  end

  # Strip block comments (=begin ... =end) preserving length.
  def strip_block_comments_preserve_length(src)
    out = src.dup
    loop do
      m = out.match(/^[ \t]*=begin.*?\n.*?^[ \t]*=end[ \t]*\n?/m)
      break unless m
      (m.begin(0)...m.end(0)).each { |k| out[k] = ' ' }
    end
    out
  end

  def sanitize(src)
    s = strip_line_comments_preserve_length(src)
    strip_block_comments_preserve_length(s)
  end
end

# -------------------------------
# Balancers
# -------------------------------
module Balance
  module_function

  def extract_curly_block(src, start_idx)
    raise "Expected '{' at #{start_idx}" unless src[start_idx] == '{'
    i = start_idx
    depth = 0
    in_s = false
    in_d = false
    escaped = false
    while i < src.length
      ch = src[i]

      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        case ch
        when "'"
          in_s = true
        when '"'
          in_d = true
        when '{'
          depth += 1
        when '}'
          depth -= 1
          return src[start_idx..i] if depth == 0
        end
      end
      i += 1
    end
    raise "Unbalanced '{' starting at #{start_idx}"
  end

  def extract_square_block(src, start_idx)
    raise "Expected '[' at #{start_idx}" unless src[start_idx] == '['
    i = start_idx
    depth = 0
    in_s = false
    in_d = false
    escaped = false
    while i < src.length
      ch = src[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        case ch
        when "'"
          in_s = true
        when '"'
          in_d = true
        when '['
          depth += 1
        when ']'
          depth -= 1
          return src[start_idx..i] if depth == 0
        end
      end
      i += 1
    end
    raise "Unbalanced '[' starting at #{start_idx}"
  end

  def extract_lambda_block(src, start_idx)
    raise "Expected 'lambda' at #{start_idx}" unless src[start_idx, 6] == 'lambda'
    i = start_idx + 6
    i += 1 while i < src.length && src[i] =~ /\s/
    if src[i, 2] == 'do'
      return extract_do_end(src, start_idx)
    elsif src[i] == '{'
      block = extract_curly_block(src, i)
      return src[start_idx...(i)] + block
    else
      j = i
      j += 1 while j < src.length && src[j] != ',' && src[j] != "\n"
      return src[start_idx...j]
    end
  end

  def extract_do_end(src, start_idx)
    i = start_idx
    in_s = false
    in_d = false
    escaped = false
    depth = 0
    while i < src.length
      ch = src[i]
      if in_s
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == "'" && !escaped
          in_s = false
        else
          escaped = false
        end
        i += 1
        next
      elsif in_d
        if ch == "\\" && !escaped
          escaped = true
        elsif ch == '"' && !escaped
          in_d = false
        else
          escaped = false
        end
        i += 1
        next
      else
        if ch == "'"
          in_s = true
          i += 1
          next
        elsif ch == '"'
          in_d = true
          i += 1
          next
        end
        if src[i..] =~ /\Ado\b/
          depth += 1
          i += 2
          next
        elsif src[i..] =~ /\Aend\b/
          depth -= 1
          i += 3
          return src[start_idx...i] if depth <= 0
          next
        else
          i += 1
        end
      end
    end
    raise "Unbalanced lambda do..end starting at #{start_idx}"
  end
end

# -------------------------------
# Section extractors
# -------------------------------
module Extractor
  module_function

  def extract_top_hash_section(src, key)
    idx = 0
    in_s = false
    in_d = false
    depth = 0
    while idx < src.length
      ch = src[idx]
      if in_s
        in_s = false if ch == "'" && src[idx-1] != "\\"
        idx += 1
        next
      elsif in_d
        in_d = false if ch == '"' && src[idx-1] != "\\"
        idx += 1
        next
      else
        case ch
        when "'"; in_s = true
        when '"'; in_d = true
        when '{'; depth += 1
        when '}'; depth -= 1 if depth > 0
        end

        if depth == 1
          if src[idx..] =~ /\A#{Regexp.escape(key)}\s*:\s*\{/
            m = Regexp.last_match
            start_brace = idx + m[0].rindex('{')
            begin
              return Balance.extract_curly_block(src, start_brace)
            rescue
              if (m2 = src.match(/#{Regexp.escape(key)}\s*:\s*\{/, idx))
                start2 = m2.end(0) - 1
                return Balance.extract_curly_block(src, start2)
              else
                raise
              end
            end
          end
        end
        idx += 1
      end
    end

    if (m3 = src.match(/#{Regexp.escape(key)}\s*:\s*\{/))
      start3 = m3.end(0) - 1
      return Balance.extract_curly_block(src, start3)
    end
    nil
  end

  def extract_named_curly_pairs(block_str)
    inner = block_str.strip
    inner = inner[1..-2] if inner.start_with?('{') && inner.end_with?('}')
    pairs = {}
    i = 0
    in_s = false
    in_d = false
    while i < inner.length
      ch = inner[i]
      if in_s
        in_s = false if ch == "'" && inner[i-1] != "\\"
        i += 1
        next
      elsif in_d
        in_d = false if ch == '"' && inner[i-1] != "\\"
        i += 1
        next
      else
        if ch == "'"; in_s = true; i += 1; next; end
        if ch == '"'; in_d = true; i += 1; next; end

        if inner[i..] =~ /\A([a-zA-Z_]\w*)\s*:\s*\{/
          m = Regexp.last_match
          name = m[1]
          start_brace = i + m[0].rindex('{')
          block = Balance.extract_curly_block(inner, start_brace)
          pairs[name] = block
          i = start_brace + block.length
          i += 1 while i < inner.length && inner[i] =~ /[\s,]/
          next
        end
        i += 1
      end
    end
    pairs
  end

  def extract_named_lambda_pairs(block_str)
    inner = block_str.strip
    inner = inner[1..-2] if inner.start_with?('{') && inner.end_with?('}')
    pairs = {}
    i = 0
    in_s = false
    in_d = false
    while i < inner.length
      ch = inner[i]
      if in_s
        in_s = false if ch == "'" && inner[i-1] != "\\"
        i += 1
        next
      elsif in_d
        in_d = false if ch == '"' && inner[i-1] != "\\"
        i += 1
        next
      else
        if ch == "'"; in_s = true; i += 1; next; end
        if ch == '"'; in_d = true; i += 1; next; end

        if inner[i..] =~ /\A([a-zA-Z_]\w*[!?]?)\s*:\s*lambda\b/
          m = Regexp.last_match
          name = m[1]
          lambda_start = i + m[0].index('lambda')
          block = Balance.extract_lambda_block(inner, lambda_start)
          pairs[name] = block
          i = lambda_start + block.length
          i += 1 while i < inner.length && inner[i] =~ /[\s,]/
          next
        end
        i += 1
      end
    end
    pairs
  end

  def extract_action_parts(action_block)
    parts = {}
    %w[input_fields execute output_fields sample_output help description subtitle title].each do |k|
      if action_block =~ /#{k}\s*:\s*lambda\b/
        start = Regexp.last_match.begin(0)
        lambda_pos = action_block.index('lambda', start)
        lb = Balance.extract_lambda_block(action_block, lambda_pos)
        parts[k] = lb
      end
    end
    parts['picklists'] = action_block.scan(/pick_list:\s*:(\w+)/).flatten.uniq
    parts
  end
end

# -------------------------------
# Semantics extractors
# -------------------------------
module Semantics
  module_function

  def find_calls(body)
    body.to_s.scan(/call\(\s*['"]([^'"]+)['"]/).flatten.uniq
  end

  def find_direct_http(body)
    hits = []
    body.to_s.scan(/\b(post|get|put|delete)\s*\(/i) { |m| hits << m[0].downcase }
    hits.uniq
  end

  def find_object_def_refs(body)
    refs = body.to_s.scan(/object_definitions\[['"]([^'"]+)['"]\]/).flatten
    refs += body.to_s.scan(/object_definitions\[['"]([^'"]+)['"]\]\.only\(/).flatten
    refs.uniq
  end

  def find_picklists(body)
    body.to_s.scan(/pick_list:\s*:(\w+)/).flatten.uniq
  end

  def lambda_params(body)
    if body =~ /lambda\s*(do|\{)\s*\|([^|]*)\|/
      Regexp.last_match(2).split(',').map(&:strip)
    else
      []
    end
  end

  # --- Parse run_vertex kwargs so the cleaner can surface them.
  def run_vertex_template_symbol(body)
    m = body.to_s.match(/call\(\s*['"]run_vertex['"][^)]*?,\s*:[\s]*([a-zA-Z_]\w*)/)
    m && m[1]
  end

  def find_kwarg(body, key)
    return Regexp.last_match(1) if body.to_s =~ /#{key}\s*:\s*['"]([^'"]+)['"]/
    return Regexp.last_match(1) if body.to_s =~ /#{key}\s*:\s*:(\w+)/
    nil
  end

  def run_vertex_kwargs(body)
    {
      'template' => run_vertex_template_symbol(body),
      'verb'     => find_kwarg(body, 'verb'),
      'extract'  => find_kwarg(body, 'extract')
    }
  end
end

# -------------------------------
# Analyzer
# -------------------------------
class ConnectorAnalyzer
  attr_reader :src, :ir, :graph, :issues

  def initialize(src)
    @src_raw = src
    @src = Preprocess.sanitize(src)
    @ir = {
      'connector' => {},
      'actions' => [],
      'methods' => [],
      'object_definitions' => [],
      'pick_lists' => []
    }
    @graph = {
      'nodes' => [],
      'edges' => [],
      'paths' => {}
    }
    @issues = []
  end

  def analyze!
    parse_topmeta
    parse_sections
    post_process
    self
  end

  def parse_topmeta
    if (m = @src.match(/title\s*:\s*['"]([^'"]+)['"]/))
      @ir['connector']['title'] = m[1]
    end
    auth_modes = []
    auth_modes << 'oauth2' if @src.include?('authorization:') && @src.include?('oauth2:')
    auth_modes << 'custom' if @src.include?('custom_auth')
    @ir['connector']['auth_modes'] = auth_modes.uniq
  end

  def parse_sections
    actions_block  = Extractor.extract_top_hash_section(@src, 'actions')
    methods_block  = Extractor.extract_top_hash_section(@src, 'methods')
    objdefs_block  = Extractor.extract_top_hash_section(@src, 'object_definitions')
    picklists_block= Extractor.extract_top_hash_section(@src, 'pick_lists')
    test_block     = @src[/\btest\s*:\s*lambda\b.+/m]

    parse_actions(actions_block) if actions_block
    parse_methods(methods_block) if methods_block
    parse_object_definitions(objdefs_block) if objdefs_block
    parse_picklists(picklists_block) if picklists_block
    parse_top_test(test_block) if test_block
  end

  def parse_actions(block)
    pairs = Extractor.extract_named_curly_pairs(block)
    pairs.each do |action_name, action_block|
      parts = Extractor.extract_action_parts(action_block)
      execute_body = parts['execute'] || ''
      input_body   = parts['input_fields'] || ''
      output_body  = parts['output_fields'] || ''

      action = {
        'name' => action_name,
        'picklists_used' => (parts['picklists'] || []),
        'input_object_defs' => Semantics.find_object_def_refs(input_body),
        'output_object_defs' => Semantics.find_object_def_refs(output_body),
        'execute' => {
          'lambda_params'  => Semantics.lambda_params(execute_body),
          'calls'          => Semantics.find_calls(execute_body),
          'direct_http'    => Semantics.find_direct_http(execute_body),
          'template_symbol'=> Semantics.run_vertex_template_symbol(execute_body),
          'kwargs'         => Semantics.run_vertex_kwargs(execute_body)  # <— NEW
        }
      }

      @ir['actions'] << action

      entry = "execute:#{action_name}"
      add_node(entry)
      action['execute']['calls'].each { |callee| add_edge(entry, callee) }
      action['execute']['direct_http'].each { |verb| add_edge(entry, "HTTP:#{verb.upcase}") }

      if action_name =~ /image/i
        ts = action['execute']['template_symbol']
        if ts && ts != 'analyze_image'
          @issues << {
            'severity' => 'warning',
            'category' => 'template_mismatch',
            'message'  => "Action '#{action_name}' uses template :#{ts}. Did you mean :analyze_image?",
            'where'    => "actions.#{action_name}.execute"
          }
        end
      end
    end
  end

  def parse_methods(block)
    pairs = Extractor.extract_named_lambda_pairs(block)
    pairs.each do |method_name, lambda_body|
      calls = Semantics.find_calls(lambda_body)
      direct_http = Semantics.find_direct_http(lambda_body)
      m = {
        'name' => method_name,
        'lambda_params' => Semantics.lambda_params(lambda_body),
        'calls' => calls,
        'direct_http' => direct_http
      }
      @ir['methods'] << m
      add_node(method_name)
      calls.each { |callee| add_edge(method_name, callee) }
      direct_http.each { |verb| add_edge(method_name, "HTTP:#{verb.upcase}") }
    end
  end

  def parse_object_definitions(block)
    pairs = Extractor.extract_named_curly_pairs(block)
    pairs.each do |name, od_block|
      picklists = Semantics.find_picklists(od_block)
      refs = Semantics.find_object_def_refs(od_block)
      @ir['object_definitions'] << {
        'name' => name,
        'picklists_used' => picklists,
        'object_defs_referenced' => refs
      }
    end
  end

  def parse_picklists(block)
    pairs = Extractor.extract_named_lambda_pairs(block)
    pairs.each do |name, _lb|
      @ir['pick_lists'] << { 'name' => name }
    end
  end

  def parse_top_test(test_blob)
    if test_blob && (idx = test_blob.index('lambda'))
      lb = Balance.extract_lambda_block(test_blob, idx)
      calls = Semantics.find_calls(lb)
      entry = 'top:test'
      add_node(entry)
      calls.each { |c| add_edge(entry, c) }
    end
  end

  def add_node(n)
    @graph['nodes'] << n unless @graph['nodes'].include?(n)
  end

  def add_edge(from, to)
    add_node(from); add_node(to)
    @graph['edges'] << { 'from' => from, 'to' => to }
  end

  def post_process
    defined_methods = @ir['methods'].map { |m| m['name'] }.to_set

    all_calls = []
    @ir['methods'].each { |m| all_calls.concat(m['calls']) }
    @ir['actions'].each { |a| all_calls.concat(a.dig('execute','calls') || []) }
    all_calls.uniq!
    (all_calls - defined_methods.to_a).each do |undef_name|
      next if undef_name.start_with?('HTTP:')
      @issues << {
        'severity' => 'info',
        'category' => 'undefined_method_reference',
        'message'  => "Method '#{undef_name}' is called but not defined under methods:",
        'where'    => 'global'
      }
    end

    reachable = compute_reachable_from_entries
    (@ir['methods'].map { |m| m['name'] } - reachable.to_a).each do |unused|
      @issues << {
        'severity' => 'info',
        'category' => 'unused_method',
        'message'  => "Method '#{unused}' is not reachable from any action/test entrypoints",
        'where'    => 'methods'
      }
    end

    (@ir['methods'] + @ir['actions'].map{|a| {'name'=>"execute:#{a['name']}", 'direct_http'=>a.dig('execute','direct_http')}}).each do |m|
      next unless m['direct_http'] && !m['direct_http'].empty?
      @issues << {
        'severity' => 'warning',
        'category' => 'direct_http',
        'message'  => "Direct HTTP calls detected in '#{m['name']}' (#{m['direct_http'].uniq.join(', ')}). Prefer unified api_request wrapper.",
        'where'    => "methods.#{m['name']}"
      }
    end

    defined_pl = @ir['pick_lists'].map{|p| p['name']}.to_set
    used_pl = []
    @ir['actions'].each { |a| used_pl.concat(a['picklists_used']) }
    @ir['object_definitions'].each { |o| used_pl.concat(o['picklists_used']) }
    (used_pl.uniq - defined_pl.to_a).each do |pl|
      @issues << {
        'severity' => 'info',
        'category' => 'missing_picklist',
        'message'  => "pick_list :#{pl} is referenced but not defined in pick_lists",
        'where'    => 'object_definitions/actions'
      }
    end

    build_call_paths!
  end

  def compute_reachable_from_entries
    adj = {}
    @graph['edges'].each do |e|
      (adj[e['from']] ||= []) << e['to']
    end
    entries = (@ir['actions'].map { |a| "execute:#{a['name']}" } + ['top:test']).select { |n| @graph['nodes'].include?(n) }
    seen = Set.new
    stack = entries.dup
    while (n = stack.pop)
      next if seen.include?(n)
      seen << n
      (adj[n] || []).each { |m| stack << m }
    end
    Set.new(seen.select { |n| @ir['methods'].any? { |m| m['name'] == n } })
  end

  def build_call_paths!
    adj = Hash.new { |h,k| h[k] = [] }
    @graph['edges'].each { |e| adj[e['from']] << e['to'] }

    entries = @ir['actions'].map { |a| "execute:#{a['name']}" }.select { |n| @graph['nodes'].include?(n) }

    entries.each do |entry|
      paths = []
      dfs_paths(entry, adj, [], Set.new, paths, 0, 60)
      @graph['paths'][entry.sub('execute:', '')] = paths
    end
  end

  def dfs_paths(node, adj, cur, seen, paths, depth, limit)
    return if depth > limit
    cur << node
    if (adj[node] || []).empty? || seen.include?(node)
      paths << cur.dup
      cur.pop
      return
    end
    seen.add(node)
    adj[node].each do |nxt|
      dfs_paths(nxt, adj, cur, seen, paths, depth+1, limit)
    end
    seen.delete(node)
    cur.pop
  end
end

# -------------------------------
# IR Cleaner / Renderer
# -------------------------------
module IRClean
  module_function

  def build(ir, graph, issues)
    clean = {}
    clean['connector'] = ir['connector']

    # Indexes
    obj_by_name = {}
    ir['object_definitions'].each { |o| obj_by_name[o['name']] = o }
    methods_by_name = {}
    ir['methods'].each { |m| methods_by_name[m['name']] = m }

    # Object usage (used_by_objects)
    used_by_objects = Hash.new { |h,k| h[k] = Set.new }
    ir['object_definitions'].each do |o|
      (o['object_defs_referenced'] || []).each { |ref| used_by_objects[ref] << o['name'] }
    end

    # Helper: collect picklists transitively from an object closure
    collect_pl = lambda do |start_objs|
      pl = Set.new
      seen = Set.new
      q = (start_objs || []).dup
      while (name = q.shift)
        next if name.nil? || name.empty?
        next if seen.include?(name)
        seen << name
        od = obj_by_name[name]
        next unless od
        (od['picklists_used'] || []).each { |p| pl << p }
        (od['object_defs_referenced'] || []).each { |ref| q << ref }
      end
      pl
    end

    # Action notes from issues
    issues_by_action = Hash.new { |h,k| h[k] = [] }
    issues.each do |iss|
      if iss['where'] && iss['where'].start_with?('actions.')
        act = iss['where'].split('.')[1]
        issues_by_action[act] << iss['message']
      end
    end

    # Build cleaned actions
    clean['actions'] = ir['actions'].map do |a|
      # primary method guess
      primary = pick_primary_method(a)

      # params from kwargs (template/verb/extract)
      kwargs = (a.dig('execute', 'kwargs') || {})
      params = {}
      params['template'] = kwargs['template'] || a.dig('execute','template_symbol')
      params['verb']     = kwargs['verb'] if kwargs['verb']
      params['extract']  = kwargs['extract'] if kwargs['extract']

      # transitive call paths → "A → B → C"
      paths = (graph['paths'][a['name']] || []).map do |p|
        p.reject { |n| n.start_with?('execute:') }.join(' → ')
      end.uniq

      # aggregate picklists (action-level + object closures)
      agg_pl = Set.new
      (a['picklists_used'] || []).each { |p| agg_pl << p }
      agg_pl.merge(collect_pl.call(a['input_object_defs']).to_a)
      agg_pl.merge(collect_pl.call(a['output_object_defs']).to_a)

      out = {
        'name' => a['name'],
        'input_object_defs'  => a['input_object_defs'],
        'output_object_defs' => a['output_object_defs'],
        'execute' => {
          'method' => primary,
          'params' => params.empty? ? nil : params,
          'transitive_calls' => paths
        }.compact,
        'picklists_used' => agg_pl.to_a.sort
      }

      if (notes = issues_by_action[a['name']]).any?
        # Put the first note inline; keep all in an array as well.
        out['note'] = notes.first
        out['notes'] = notes
      end

      out
    end

    # methods (lean view)
    clean['methods'] = ir['methods'].map { |m| { 'name' => m['name'], 'calls' => (m['calls'] || []) } }

    # object definitions usage
    clean['object_definitions'] = ir['object_definitions'].map do |o|
      {
        'name' => o['name'],
        'used_by_actions' => ir['actions'].select { |a|
          (a['input_object_defs'] || []).include?(o['name']) ||
          (a['output_object_defs'] || []).include?(o['name'])
        }.map { |a| a['name'] }.sort,
        'used_by_objects' => used_by_objects[o['name']].to_a.sort
      }
    end

    # pick list usage
    pl_names = ir['pick_lists'].map { |p| p['name'] }
    used_by_objects_pl = Hash.new { |h,k| h[k] = Set.new }
    ir['object_definitions'].each do |o|
      (o['picklists_used'] || []).each { |pl| used_by_objects_pl[pl] << o['name'] }
    end

    # For actions, use cleaned aggregation above
    used_by_actions_pl = Hash.new { |h,k| h[k] = Set.new }
    clean['actions'].each do |a|
      (a['picklists_used'] || []).each { |pl| used_by_actions_pl[pl] << a['name'] }
    end

    clean['pick_lists'] = pl_names.map do |pl|
      {
        'name' => pl,
        'used_by_objects' => used_by_objects_pl[pl].to_a.sort,
        'used_by_actions' => used_by_actions_pl[pl].to_a.sort
      }
    end

    clean
  end

  def pick_primary_method(action)
    calls = action.dig('execute','calls') || []
    return 'run_vertex'                     if calls.include?('run_vertex')
    return 'generate_embeddings_batch_exec' if calls.include?('generate_embeddings_batch_exec')
    return 'generate_embedding_single_exec' if calls.include?('generate_embedding_single_exec')
    return 'api_request'                    if calls.include?('api_request')
    dh = action.dig('execute','direct_http') || []
    return "HTTP:#{dh.first&.upcase}"       if !dh.empty?
    calls.first || 'execute'
  end
end

# -------------------------------
# Metrics / Visibility
# -------------------------------
module Metrics
  module_function

  def build(ir, graph, issues)
    nodes = graph['nodes']
    edges = graph['edges']

    adj = Hash.new { |h,k| h[k] = [] }
    radj = Hash.new { |h,k| h[k] = [] }
    edges.each { |e| adj[e['from']] << e['to']; radj[e['to']] << e['from'] }

    # fan-in/out
    fan_in  = Hash.new(0)
    fan_out = Hash.new(0)
    nodes.each { |n| fan_out[n] = adj[n].size; fan_in[n] = radj[n].size }

    # undefined + unused from issues
    undef_set = issues.select { |i| i['category'] == 'undefined_method_reference' }
                      .flat_map { |i| i.fetch('message','').scan(/'(.*?)'/).flatten }
                      .to_set
    unused_set = issues.select { |i| i['category'] == 'unused_method' }
                       .flat_map { |i| i.fetch('message','').scan(/'(.*?)'/).flatten }
                       .to_set

    # SCCs / cycles
    sccs = tarjan_scc(nodes, adj)
    cyc_nodes = sccs.select { |c| c.size > 1 }.flatten.to_set
    # self-loops also count as cycle
    nodes.each { |n| cyc_nodes << n if adj[n].include?(n) }

    # classify node kinds
    kind = {}
    nodes.each do |n|
      kind[n] =
        if n.start_with?('execute:')
          'action'
        elsif n.start_with?('HTTP:')
          'http'
        else
          'method'
        end
    end

    # hotspots = top 10 by max(fan-in, fan-out)
    scores = nodes.map { |n| [n, [fan_in[n], fan_out[n]].max] }
    cutoff = scores.map(&:last).sort.last(10).first || 0
    hot = scores.select { |_, s| s >= cutoff && s > 0 }.map(&:first).to_set

    # per-action complexity from precomputed paths
    per_action = {}
    (graph['paths'] || {}).each do |act, paths|
      act_nodes = Set.new
      act_edges = Set.new
      paths.each do |p|
        p.each_with_index do |v, i|
          act_nodes << v
          if i < p.size - 1
            act_edges << [p[i], p[i+1]]
          end
        end
      end

      # basic depth approximation = longest path length - 1
      max_depth = paths.map { |p| p.size - 1 }.max || 0
      http_cnt  = act_nodes.count { |n| n.start_with?('HTTP:') }

      per_action[act] = {
        'nodes'      => act_nodes.size,
        'edges'      => act_edges.size,
        'max_depth'  => max_depth,
        'paths'      => paths.size,
        'http_nodes' => http_cnt
      }
    end

    {
      'fan_in'   => fan_in,
      'fan_out'  => fan_out,
      'kind'     => kind,
      'hot'      => hot.to_a,
      'cycle'    => cyc_nodes.to_a,
      'undefined'=> undef_set.to_a,
      'unused'   => unused_set.to_a,
      'per_action' => per_action
    }
  end

  # Tarjan SCC
  def tarjan_scc(nodes, adj)
    index = 0
    stack = []
    onstack = {}
    idx = {}
    low = {}
    sccs = []

    strongconnect = lambda do |v|
      idx[v] = index
      low[v] = index
      index += 1
      stack << v
      onstack[v] = true

      (adj[v] || []).each do |w|
        if !idx.key?(w)
          strongconnect.call(w)
          low[v] = [low[v], low[w]].min
        elsif onstack[w]
          low[v] = [low[v], idx[w]].min
        end
      end

      if low[v] == idx[v]
        comp = []
        begin
          w = stack.pop
          onstack[w] = false
          comp << w
        end until w == v
        sccs << comp
      end
    end

    nodes.each { |v| strongconnect.call(v) unless idx.key?(v) }
    sccs
  end
end

# -------------------------------
# Visualization (Mermaid + optional Graphviz)
# -------------------------------
module Viz
  module_function

  def slug(s)
    s.to_s.gsub(/[^A-Za-z0-9_]/, '_')
  end

  def build_node_classes(graph, metrics)
    hot   = metrics['hot'].to_set
    cycle = metrics['cycle'].to_set
    undefd= metrics['undefined'].to_set
    unused= metrics['unused'].to_set
    classes = Hash.new { |h,k| h[k] = [] }
    graph['nodes'].each do |n|
      classes[n] << 'hot'   if hot.include?(n)
      classes[n] << 'cycle' if cycle.include?(n)
      classes[n] << 'undef' if undefd.include?(n)
      classes[n] << 'unused' if unused.include?(n)
    end
    classes
  end

  def mermaid_graph(ir, graph, node_classes = {})
    lines = []
    lines << "flowchart TD"

    graph['nodes'].each do |n|
      id = slug(n)
      label = n.gsub('"', '\"')
      shape =
        if n.start_with?('execute:') then "([#{label}])"
        elsif n.start_with?('HTTP:') then "{{#{label}}}"
        else "[#{label}]"
        end
      lines << "  #{id}#{shape}"
    end

    graph['edges'].each do |e|
      lines << "  #{slug(e['from'])} --> #{slug(e['to'])}"
    end

    # base classes
    action_ids = ir['actions'].map { |a| slug("execute:#{a['name']}") }
    http_ids   = graph['nodes'].select { |n| n.start_with?('HTTP:') }.map { |n| slug(n) }
    method_ids = graph['nodes'].reject { |n| n.start_with?('execute:') || n.start_with?('HTTP:') }.map { |n| slug(n) }

    lines << "  classDef action fill:#E3F2FD,stroke:#1E88E5,stroke-width:1px;"
    lines << "  classDef method fill:#E8F5E9,stroke:#2E7D32,stroke-width:1px;"
    lines << "  classDef http   fill:#FFF3E0,stroke:#EF6C00,stroke-width:1px;"

    # visibility classes
    lines << "  classDef hot stroke:#6A1B9A,stroke-width:3px;"
    lines << "  classDef cycle stroke:#C62828,stroke-width:3px;"
    lines << "  classDef unused fill:#ECECEC,color:#6B7280,stroke:#9CA3AF;"
    lines << "  classDef undef stroke-dasharray:4 2,stroke:#EF4444;"

    action_ids.each { |id| lines << "  class #{id} action;" }
    method_ids.each { |id| lines << "  class #{id} method;" }
    http_ids.each   { |id| lines << "  class #{id} http;" }

    node_classes.each do |node, classes|
      next if classes.nil? || classes.empty?
      lines << "  class #{slug(node)} #{classes.uniq.join(',')};"
    end

    lines.join("\n")
  end

  def write_mermaid(out_dir, ir, graph, node_classes = {})
    mmd = mermaid_graph(ir, graph, node_classes)
    File.write(File.join(out_dir, 'call_graph.mmd'), mmd)

    html = <<~HTML
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Connector Call Graph</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;margin:0;background:#fafafa}
          header{padding:16px 20px;border-bottom:1px solid #e5e7eb;background:#fff;position:sticky;top:0}
          main{padding:16px}
          pre.mermaid{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;overflow:auto}
          .legend{display:flex;gap:8px;align-items:center;margin:12px 0 20px}
          .chip{border-radius:10px;padding:2px 8px;border:1px solid #e5e7eb}
          .chip.action{background:#E3F2FD;border-color:#1E88E5}
          .chip.method{background:#E8F5E9;border-color:#2E7D32}
          .chip.http{background:#FFF3E0;border-color:#EF6C00}
        </style>
        <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
        <script>mermaid.initialize({ startOnLoad: true, securityLevel: 'loose', theme: 'default' });</script>
      </head>
      <body>
        <header><h1 style="margin:0;font-size:18px">Connector Call Graph</h1></header>
        <main>
          <div class="legend">
            <span class="chip action">Action entrypoint</span>
            <span class="chip method">Method</span>
            <span class="chip http">Direct HTTP</span>
          </div>
          <pre class="mermaid">#{mmd}</pre>
        </main>
      </body>
      </html>
    HTML

    html = html.sub('<pre class"mermaid">', %Q{<pre class="mermaid">})
    File.write(File.join(out_dir, 'call_graph.html'), html)
  end

  def write_mermaid_markdown(out_dir, ir, graph, node_classes = {})
    mmd = mermaid_graph(ir, graph, node_classes)
    md = <<~MD
      # Connector Call Graph

      ```mermaid
      #{mmd}
      ```
    MD
    File.write(File.join(out_dir, 'call_graph.md'), md)
  end

  # Optional Graphviz output if `dot` exists
  def write_graphviz(out_dir, graph)
    return unless system('which dot > /dev/null 2>&1')

    dot = +"digraph connector {\n"
    dot << "  rankdir=LR;\n"
    dot << "  node [shape=box, style=rounded, fontsize=10];\n"

    graph['nodes'].each do |n|
      attrs =
        if n.start_with?('execute:')
          'shape=box, style="rounded,filled", fillcolor="#E3F2FD", color="#1E88E5"'
        elsif n.start_with?('HTTP:')
          'shape=hexagon, style="filled", fillcolor="#FFF3E0", color="#EF6C00"'
        else
          'shape=box, style="rounded,filled", fillcolor="#E8F5E9", color="#2E7D32"'
        end
      dot << "  \"#{n}\" [#{attrs}];\n"
    end

    graph['edges'].each do |e|
      dot << "  \"#{e['from']}\" -> \"#{e['to']}\";\n"
    end

    dot << "}\n"

    dot_path = File.join(out_dir, 'call_graph.dot')
    svg_path = File.join(out_dir, 'call_graph.svg')
    File.write(dot_path, dot)
    system("dot -Tsvg #{Shellwords.escape(dot_path)} -o #{Shellwords.escape(svg_path)}")
  rescue => e
    warn "[viz] Graphviz generation failed: #{e.message}"
  end

  # -------------------------------
  # Per-action mini graphs
  # -------------------------------
  def mermaid_graph_subset(nodes, edges, node_classes = {})
    lines = []
    lines << "flowchart TD"

    nodes.each do |n|
      id = slug(n)
      label = n.gsub('"', '\"')
      shape =
        if n.start_with?('execute:') then "([#{label}])"
        elsif n.start_with?('HTTP:') then "{{#{label}}}"
        else "[#{label}]"
        end
      lines << "  #{id}#{shape}"
    end

    edges.each { |e| lines << "  #{slug(e['from'])} --> #{slug(e['to'])}" }

    action_ids = nodes.select { |n| n.start_with?('execute:') }.map { |n| slug(n) }
    http_ids   = nodes.select { |n| n.start_with?('HTTP:') }.map { |n| slug(n) }
    method_ids = nodes.reject { |n| n.start_with?('execute:') || n.start_with?('HTTP:') }.map { |n| slug(n) }

    lines << "  classDef action fill:#E3F2FD,stroke:#1E88E5,stroke-width:1px;"
    lines << "  classDef method fill:#E8F5E9,stroke:#2E7D32,stroke-width:1px;"
    lines << "  classDef http   fill:#FFF3E0,stroke:#EF6C00,stroke-width:1px;"
    lines << "  classDef hot stroke:#6A1B9A,stroke-width:3px;"
    lines << "  classDef cycle stroke:#C62828,stroke-width:3px;"
    lines << "  classDef unused fill:#ECECEC,color:#6B7280,stroke:#9CA3AF;"
    lines << "  classDef undef stroke-dasharray:4 2,stroke:#EF4444;"

    action_ids.each { |id| lines << "  class #{id} action;" }
    method_ids.each { |id| lines << "  class #{id} method;" }
    http_ids.each   { |id| lines << "  class #{id} http;" }

    node_classes.each do |node, classes|
      next unless nodes.include?(node)
      lines << "  class #{slug(node)} #{classes.uniq.join(',')};"
    end

    lines.join("\n")
  end

  def build_subset_for_action(ir, graph, action_name)
    # Use precomputed paths from Analyzer#build_call_paths!
    paths = graph.dig('paths', action_name) || []

    # Collect nodes in any path that starts at this action
    node_set = Set.new
    paths.each { |p| p.each { |n| node_set << n } }

    # Fallback: include the entrypoint even if no paths
    entry = "execute:#{action_name}"
    node_set << entry if node_set.empty? && graph['nodes'].include?(entry)

    # Filter edges to those entirely inside the node_set
    edge_subset = graph['edges'].select { |e| node_set.include?(e['from']) && node_set.include?(e['to']) }

    [node_set.to_a, edge_subset]
  end

  def write_mermaid_per_action(out_dir, ir, graph, node_classes = {})
    actions_dir = File.join(out_dir, 'actions')
    FileUtils.mkdir_p(actions_dir)

    index_rows = []

    ir.fetch('actions', []).each do |a|
      name = a['name']
      safe = slug(name)
      nodes, edges = build_subset_for_action(ir, graph, name)
      mmd = mermaid_graph_subset(nodes, edges, node_classes)

      mmd_path  = File.join(actions_dir, "#{safe}.mmd")
      html_path = File.join(actions_dir, "#{safe}.html")
      File.write(mmd_path, mmd)

      html = <<~HTML
        <!doctype html>
        <html>
        <head>
          <meta charset="utf-8">
          <title>#{name} — Call Graph</title>
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <style>
            body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;margin:0;background:#fafafa}
            header{padding:16px 20px;border-bottom:1px solid #e5e7eb;background:#fff;position:sticky;top:0}
            main{padding:16px}
            pre.mermaid{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:16px;overflow:auto}
            .legend{display:flex;gap:8px;align-items:center;margin:12px 0 20px}
            .chip{border-radius:10px;padding:2px 8px;border:1px solid #e5e7eb}
            .chip.action{background:#E3F2FD;border-color:#1E88E5}
            .chip.method{background:#E8F5E9;border-color:#2E7D32}
            .chip.http{background:#FFF3E0;border-color:#EF6C00}
          </style>
          <script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
          <script>mermaid.initialize({ startOnLoad: true, securityLevel: 'loose', theme: 'default' });</script>
        </head>
        <body>
          <header>
            <h1 style="margin:0;font-size:18px">Action: #{name}</h1>
          </header>
          <main>
            <div class="legend">
              <span class="chip action">Action entrypoint</span>
              <span class="chip method">Method</span>
              <span class="chip http">Direct HTTP</span>
            </div>
            <pre class="mermaid">#{mmd}</pre>
          </main>
        </body>
        </html>
      HTML

      File.write(html_path, html)

      counts = {
        actions: nodes.count { |n| n.start_with?('execute:') },
        methods: nodes.count { |n| !n.start_with?('execute:') && !n.start_with?('HTTP:') },
        http:    nodes.count { |n| n.start_with?('HTTP:') }
      }
      index_rows << { name: name, safe: safe, counts: counts }
    end

    # Index page for all actions
    index_html = <<~HTML
      <!doctype html>
      <html>
      <head>
        <meta charset="utf-8">
        <title>Per-Action Call Graphs</title>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;margin:0;background:#fafafa}
          header{padding:16px 20px;border-bottom:1px solid #e5e7eb;background:#fff;position:sticky;top:0}
          main{padding:16px}
          a{color:#1E88E5;text-decoration:none}
          a:hover{text-decoration:underline}
          table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e5e7eb;border-radius:12px;overflow:hidden}
          th,td{padding:10px;border-bottom:1px solid #e5e7eb;text-align:left;font-size:14px}
          th{background:#fafafa}
          tr:hover{background:#f6fafe}
          code{background:#f3f4f6;border:1px solid #e5e7eb;border-radius:6px;padding:2px 6px}
        </style>
      </head>
      <body>
        <header><h1 style="margin:0;font-size:18px">Per-Action Call Graphs</h1></header>
        <main>
          <p>Open a focused call graph for each action. Mermaid sources are in <code>out/actions/*.mmd</code>.</p>
          <table>
            <thead><tr><th>Action</th><th>Mini graph</th><th>Nodes</th><th>Methods</th><th>HTTP</th></tr></thead>
            <tbody>
              #{index_rows.map { |r|
                %Q{<tr>
                    <td><code>#{r[:name]}</code></td>
                    <td><a href="actions/#{r[:safe]}.html">Open</a></td>
                    <td>#{r[:counts][:actions] + r[:counts][:methods] + r[:counts][:http]}</td>
                    <td>#{r[:counts][:methods]}</td>
                    <td>#{r[:counts][:http]}</td>
                  </tr>}
              }.join("\n")}
            </tbody>
          </table>
        </main>
      </body>
      </html>
    HTML

    File.write(File.join(out_dir, 'call_graph_actions.html'), index_html)
  end

  def write_markdown_per_action(out_dir, ir, graph, node_classes = {})
    actions_dir = File.join(out_dir, 'actions')
    FileUtils.mkdir_p(actions_dir)
    index_lines = ["# Per‑Action Call Graphs", ""]

    ir.fetch('actions', []).each do |a|
      name = a['name']
      safe = slug(name)
      nodes, edges = build_subset_for_action(ir, graph, name)
      mmd = mermaid_graph_subset(nodes, edges, node_classes)
      File.write(File.join(actions_dir, "#{safe}.md"),
        "## #{name}\n\n```mermaid\n#{mmd}\n```\n")
      index_lines << "- [#{name}](actions/#{safe}.md)"
    end

    File.write(File.join(out_dir, 'call_graph_actions.md'), index_lines.join("\n"))
  end

  def write_complexity_dashboard(out_dir, metrics)
    path = File.join(out_dir, 'complexity.html')
    per = metrics['per_action'] || {}
    rows = per.map do |act, m|
      %Q{<tr>
        <td><code>#{act}</code></td>
        <td>#{m['nodes']}</td><td>#{m['edges']}</td>
        <td>#{m['max_depth']}</td><td>#{m['paths']}</td>
        <td>#{m['http_nodes']}</td>
      </tr>}
    end.join

    hot_nodes = (metrics['hot'] || []).map { |n| "<li><code>#{n}</code></li>" }.join
    cyc_nodes = (metrics['cycle'] || []).map { |n| "<li><code>#{n}</code></li>" }.join
    undefd    = (metrics['undefined'] || []).map { |n| "<li><code>#{n}</code></li>" }.join
    unused    = (metrics['unused'] || []).map { |n| "<li><code>#{n}</code></li>" }.join

    html = <<~HTML
      <!doctype html><html><head><meta charset="utf-8">
      <title>Connector Complexity</title>
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <style>
        body{font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu,Cantarell,Noto Sans,sans-serif;margin:0;background:#fafafa}
        header{padding:16px 20px;border-bottom:1px solid #e5e7eb;background:#fff;position:sticky;top:0}
        main{padding:16px}
        table{width:100%;border-collapse:collapse;background:#fff;border:1px solid #e5e7eb;border-radius:12px;overflow:hidden}
        th,td{padding:10px;border-bottom:1px solid #e5e7eb;text-align:left;font-size:14px}
        th{background:#fafafa} tr:hover{background:#f6fafe}
        .grid{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin:16px 0}
        section{background:#fff;border:1px solid #e5e7eb;border-radius:12px;padding:12px}
        ul{margin:0;padding-left:20px}
        code{background:#f3f4f6;border:1px solid #e5e7eb;border-radius:6px;padding:2px 6px}
      </style></head><body>
      <header><h1 style="margin:0;font-size:18px">Connector Complexity</h1></header>
      <main>
        <h2>Actions ranked by structural complexity</h2>
        <table>
          <thead><tr><th>Action</th><th>Nodes</th><th>Edges</th><th>Max depth</th><th>#Paths</th><th>HTTP</th></tr></thead>
          <tbody>#{rows}</tbody>
        </table>
        <div class="grid">
          <section><h3>Hotspots (high fan-in/out)</h3><ul>#{hot_nodes}</ul></section>
          <section><h3>Cycles</h3><ul>#{cyc_nodes}</ul></section>
          <section><h3>Undefined calls</h3><ul>#{undefd}</ul></section>
          <section><h3>Unused methods</h3><ul>#{unused}</ul></section>
        </div>
      </main></body></html>
    HTML
    File.write(path, html)
  end

end

# -------------------------------
# CLI
# -------------------------------
if __FILE__ == $0
  opts = { out: 'out' }
  OptionParser.new do |o|
    o.banner = "Usage: ruby #{File.basename($0)} path/to/connector.rb [-o out_dir]"
    o.on('-o', '--out DIR', 'Output directory') { |v| opts[:out] = v }
  end.parse!

  abort("Please provide path to connector file") if ARGV.empty?
  path = ARGV[0]
  abort("File not found: #{path}") unless File.file?(path)

  src = File.read(path, encoding: 'UTF-8')
  analyzer = ConnectorAnalyzer.new(src).analyze!

  FileUtils.mkdir_p(opts[:out])

  ir_path  = File.join(opts[:out], 'ir.json')
  cg_path  = File.join(opts[:out], 'call_graph.json')
  is_path  = File.join(opts[:out], 'issues.json')
  ic_path  = File.join(opts[:out], 'ir_clean.json')

  File.write(ir_path, JSON.pretty_generate(analyzer.ir))
  File.write(cg_path, JSON.pretty_generate(analyzer.graph))
  File.write(is_path, JSON.pretty_generate(analyzer.issues))

  ir_clean = IRClean.build(analyzer.ir, analyzer.graph, analyzer.issues)
  File.write(ic_path, JSON.pretty_generate(ir_clean))

  # --- Visualization outputs ---
  # --- Metrics & Visualization ---
  begin
    metrics = Metrics.build(analyzer.ir, analyzer.graph, analyzer.issues)
    File.write(File.join(opts[:out], 'metrics.json'), JSON.pretty_generate(metrics))
  rescue => e
    warn "[metrics] Failed: #{e.message}"
    metrics = nil
  end

  node_classes = metrics ? Viz.build_node_classes(analyzer.graph, metrics) : {}

  begin
    Viz.write_mermaid(opts[:out], analyzer.ir, analyzer.graph, node_classes)
  rescue => e
    warn "[viz] Mermaid generation failed: #{e.message}"
  end

  begin
    Viz.write_graphviz(opts[:out], analyzer.graph) # no-op if `dot` missing
  rescue => e
    warn "[viz] Graphviz generation failed: #{e.message}"
  end

  begin
    Viz.write_mermaid_per_action(opts[:out], analyzer.ir, analyzer.graph, node_classes)
  rescue => e
    warn "[viz] Per-action Mermaid generation failed: #{e.message}"
  end

  begin
    Viz.write_complexity_dashboard(opts[:out], metrics) if metrics
  rescue => e
    warn "[viz] Complexity dashboard failed: #{e.message}"
  end

  puts "[✓] Wrote: #{ir_path}, #{cg_path}, #{is_path}, #{ic_path}, " \
       "#{File.join(opts[:out], 'metrics.json')}, " \
       "#{File.join(opts[:out], 'call_graph.mmd')}, #{File.join(opts[:out], 'call_graph.html')}, " \
       "#{File.join(opts[:out], 'call_graph_actions.html')}, complexity.html (plus /actions/*.html, *.mmd)"
  puts "Actions: #{analyzer.ir['actions'].size}, Methods: #{analyzer.ir['methods'].size}, " \
       "ObjectDefs: #{analyzer.ir['object_definitions'].size}, PickLists: #{analyzer.ir['pick_lists'].size}"
  puts "Issues: #{analyzer.issues.size}"
end