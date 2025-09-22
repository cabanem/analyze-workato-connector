import re, json, csv, sys, os, logging
from typing import Dict, List, Set, Optional, Tuple
from dataclasses import dataclass, field
from collections import defaultdict
from datetime import datetime

@dataclass
class Component:
    """Component with lazy evaluation of dependencies"""
    name: str
    component_type: str
    code_block: str = ""  # Store raw code for lazy analysis

    # Outgoing dependencies (what this component uses)
    _dep_methods: Optional[Set[str]] = None
    _dep_objects: Optional[Set[str]] = None
    _dep_picklists: Optional[Set[str]] = None

    # Metadata
    calls_external_api: Optional[str] = None
    uses_cache: Optional[str] = None
    error_handling_type: Optional[str] = None
    retry_logic: Optional[str] = None
    
    @property
    def dep_methods(self) -> Set[str]:
        if self._dep_methods is None:
            self._analyze_dependencies()
        return self._dep_methods
    
    @property
    def dep_objects(self) -> Set[str]:
        if self._dep_objects is None:
            self._analyze_dependencies()
        return self._dep_objects
    
    @property
    def dep_picklists(self) -> Set[str]:
        if self._dep_picklists is None:
            self._analyze_dependencies()
        return self._dep_picklists
    
    def _analyze_dependencies(self):
        """Enhanced dependency analysis with better patterns"""
        self._dep_methods = set()
        self._dep_objects = set()
        self._dep_picklists = set()

        if not self.code_block:
            return
        
        # Method dependencies
        # Pattern 1: call('method_name', ...)
        self._dep_methods.update(re.findall(r"call\(['\"](\w+)['\"]", self.code_block))
        
        # Special handling for picklists that call methods
        if self.component_type == 'picklist':
            # Look for dynamic_model_picklist calls (common pattern)
            if 'dynamic_model_picklist' in self.code_block:
                self._dep_methods.add('dynamic_model_picklist')

        # === OBJECT DEFINITION DEPENDENCIES ===
        # Pattern 1: object_definitions['name']
        self._dep_objects.update(re.findall(r"object_definitions\[['\"](\w+)['\"]\]", self.code_block))
        
        # Pattern 2: Concatenation with object_definitions
        concat_matches = re.findall(r"\.concat\(object_definitions\[['\"](\w+)['\"]\]", self.code_block)
        self._dep_objects.update(concat_matches)
        
        # Pattern 3: .only() method on object_definitions
        only_matches = re.findall(r"object_definitions\[['\"](\w+)['\"]\]\.only", self.code_block)
        self._dep_objects.update(only_matches)
        
        # === PICKLIST DEPENDENCIES ===
        # Pattern 1: pick_list: :name
        self._dep_picklists.update(re.findall(r"pick_list:\s*:(\w+)", self.code_block))
        
        # Pattern 2: pick_list: 'name' or "name"  
        self._dep_picklists.update(re.findall(r"pick_list:\s*['\"](\w+)['\"]", self.code_block))
        
        # Pattern 3: pick_list => :name (hash rocket syntax)
        self._dep_picklists.update(re.findall(r"pick_list\s*=>\s*:(\w+)", self.code_block))
        
        # Pattern 4: :pick_list => :name (symbol key with hash rocket)
        self._dep_picklists.update(re.findall(r":pick_list\s*=>\s*:(\w+)", self.code_block))
        
        # Pattern 5: Direct picklist array access
        self._dep_picklists.update(re.findall(r"pick_lists\[['\"](\w+)['\"]\]", self.code_block))

class RelationshipAnalyzer:
    """Analyzes all relationship types in the connector"""
    
    def __init__(self, components: Dict[str, Component]):
        self.components = components
        self.relationships = {
            'method_calls_method': [],      # (a) methods → methods
            'action_calls_method': [],       # actions → methods
            'action_uses_object': [],        # actions → object_defs
            'action_uses_picklist': [],      # actions → picklists
            'object_uses_object': [],        # object_defs → object_defs
            'object_uses_picklist': [],      # object_defs → picklists
            'picklist_calls_method': [],     # (c) picklists → methods
            'method_uses_object': [],        # methods → object_defs
            'method_calls_picklist': [],     # (b) methods → picklists (rare)
        }
    
    def analyze(self):
        """Build complete relationship map"""
        for name, component in self.components.items():
            source_type = component.component_type
            
            # Analyze method dependencies
            for method in component.dep_methods:
                if method in self.components:
                    target_type = self.components[method].component_type
                    rel_type = f"{source_type}_calls_{target_type}"
                    self.relationships.setdefault(rel_type, []).append((name, method))
            
            # Analyze object dependencies
            for obj in component.dep_objects:
                if obj in self.components:
                    target_type = self.components[obj].component_type
                    rel_type = f"{source_type}_uses_{target_type}"
                    self.relationships.setdefault(rel_type, []).append((name, obj))
            
            # Analyze picklist dependencies
            for picklist in component.dep_picklists:
                if picklist in self.components:
                    rel_type = f"{source_type}_uses_picklist"
                    self.relationships.setdefault(rel_type, []).append((name, picklist))
        
        return self.relationships
    
    def get_summary(self):
        """Get relationship summary statistics"""
        summary = {}
        for rel_type, rels in self.relationships.items():
            if rels:  # Only include non-empty relationship types
                summary[rel_type] = len(rels)
        return summary

class OptimizedConnectorAnalyzer:
    def __init__(self, connector_code: str):
        self.lines = connector_code.split('\n')
        self.total_lines = len(self.lines)
        self.components: Dict[str, Component] = {}
        self.section_cache = {}
        logging.basicConfig(level=logging.INFO)
        self.logger = logging.getLogger(__name__)
        
    def analyze(self) -> Dict[str, Component]:
        """Single-pass analysis with section detection"""
        self.logger.info(f"Analyzing {self.total_lines} lines of code")
        
        # Single pass to identify major sections
        self._identify_sections()
        
        # Parse each section in parallel (conceptually)
        if 'actions' in self.section_cache:
            self._parse_actions_optimized()
        if 'methods' in self.section_cache:
            self._parse_methods_optimized()
        if 'object_definitions' in self.section_cache:
            self._parse_object_defs_optimized()
        if 'pick_lists' in self.section_cache:
            self._parse_picklists_optimized()
            
        self.logger.info(f"Found {len(self.components)} components")
        return self.components
    
    def _identify_sections(self):
        """Single pass to identify major sections"""
        current_section = None
        section_start = 0
        indent_stack = []
        
        for i, line in enumerate(self.lines):
            # Check for major sections
            if re.match(r'^\s{2}(actions|methods|object_definitions|pick_lists):\s*\{', line):
                section_name = re.match(r'^\s{2}(\w+):', line).group(1)
                self.section_cache[section_name] = {'start': i, 'lines': []}
                current_section = section_name
                section_start = i
                indent_stack = [2]  # Track indentation level
                
            elif current_section:
                # Track section content by indentation
                indent = len(line) - len(line.lstrip())
                
                # Check if we're still in the section
                if line.strip() and indent <= 2 and not line.strip().startswith('}'):
                    # End of section
                    self.section_cache[current_section]['end'] = i
                    current_section = None
                else:
                    self.section_cache[current_section]['lines'].append(i)
    
    def _parse_actions_optimized(self):
        """Parse actions section efficiently"""
        section = self.section_cache['actions']
        start_line = section['start']
        end_line = section.get('end', self.total_lines)
        
        # Use state machine for parsing
        current_action = None
        current_block = []
        indent_level = 0
        
        for i in range(start_line + 1, end_line):
            line = self.lines[i]
            stripped = line.strip()
            
            if not stripped:
                continue
                
            current_indent = len(line) - len(line.lstrip())
            
            # Detect new action
            if current_indent == 4 and ':' in stripped and '{' in stripped:
                # Save previous action
                if current_action:
                    self._save_component(current_action, '\n'.join(current_block), 'action')
                
                # Start new action
                action_name = stripped.split(':')[0].strip()
                current_action = action_name
                current_block = [line]
                indent_level = 4
                
            elif current_action and current_indent >= indent_level:
                current_block.append(line)
        
        # Save last action
        if current_action:
            self._save_component(current_action, '\n'.join(current_block), 'action')
    
    def _parse_methods_optimized(self):
        """Parse methods section efficiently"""
        section = self.section_cache.get('methods', {})
        start_line = section.get('start', 0)
        end_line = section.get('end', self.total_lines)
        
        # Pattern for method definition
        method_pattern = re.compile(r'^\s{4}(\w+):\s*lambda')
        
        current_method = None
        current_block = []
        
        for i in range(start_line + 1, end_line):
            line = self.lines[i]
            
            # Check for new method
            match = method_pattern.match(line)
            if match:
                # Save previous method
                if current_method:
                    self._save_component(current_method, '\n'.join(current_block), 'method')
                
                current_method = match.group(1)
                current_block = [line]
            elif current_method:
                # Continue collecting method body
                if len(line) - len(line.lstrip()) >= 4:
                    current_block.append(line)
                elif line.strip() and not line.strip().startswith('}'):
                    # End of method
                    self._save_component(current_method, '\n'.join(current_block), 'method')
                    current_method = None
                    current_block = []
        
        # Save last method
        if current_method:
            self._save_component(current_method, '\n'.join(current_block), 'method')
    
    def _parse_object_defs_optimized(self):
        """Parse object definitions efficiently"""
        section = self.section_cache.get('object_definitions', {})
        start_line = section.get('start', 0)
        end_line = section.get('end', self.total_lines)
        
        # Similar pattern matching for object definitions
        obj_pattern = re.compile(r'^\s{4}(\w+):\s*\{')
        
        current_obj = None
        current_block = []
        brace_count = 0
        
        for i in range(start_line + 1, end_line):
            line = self.lines[i]
            
            match = obj_pattern.match(line)
            if match and brace_count == 0:
                if current_obj:
                    self._save_component(current_obj, '\n'.join(current_block), 'object_def')
                
                current_obj = match.group(1)
                current_block = [line]
                brace_count = 1
            elif current_obj:
                current_block.append(line)
                brace_count += line.count('{') - line.count('}')
                
                if brace_count == 0:
                    self._save_component(current_obj, '\n'.join(current_block), 'object_def')
                    current_obj = None
                    current_block = []
    
    def _parse_picklists_optimized(self):
        """Parse picklists with proper lambda body extraction"""
        section = self.section_cache.get('pick_lists', {})
        start_line = section.get('start', 0)
        end_line = section.get('end', self.total_lines)
        
        current_picklist = None
        current_block = []
        in_lambda = False
        
        for i in range(start_line + 1, end_line):
            line = self.lines[i]
            
            # Check for new picklist
            if re.match(r'^\s{4}(\w+):\s*lambda', line):
                # Save previous picklist
                if current_picklist:
                    self._save_component(current_picklist, '\n'.join(current_block), 'picklist')
                
                # Start new picklist
                match = re.match(r'^\s{4}(\w+):\s*lambda', line)
                current_picklist = match.group(1)
                current_block = [line]
                in_lambda = True
                
            elif current_picklist and in_lambda:
                # Continue collecting lambda body
                indent = len(line) - len(line.lstrip())
                
                # Check if we're still in the lambda (indent > 4)
                if indent > 4 or line.strip() == '' or line.strip() == 'end':
                    current_block.append(line)
                    if line.strip() == 'end':
                        in_lambda = False
                elif indent == 4 and line.strip():
                    # New picklist or end of section
                    self._save_component(current_picklist, '\n'.join(current_block), 'picklist')
                    current_picklist = None
                    current_block = []
                    in_lambda = False
        
        # Save last picklist
        if current_picklist:
            self._save_component(current_picklist, '\n'.join(current_block), 'picklist')
    
    def _save_component(self, name: str, code_block: str, comp_type: str):
        """Enhanced component saving with better pattern detection"""
        component = Component(
            name=name,
            component_type=comp_type,
            code_block=code_block
        )
        
        # Fixed API call detection for Ruby/Workato patterns
        api_patterns = [
            r'\bget\s*\(',          # get( or get (
            r'\bpost\s*\(',         # post( or post (
            r'\bput\s*\(',          # put( or put (
            r'\bdelete\s*\(',       # delete( or delete (
            r'\bpatch\s*\(',        # patch( or patch (
            r'\.after_error_response',  # Workato API error handling
            r'\.request_format',    # API request formatting
            r'https?://'           # Direct URL references
        ]
        
        if any(re.search(pattern, code_block) for pattern in api_patterns):
            component.calls_external_api = 'true'
        else:
            component.calls_external_api = 'false'
        
        # Fixed cache detection for Workato patterns
        cache_patterns = [
            r'workato\.cache\.get',
            r'workato\.cache\.set',
            r'workato\.cache\[',
        ]
        
        if any(re.search(pattern, code_block) for pattern in cache_patterns):
            component.uses_cache = 'true'
        else:
            component.uses_cache = 'false'
        
        # Retry logic detection
        retry_patterns = [
            r'retry',
            r'exponential_backoff',
            r'max_retries',
            r'retry_on_response',
            r'retry_on_request'
        ]
        
        if any(re.search(pattern, code_block, re.IGNORECASE) for pattern in retry_patterns):
            if 'exponential_backoff' in code_block.lower():
                component.retry_logic = 'exponential_backoff'
            elif 'rate_limit' in code_block:
                component.retry_logic = 'rate_limit'
            else:
                component.retry_logic = 'retry'
        else:
            component.retry_logic = 'none'
        
        # Error handling detection
        error_patterns = {
            'circuit_breaker': r'circuit_breaker',
            'custom': r'(after_error_response|error_handler)',
            'throws': r'\berror\s*\(',
            'rescue': r'\brescue\b'
        }
        
        component.error_handling_type = 'none'
        for error_type, pattern in error_patterns.items():
            if re.search(pattern, code_block):
                component.error_handling_type = error_type
                break
        
        self.components[name] = component

        def to_csv(self, filename: str = "connector_components.csv"):
            """Export with progress indicator for large files"""
            total = len(self.components)
            self.logger.info(f"Exporting {total} components to CSV")
            
            with open(filename, 'w', newline='', encoding='utf-8') as csvfile:
                fieldnames = [
                    'component', 'component_type', 'dep_methods', 'dep_objects', 
                    'dep_picklists', 'calls_external_api', 'uses_cache', 
                    'error_handling_type', 'retry_logic'
                ]
                writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
                writer.writeheader()
                
                for i, component in enumerate(sorted(self.components.values(), 
                                                    key=lambda x: (x.component_type, x.name))):
                    if i % 50 == 0:
                        self.logger.info(f"Processed {i}/{total} components")
                        
                    writer.writerow({
                        'component': component.name,
                        'component_type': component.component_type,
                        'dep_methods': ';'.join(sorted(component.dep_methods)),
                        'dep_objects': ';'.join(sorted(component.dep_objects)),
                        'dep_picklists': ';'.join(sorted(component.dep_picklists)),
                        'calls_external_api': component.calls_external_api or '',
                        'uses_cache': component.uses_cache or '',
                        'error_handling_type': component.error_handling_type or '',
                        'retry_logic': component.retry_logic or ''
                    })

def main():
    """Main function optimized for large connector analysis"""
    
    # Set up logging
    logging.basicConfig(
        level=logging.INFO,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    logger = logging.getLogger(__name__)
    
    # Determine connector file path
    if len(sys.argv) > 1:
        # Use provided path
        connector_path = sys.argv[1]
        if not os.path.exists(connector_path):
            logger.error(f"File not found: {connector_path}")
            return
    else:
        # Look in parent directory (since we're in src/)
        parent_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
        rb_files = [f for f in os.listdir(parent_dir) if f.endswith('.rb')]
        
        if not rb_files:
            logger.error(f"No .rb file found in {parent_dir}")
            print("Usage: python src/main.py [path/to/connector.rb]")
            return
        
        # If multiple .rb files, pick the largest (likely the main connector)
        if len(rb_files) > 1:
            rb_files.sort(key=lambda f: os.path.getsize(os.path.join(parent_dir, f)), reverse=True)
            logger.info(f"Found {len(rb_files)} .rb files, selecting largest: {rb_files[0]}")
        
        connector_path = os.path.join(parent_dir, rb_files[0])
    
    # Get file info
    file_size = os.path.getsize(connector_path)
    file_name = os.path.basename(connector_path)
    
    logger.info(f"Starting analysis of: {file_name}")
    logger.info(f"File size: {file_size:,} bytes ({file_size/1024:.1f} KB)")
    
    # Read the connector file
    start_time = datetime.now()
    
    try:
        with open(connector_path, 'r', encoding='utf-8') as f:
            connector_code = f.read()
    except Exception as e:
        logger.error(f"Failed to read file: {e}")
        return
    
    line_count = len(connector_code.splitlines())
    logger.info(f"Loaded {line_count:,} lines of code in {(datetime.now() - start_time).total_seconds():.2f}s")
    
    # Run analysis
    logger.info("Starting component analysis...")
    analysis_start = datetime.now()
    
    try:
        analyzer = OptimizedConnectorAnalyzer(connector_code)
        components = analyzer.analyze()
    except Exception as e:
        logger.error(f"Analysis failed: {e}")
        return
    
    analysis_time = (datetime.now() - analysis_start).total_seconds()
    logger.info(f"Analysis completed in {analysis_time:.2f}s")

    # Analyze relationships
    output_dir = os.path.dirname(connector_path) or '.'
    base_name = os.path.splitext(file_name)[0]

    logger.info("Analyzing component relationships...")
    rel_analyzer = RelationshipAnalyzer(components)
    relationships = rel_analyzer.analyze()
    rel_summary = rel_analyzer.get_summary()

    # Add to the console output
    print("\n📐 Relationship Analysis:")
    print("  Unique relationship types found:")

    # Key relationships to highlight
    key_rels = {
        'method_calls_method': 'Methods calling methods',
        'picklist_calls_method': 'Picklists calling methods',
        'action_uses_picklist': 'Actions using picklists',
        'object_def_uses_object_def': 'Objects referencing objects',
        'action_calls_method': 'Actions calling methods'
    }

    for rel_type, description in key_rels.items():
        count = rel_summary.get(rel_type, 0)
        if count > 0:
            print(f"    • {description}: {count}")

    # Find components with interesting patterns
    print("\n  Special patterns:")

    # Find picklists that call methods (dynamic picklists)
    dynamic_picklists = [name for name, c in components.items() 
                        if c.component_type == 'picklist' and len(c.dep_methods) > 0]
    if dynamic_picklists:
        print(f"    • Dynamic picklists (call methods): {', '.join(dynamic_picklists)}")

    # Find methods that orchestrate other methods
    orchestrator_methods = [(name, len(c.dep_methods)) for name, c in components.items() 
                        if c.component_type == 'method' and len(c.dep_methods) > 2]
    if orchestrator_methods:
        orchestrator_methods.sort(key=lambda x: x[1], reverse=True)
        print(f"    • Orchestrator methods (call 3+ methods):")
        for name, count in orchestrator_methods[:5]:
            print(f"        - {name}: calls {count} methods")

    # Save detailed relationships to separate file
    rel_report_path = os.path.join(output_dir, f"{base_name}_relationships.json")
    with open(rel_report_path, 'w', encoding='utf-8') as f:
        json.dump({
            'summary': rel_summary,
            'details': {k: v for k, v in relationships.items() if v},
            'dynamic_picklists': dynamic_picklists,
            'orchestrator_methods': dict(orchestrator_methods[:10])
        }, f, indent=2)
    logger.info(f"✓ Relationship details saved to: {rel_report_path}")
    
    # Determine output directory
    project_root = os.path.dirname(connector_path) or '.'
    output_dir = os.path.join(project_root, 'output')
    os.makedirs(output_dir, exist_ok=True)
    base_name = os.path.splitext(file_name)[0]
    
    # Export to CSV
    csv_path = os.path.join(output_dir, f"{base_name}_components.csv")
    logger.info(f"Exporting component database to CSV...")
    
    try:
        analyzer.to_csv(csv_path)
        logger.info(f"✓ Component database saved to: {csv_path}")
    except Exception as e:
        logger.error(f"Failed to save CSV: {e}")
    
    # Generate dependency graph (only for manageable sizes)
    if len(components) < 1000:  # Skip graph for very large connectors
        graph_path = os.path.join(output_dir, f"{base_name}_dependency_graph.json")
        logger.info("Generating dependency graph...")
        
        try:
            graph = generate_dependency_graph(components)
            with open(graph_path, 'w', encoding='utf-8') as f:
                json.dump(graph, f, indent=2)
            logger.info(f"✓ Dependency graph saved to: {graph_path}")
        except Exception as e:
            logger.error(f"Failed to generate graph: {e}")
    else:
        logger.warning(f"Skipping graph generation (too many components: {len(components)})")
    
    # Generate summary statistics
    print("\n" + "="*60)
    print(f"📊 ANALYSIS SUMMARY FOR: {file_name}")
    print("="*60)
    
    print(f"\nFile Statistics:")
    print(f"  • Lines of code: {line_count:,}")
    print(f"  • File size: {file_size:,} bytes")
    print(f"  • Analysis time: {analysis_time:.2f} seconds")
    print(f"  • Components found: {len(components)}")
    
    # Component breakdown by type
    by_type = defaultdict(int)
    for c in components.values():
        by_type[c.component_type] += 1
    
    print(f"\nComponents by Type:")
    for ctype, count in sorted(by_type.items(), key=lambda x: x[1], reverse=True):
        print(f"  • {ctype:15s}: {count:4d}")
    
    # Analyze dependencies
    print(f"\nDependency Analysis:")
    
    # Calculate dependency metrics
    dependency_counts = []
    api_components = []
    cached_components = []
    
    for name, comp in components.items():
        # Count dependencies (triggers lazy loading)
        dep_count = len(comp.dep_methods) + len(comp.dep_objects) + len(comp.dep_picklists)
        dependency_counts.append((name, dep_count))
        
        if comp.calls_external_api == 'true':
            api_components.append(name)
        if comp.uses_cache == 'true':
            cached_components.append(name)
    
    # Sort by dependency count
    dependency_counts.sort(key=lambda x: x[1], reverse=True)
    
    print(f"  • Components with API calls: {len(api_components)}")
    print(f"  • Components using cache: {len(cached_components)}")
    print(f"  • Average dependencies per component: {sum(d[1] for d in dependency_counts)/len(dependency_counts):.1f}")
    
    # Most connected components
    print(f"\nMost Connected Components (Top 10):")
    for name, deps in dependency_counts[:10]:
        comp = components[name]
        print(f"  • {name:30s} ({comp.component_type:10s}): {deps:3d} dependencies")
    
    # Identify potential issues
    print(f"\n⚠️  Potential Issues:")
    
    # Find circular dependencies (simplified check)
    circular_deps = find_circular_dependencies(components)
    if circular_deps:
        print(f"  • Found {len(circular_deps)} potential circular dependencies")
    
    # Find orphaned components
    orphaned = find_orphaned_components(components)
    if orphaned:
        print(f"  • Found {len(orphaned)} orphaned components (no dependencies)")
    
    # Performance concerns
    perf_critical = [name for name, c in components.items() 
                    if c.calls_external_api == 'true' and c.retry_logic == 'none']
    if perf_critical:
        print(f"  • {len(perf_critical)} components make API calls without retry logic")
    
    print("\n" + "="*60)
    
    # Save summary report
    report_path = os.path.join(output_dir, f"{base_name}_analysis_report.txt")
    save_analysis_report(report_path, file_name, line_count, components, dependency_counts)
    logger.info(f"✓ Analysis report saved to: {report_path}")

    # Visualize
    try:
        from analyzer import generate_analysis_report
        print("\n📈 Generating visualizations and analysis...")
        generate_analysis_report(csv_path, graph_path, output_dir)
        logger.info("✓ Analysis and visualizations generated")
    except ImportError:
        logger.warning("Install matplotlib, seaborn, networkx, and pandas for visualizations")
    except Exception as e:
        logger.error(f"Visualization failed: {e}")

def generate_dependency_graph(components: Dict[str, 'Component']) -> Dict:
    """Generate a dependency graph for visualization"""
    graph = {
        "metadata": {
            "total_components": len(components),
            "generated_at": datetime.now().isoformat()
        },
        "nodes": [],
        "edges": []
    }
    
    for name, component in components.items():
        # Add node
        graph["nodes"].append({
            "id": name,
            "type": component.component_type,
            "api_calls": component.calls_external_api == "true",
            "cached": component.uses_cache == "true",
            "retry_logic": component.retry_logic or "none"
        })
        
        # Add edges for method dependencies
        for method in component.dep_methods:
            graph["edges"].append({
                "source": name,
                "target": method,
                "type": "method_call"
            })
        
        # Add edges for object dependencies
        for obj in component.dep_objects:
            graph["edges"].append({
                "source": name,
                "target": obj,
                "type": "object_ref"
            })
        
        # Add edges for picklists
        for picklist in component.dep_picklists:
            graph["edges"].append({
                "source": name,
                "target": picklist,
                "type": "picklist_ref"
            })
    
    return graph

def find_circular_dependencies(components: Dict[str, 'Component']) -> List[Tuple[str, str]]:
    """Simple circular dependency detection"""
    circular = []
    
    for name1, comp1 in components.items():
        for dep in comp1.dep_methods:
            if dep in components:
                comp2 = components[dep]
                if name1 in comp2.dep_methods:
                    if (dep, name1) not in circular:  # Avoid duplicates
                        circular.append((name1, dep))
    
    return circular

def find_orphaned_components(components: Dict[str, 'Component']) -> List[str]:
    """Find components with no dependencies or dependents"""
    # Build reverse dependency map
    dependents = defaultdict(set)
    
    for name, comp in components.items():
        for dep in comp.dep_methods:
            dependents[dep].add(name)
        for dep in comp.dep_objects:
            dependents[dep].add(name)
    
    # Find orphans
    orphaned = []
    for name, comp in components.items():
        has_deps = len(comp.dep_methods) > 0 or len(comp.dep_objects) > 0
        has_dependents = len(dependents[name]) > 0
        
        if not has_deps and not has_dependents and comp.component_type != 'action':
            orphaned.append(name)
    
    return orphaned

def save_analysis_report(path: str, file_name: str, line_count: int, 
                         components: Dict, dependency_counts: List):
    """Save a detailed analysis report with relationships"""
    # Run relationship analysis for the report
    rel_analyzer = RelationshipAnalyzer(components)
    relationships = rel_analyzer.analyze()
    rel_summary = rel_analyzer.get_summary()
    
    with open(path, 'w', encoding='utf-8') as f:
        f.write(f"Connector Analysis Report\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")
        f.write(f"{'='*60}\n\n")
        
        f.write(f"File: {file_name}\n")
        f.write(f"Lines: {line_count:,}\n")
        f.write(f"Components: {len(components)}\n\n")
        
        # Add relationship summary
        f.write("Relationship Summary:\n")
        f.write("-"*40 + "\n")
        for rel_type, count in sorted(rel_summary.items(), key=lambda x: x[1], reverse=True):
            f.write(f"  {rel_type}: {count}\n")
        f.write("\n")
        
        f.write("Component Inventory:\n")
        f.write("-"*40 + "\n")
        
        # Group by type
        by_type = defaultdict(list)
        for name, comp in components.items():
            by_type[comp.component_type].append(name)
        
        for ctype in sorted(by_type.keys()):
            f.write(f"\n{ctype.upper()}S ({len(by_type[ctype])}):\n")
            for name in sorted(by_type[ctype]):
                comp = components[name]
                deps = len(comp.dep_methods) + len(comp.dep_objects) + len(comp.dep_picklists)
                f.write(f"  - {name} ({deps} deps)")
                
                # Show dependency breakdown
                if deps > 0:
                    breakdown = []
                    if len(comp.dep_methods) > 0:
                        breakdown.append(f"{len(comp.dep_methods)}m")
                    if len(comp.dep_objects) > 0:
                        breakdown.append(f"{len(comp.dep_objects)}o")
                    if len(comp.dep_picklists) > 0:
                        breakdown.append(f"{len(comp.dep_picklists)}p")
                    f.write(f" [{','.join(breakdown)}]")
                
                if comp.calls_external_api == 'true':
                    f.write(" [API]")
                if comp.uses_cache == 'true':
                    f.write(" [CACHED]")
                f.write("\n")
        
        f.write("\n" + "="*60 + "\n")
        f.write("End of Report\n")

if __name__ == "__main__":
    main()
