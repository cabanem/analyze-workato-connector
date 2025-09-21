import re, json, csv
from typing import Dict, List, Set, Tuple, Optional
from dataclasses import dataclass, field
from collections import defaultdict

@dataclass
class Component:
    """Represents a connector component with all its metadata"""
    name: str
    component_type: str
    dep_methods: Set[str] = field(default_factory=set)
    dep_objects: Set[str] = field(default_factory=set)
    dep_picklists: Set[str] = field(default_factory=set)
    calls_external_api: Optional[str] = None
    uses_cache: Optional[str] = None
    error_handling_type: Optional[str] = None
    retry_logic: Optional[str] = None
    auth_required: Optional[str] = None
    performance_critical: Optional[str] = None
    notes: str = ""

class WorkatoConnectorAnalyzer:
    def __init__(self, connector_code: str):
        self.code = connector_code
        self.components: Dict[str, Component] = {}
        self.call_graph: Dict[str, Set[str]] = defaultdict(set)
        
    def analyze(self) -> Dict[str, Component]:
        """Main analysis entry point"""
        self._extract_actions()
        self._extract_methods()
        self._extract_object_definitions()
        self._extract_picklists()
        self._analyze_dependencies()
        self._infer_characteristics()
        return self.components
    
    def _extract_actions(self):
        """Extract all actions from the connector"""
        # Match action blocks
        action_pattern = r"(\w+):\s*\{[^}]*?title:\s*['\"]([^'\"]+)['\"]"
        actions_section = re.search(r"actions:\s*\{(.*?)\n\s{2}\},$", self.code, re.DOTALL)
        
        if actions_section:
            actions_code = actions_section.group(1)
            
            # Find each action definition
            action_blocks = re.findall(r"(\w+):\s*\{.*?\n\s{4}\}", actions_code, re.DOTALL)
            
            for action_match in re.finditer(r"(\w+):\s*\{(.*?)\n\s{4}\}", actions_code, re.DOTALL):
                action_name = action_match.group(1)
                action_body = action_match.group(2)
                
                component = Component(
                    name=action_name,
                    component_type="action"
                )
                
                # Extract execute lambda dependencies
                execute_match = re.search(r"execute:\s*lambda[^{]*\{([^}]+)\}", action_body, re.DOTALL)
                if execute_match:
                    self._extract_method_calls(execute_match.group(1), component)
                
                # Extract input/output field dependencies
                input_match = re.search(r"input_fields:.*?object_definitions\['(\w+)'\]", action_body)
                if input_match:
                    component.dep_objects.add(input_match.group(1))
                
                output_match = re.search(r"output_fields:.*?object_definitions\['(\w+)'\]", action_body)
                if output_match:
                    component.dep_objects.add(output_match.group(1))
                
                # Check for inline field definitions with dependencies
                field_deps = re.findall(r"object_definitions\['(\w+)'\]", action_body)
                component.dep_objects.update(field_deps)
                
                # Extract picklist dependencies
                picklist_deps = re.findall(r"pick_list:\s*:(\w+)", action_body)
                component.dep_picklists.update(picklist_deps)
                
                self.components[action_name] = component
    
    def _extract_methods(self):
        """Extract all methods from the connector"""
        methods_section = re.search(r"methods:\s*\{(.*?)\n\s{2}\},$", self.code, re.DOTALL)
        
        if methods_section:
            methods_code = methods_section.group(1)
            
            # Find each method definition
            for method_match in re.finditer(r"(\w+):\s*lambda[^{]*\{([^}]+(?:\{[^}]*\}[^}]*)*)\}", methods_code, re.DOTALL):
                method_name = method_match.group(1)
                method_body = method_match.group(2)
                
                component = Component(
                    name=method_name,
                    component_type="method"
                )
                
                # Extract method calls
                self._extract_method_calls(method_body, component)
                
                # Check for object definition usage
                obj_refs = re.findall(r"object_definitions\['(\w+)'\]", method_body)
                component.dep_objects.update(obj_refs)
                
                self.components[method_name] = component
    
    def _extract_object_definitions(self):
        """Extract all object definitions"""
        obj_section = re.search(r"object_definitions:\s*\{(.*?)\n\s{2}\},$", self.code, re.DOTALL)
        
        if obj_section:
            obj_code = obj_section.group(1)
            
            for obj_match in re.finditer(r"(\w+):\s*\{", obj_code):
                obj_name = obj_match.group(1)
                
                # Find the complete object definition block
                start_pos = obj_match.end()
                end_pos = self._find_matching_brace(obj_code, start_pos - 1)
                obj_body = obj_code[start_pos:end_pos] if end_pos else ""
                
                component = Component(
                    name=obj_name,
                    component_type="object_def"
                )
                
                # Check for dependencies on other object definitions
                obj_deps = re.findall(r"object_definitions\['(\w+)'\]", obj_body)
                component.dep_objects.update(obj_deps)
                
                # Check for method calls
                self._extract_method_calls(obj_body, component)
                
                self.components[obj_name] = component
    
    def _extract_picklists(self):
        """Extract all picklists"""
        picklist_section = re.search(r"pick_lists:\s*\{(.*?)\n\s{2}\}", self.code, re.DOTALL)
        
        if picklist_section:
            picklist_code = picklist_section.group(1)
            
            for pick_match in re.finditer(r"(\w+):\s*lambda", picklist_code):
                picklist_name = pick_match.group(1)
                
                component = Component(
                    name=picklist_name,
                    component_type="picklist"
                )
                
                # Find method dependencies in picklist
                start_pos = pick_match.end()
                end_pos = self._find_lambda_end(picklist_code, start_pos)
                if end_pos:
                    pick_body = picklist_code[start_pos:end_pos]
                    self._extract_method_calls(pick_body, component)
                
                self.components[picklist_name] = component
    
    def _extract_method_calls(self, code_block: str, component: Component):
        """Extract method calls from a code block"""
        # Pattern for call('method_name', ...)
        call_pattern = r"call\(['\"](\w+)['\"]"
        calls = re.findall(call_pattern, code_block)
        component.dep_methods.update(calls)
        
        # Also track in call graph
        if calls:
            self.call_graph[component.name].update(calls)
    
    def _analyze_dependencies(self):
        """Analyze transitive dependencies and relationships"""
        # This could be extended to include transitive dependency analysis
        pass
    
    def _infer_characteristics(self):
        """Infer characteristics based on code patterns"""
        for name, component in self.components.items():
            code_context = self._get_component_code(name)
            
            # Check for external API calls
            if any(pat in code_context for pat in ['get(', 'post(', 'put(', 'delete(', 'http']):
                component.calls_external_api = "true"
            else:
                component.calls_external_api = "false"
            
            # Check for cache usage
            if 'workato.cache' in code_context:
                component.uses_cache = "true"
            else:
                component.uses_cache = "false"
            
            # Detect retry logic
            if 'retry' in code_context.lower() or 'exponential_backoff' in code_context:
                component.retry_logic = "exponential_backoff"
            elif 'rate_limit' in code_context:
                component.retry_logic = "rate_limit"
            else:
                component.retry_logic = "none"
            
            # Detect error handling
            if 'circuit_breaker' in code_context:
                component.error_handling_type = "circuit_breaker"
            elif 'after_error_response' in code_context:
                component.error_handling_type = "custom"
            elif 'error(' in code_context:
                component.error_handling_type = "throws"
            else:
                component.error_handling_type = "none"
            
            # Performance critical if it's an AI action or batch operation
            if component.component_type == "action" and any(kw in name for kw in ['embedding', 'batch', 'ai_', 'analyze']):
                component.performance_critical = "true"
            else:
                component.performance_critical = "false"
    
    def _get_component_code(self, component_name: str) -> str:
        """Get the code block for a specific component"""
        # This is simplified - would need proper parsing for production
        pattern = rf"{component_name}[:\s].*?\{{.*?\}}"
        match = re.search(pattern, self.code, re.DOTALL)
        return match.group(0) if match else ""
    
    def _find_matching_brace(self, text: str, start: int) -> Optional[int]:
        """Find the matching closing brace"""
        depth = 1
        i = start + 1
        while i < len(text) and depth > 0:
            if text[i] == '{':
                depth += 1
            elif text[i] == '}':
                depth -= 1
            i += 1
        return i if depth == 0 else None
    
    def _find_lambda_end(self, text: str, start: int) -> Optional[int]:
        """Find the end of a lambda block"""
        # Simplified - looks for 'end' or next lambda
        next_lambda = text.find('lambda', start + 1)
        end_pos = text.find('\n    ', start)  # Next dedent
        if next_lambda > 0 and (end_pos < 0 or next_lambda < end_pos):
            return next_lambda
        return end_pos if end_pos > 0 else len(text)
    
    def to_csv(self, filename: str = "connector_components.csv"):
        """Export components to CSV database"""
        with open(filename, 'w', newline='') as csvfile:
            fieldnames = [
                'component', 'component_type', 'dep_methods', 'dep_objects', 
                'dep_picklists', 'calls_external_api', 'uses_cache', 
                'error_handling_type', 'retry_logic', 'auth_required',
                'performance_critical', 'notes'
            ]
            writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
            writer.writeheader()
            
            for component in sorted(self.components.values(), key=lambda x: (x.component_type, x.name)):
                writer.writerow({
                    'component': component.name,
                    'component_type': component.component_type,
                    'dep_methods': ';'.join(sorted(component.dep_methods)),
                    'dep_objects': ';'.join(sorted(component.dep_objects)),
                    'dep_picklists': ';'.join(sorted(component.dep_picklists)),
                    'calls_external_api': component.calls_external_api or '',
                    'uses_cache': component.uses_cache or '',
                    'error_handling_type': component.error_handling_type or '',
                    'retry_logic': component.retry_logic or '',
                    'auth_required': component.auth_required or '',
                    'performance_critical': component.performance_critical or '',
                    'notes': component.notes
                })
    
    def generate_dependency_graph(self) -> Dict:
        """Generate a dependency graph for visualization"""
        graph = {
            "nodes": [],
            "edges": []
        }
        
        for name, component in self.components.items():
            graph["nodes"].append({
                "id": name,
                "type": component.component_type,
                "api_calls": component.calls_external_api == "true",
                "cached": component.uses_cache == "true"
            })
            
            # Add edges for dependencies
            for method in component.dep_methods:
                graph["edges"].append({
                    "source": name,
                    "target": method,
                    "type": "method_call"
                })
            
            for obj in component.dep_objects:
                graph["edges"].append({
                    "source": name,
                    "target": obj,
                    "type": "object_ref"
                })
        
        return graph

# Usage example
def analyze_connector(file_path: str):
    """Main function to analyze a Workato connector"""
    with open(file_path, 'r') as f:
        connector_code = f.read()
    
    analyzer = WorkatoConnectorAnalyzer(connector_code)
    components = analyzer.analyze()
    
    # Export to CSV
    analyzer.to_csv("vertex_ai_connector_components.csv")
    
    # Generate dependency graph
    graph = analyzer.generate_dependency_graph()
    with open("dependency_graph.json", "w") as f:
        json.dump(graph, f, indent=2)
    
    # Print summary statistics
    print(f"Total components: {len(components)}")
    by_type = defaultdict(int)
    for c in components.values():
        by_type[c.component_type] += 1
    
    print("\nComponents by type:")
    for ctype, count in sorted(by_type.items()):
        print(f"  {ctype}: {count}")
    
    # Find most connected components
    connectivity = [(name, len(c.dep_methods) + len(c.dep_objects)) 
                    for name, c in components.items()]
    connectivity.sort(key=lambda x: x[1], reverse=True)
    
    print("\nMost connected components:")
    for name, deps in connectivity[:10]:
        print(f"  {name}: {deps} dependencies")

if __name__ == "__main__":
    analyze_connector("vertex_ai_connector.rb")