import pandas as pd
import json
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import networkx as nx
from collections import Counter
import numpy as np

class ConnectorAnalytics:
    def __init__(self, csv_path, json_path):
        self.df = pd.read_csv(csv_path)
        with open(json_path, 'r') as f:
            self.graph_data = json.load(f)
        
        # Parse dependency columns
        self.df['method_count'] = self.df['dep_methods'].fillna('').apply(lambda x: len(x.split(';')) if x else 0)
        self.df['object_count'] = self.df['dep_objects'].fillna('').apply(lambda x: len(x.split(';')) if x else 0)
        self.df['picklist_count'] = self.df['dep_picklists'].fillna('').apply(lambda x: len(x.split(';')) if x else 0)
        self.df['total_deps'] = self.df['method_count'] + self.df['object_count'] + self.df['picklist_count']
    
    def basic_stats(self):
        """Generate basic statistics"""
        stats = {
            'Component Type Distribution': self.df['component_type'].value_counts().to_dict(),
            'API Calling Components': self.df[self.df['calls_external_api'] == 'true']['component'].tolist(),
            'Cached Components': self.df[self.df['uses_cache'] == 'true']['component'].tolist(),
            'Average Dependencies': {
                'Overall': self.df['total_deps'].mean(),
                'By Type': self.df.groupby('component_type')['total_deps'].mean().to_dict()
            },
            'Most Connected': self.df.nlargest(10, 'total_deps')[['component', 'component_type', 'total_deps']].to_dict('records'),
            'Isolated Components': self.df[self.df['total_deps'] == 0]['component'].tolist()
        }
        return stats
    
    def complexity_analysis(self):
        """Analyze connector complexity"""
        metrics = {}
        
        # Build graph for analysis
        G = self.build_dependency_graph()
        metrics['graph_density'] = nx.density(G) if len(G) > 0 else 0
        metrics['strongly_connected_components'] = nx.number_strongly_connected_components(G) if len(G) > 0 else 0
        
        # Find potential bottlenecks (high betweenness centrality)
        if len(G) > 0:
            centrality = nx.betweenness_centrality(G)
            metrics['bottlenecks'] = sorted(centrality.items(), key=lambda x: x[1], reverse=True)[:5]
        
        # Coupling analysis
        metrics['avg_coupling'] = self.df['method_count'].mean()
        metrics['max_coupling'] = self.df['method_count'].max()
        
        return metrics
    
    def build_dependency_graph(self):
        """Build NetworkX graph from dependencies"""
        G = nx.DiGraph()
        
        for edge in self.graph_data.get('edges', []):
            G.add_edge(edge['source'], edge['target'], type=edge['type'])
        
        for node in self.graph_data.get('nodes', []):
            G.add_node(node['id'], **{k:v for k,v in node.items() if k != 'id'})
        
        return G

class ConnectorVisualizer:
    def __init__(self, analytics):
        self.analytics = analytics
        self.df = analytics.df
        # Set up matplotlib style
        plt.style.use('default')
        plt.rcParams['figure.facecolor'] = 'white'
        plt.rcParams['axes.facecolor'] = 'white'
        plt.rcParams['axes.grid'] = True
        plt.rcParams['grid.alpha'] = 0.3
    
    def plot_component_distribution(self, save_path='component_distribution.png'):
        """Pie charts of component and dependency types"""
        fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))
        
        # Component type distribution
        type_counts = self.df['component_type'].value_counts()
        colors1 = plt.cm.Set3(np.linspace(0, 1, len(type_counts)))
        wedges1, texts1, autotexts1 = ax1.pie(type_counts.values, 
                                                labels=type_counts.index, 
                                                autopct='%1.1f%%',
                                                colors=colors1)
        ax1.set_title('Component Type Distribution', fontsize=14, fontweight='bold')
        
        # Dependency type distribution
        total_methods = self.df['method_count'].sum()
        total_objects = self.df['object_count'].sum()
        total_picklists = self.df['picklist_count'].sum()
        
        colors2 = ['#ff9999', '#66b3ff', '#99ff99']
        wedges2, texts2, autotexts2 = ax2.pie([total_methods, total_objects, total_picklists], 
                                                labels=['Methods', 'Objects', 'Picklists'],
                                                autopct='%1.1f%%',
                                                colors=colors2)
        ax2.set_title('Dependency Type Distribution', fontsize=14, fontweight='bold')
        
        plt.tight_layout()
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        plt.show()
        return fig
    
    def plot_dependency_heatmap(self, save_path='dependency_heatmap.png'):
        """Heatmap of dependencies by component type using matplotlib only"""
        pivot = self.df.groupby('component_type')[['method_count', 'object_count', 'picklist_count']].mean()
        
        fig, ax = plt.subplots(figsize=(10, 6))
        
        # Create heatmap using imshow
        data = pivot.T.values
        im = ax.imshow(data, cmap='YlOrRd', aspect='auto')
        
        # Set ticks and labels
        ax.set_xticks(np.arange(len(pivot.index)))
        ax.set_yticks(np.arange(len(pivot.columns)))
        ax.set_xticklabels(pivot.index)
        ax.set_yticklabels(['Methods', 'Objects', 'Picklists'])
        
        # Rotate the tick labels
        plt.setp(ax.get_xticklabels(), rotation=45, ha="right", rotation_mode="anchor")
        
        # Add colorbar
        cbar = plt.colorbar(im, ax=ax)
        cbar.set_label('Average Count', rotation=270, labelpad=15)
        
        # Add text annotations
        for i in range(len(pivot.columns)):
            for j in range(len(pivot.index)):
                text = ax.text(j, i, f'{data[i, j]:.1f}',
                             ha="center", va="center", color="black")
        
        ax.set_title('Average Dependencies by Component Type', fontsize=14, fontweight='bold')
        ax.set_xlabel('Component Type')
        ax.set_ylabel('Dependency Type')
        
        plt.tight_layout()
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        plt.show()
        return fig
    
    def plot_dependency_network(self, save_path='dependency_network.png', filter_isolated=True, max_nodes=100):
        """Network visualization of dependencies"""
        G = self.analytics.build_dependency_graph()
        
        # Filter for visualization
        if filter_isolated:
            G.remove_nodes_from(list(nx.isolates(G)))
        
        # Limit nodes for large graphs
        if len(G) > max_nodes:
            # Keep only the most connected nodes
            degree_dict = dict(G.degree())
            top_nodes = sorted(degree_dict.items(), key=lambda x: x[1], reverse=True)[:max_nodes]
            G = G.subgraph([n for n, d in top_nodes])
        
        if len(G) == 0:
            print("No connected components to visualize")
            return None
        
        fig, ax = plt.subplots(figsize=(20, 15))
        
        # Layout
        pos = nx.spring_layout(G, k=2, iterations=50, seed=42)
        
        # Color mapping by component type
        color_map = {
            'action': '#87CEEB',      # light blue
            'method': '#90EE90',      # light green
            'object_def': '#FFFFE0',  # light yellow
            'picklist': '#FFB6C1'     # light coral
        }
        
        node_colors = []
        for node in G.nodes():
            if node in self.df['component'].values:
                comp_type = self.df[self.df['component'] == node]['component_type'].iloc[0]
                node_colors.append(color_map.get(comp_type, '#D3D3D3'))
            else:
                node_colors.append('#D3D3D3')
        
        # Draw network
        nx.draw_networkx_nodes(G, pos, node_color=node_colors, node_size=300, alpha=0.9, ax=ax)
        nx.draw_networkx_edges(G, pos, alpha=0.5, arrows=True, ax=ax, edge_color='gray', arrowsize=10)
        nx.draw_networkx_labels(G, pos, font_size=8, ax=ax)
        
        # Add legend
        legend_elements = [mpatches.Patch(color=color, label=comp_type.replace('_', ' ').title()) 
                          for comp_type, color in color_map.items()]
        ax.legend(handles=legend_elements, loc='upper left')
        
        ax.set_title('Component Dependency Network', fontsize=16, fontweight='bold')
        ax.axis('off')
        
        plt.tight_layout()
        plt.savefig(save_path, dpi=200, bbox_inches='tight')
        plt.show()
        return fig
    
    def plot_complexity_metrics(self, save_path='complexity_metrics.png'):
        """Bar charts of complexity metrics"""
        fig, axes = plt.subplots(2, 2, figsize=(14, 10))
        
        # Top 10 most complex components
        top_complex = self.df.nlargest(10, 'total_deps')
        y_pos = np.arange(len(top_complex))
        
        bars1 = axes[0, 0].barh(y_pos, top_complex['total_deps'].values, color='steelblue')
        axes[0, 0].set_yticks(y_pos)
        axes[0, 0].set_yticklabels(top_complex['component'].values)
        axes[0, 0].set_xlabel('Total Dependencies')
        axes[0, 0].set_title('Top 10 Most Complex Components', fontweight='bold')
        axes[0, 0].grid(axis='x', alpha=0.3)
        
        # Dependencies by type
        by_type = self.df.groupby('component_type')['total_deps'].mean().sort_values()
        x_pos = np.arange(len(by_type))
        
        bars2 = axes[0, 1].bar(x_pos, by_type.values, color='coral')
        axes[0, 1].set_xticks(x_pos)
        axes[0, 1].set_xticklabels(by_type.index, rotation=45, ha='right')
        axes[0, 1].set_ylabel('Average Dependencies')
        axes[0, 1].set_title('Average Complexity by Type', fontweight='bold')
        axes[0, 1].grid(axis='y', alpha=0.3)
        
        # API vs non-API components
        api_df = self.df.copy()
        api_df['has_api'] = api_df['calls_external_api'] == 'true'
        api_comparison = api_df.groupby('has_api')['total_deps'].mean()
        
        bars3 = axes[1, 0].bar(['No API', 'Has API'], 
                               [api_comparison.get(False, 0), api_comparison.get(True, 0)],
                               color=['lightgreen', 'salmon'])
        axes[1, 0].set_ylabel('Average Dependencies')
        axes[1, 0].set_title('Complexity: API vs Non-API Components', fontweight='bold')
        axes[1, 0].grid(axis='y', alpha=0.3)
        
        # Error handling distribution
        error_types = self.df['error_handling_type'].value_counts()
        colors4 = plt.cm.Pastel1(np.linspace(0, 1, len(error_types)))
        
        wedges, texts, autotexts = axes[1, 1].pie(error_types.values, 
                                                   labels=error_types.index, 
                                                   autopct='%1.1f%%',
                                                   colors=colors4)
        axes[1, 1].set_title('Error Handling Strategies', fontweight='bold')
        
        plt.suptitle('Connector Complexity Analysis', fontsize=16, fontweight='bold', y=1.02)
        plt.tight_layout()
        plt.savefig(save_path, dpi=150, bbox_inches='tight')
        plt.show()
        return fig

def generate_analysis_report(csv_path, json_path, output_dir='.'):
    """Generate complete analysis with visualizations"""
    
    # Initialize analytics
    analytics = ConnectorAnalytics(csv_path, json_path)
    viz = ConnectorVisualizer(analytics)
    
    # Generate statistics
    stats = analytics.basic_stats()
    complexity = analytics.complexity_analysis()
    
    # Create visualizations
    print("Generating visualizations...")
    viz.plot_component_distribution(f'{output_dir}/component_distribution.png')
    viz.plot_dependency_heatmap(f'{output_dir}/dependency_heatmap.png')
    viz.plot_complexity_metrics(f'{output_dir}/complexity_metrics.png')
    
    # Only plot network for smaller connectors
    if len(analytics.df) < 200:
        viz.plot_dependency_network(f'{output_dir}/dependency_network.png')
    
    # Generate markdown report
    with open(f'{output_dir}/analysis_report.md', 'w') as f:
        f.write("# Connector Analysis Report\n\n")
        
        f.write("## Summary Statistics\n\n")
        f.write(f"- Total Components: {len(analytics.df)}\n")
        f.write(f"- Average Dependencies: {stats['Average Dependencies']['Overall']:.2f}\n")
        f.write(f"- API-calling Components: {len(stats['API Calling Components'])}\n")
        f.write(f"- Cached Components: {len(stats['Cached Components'])}\n\n")
        
        f.write("## Complexity Metrics\n\n")
        f.write(f"- Graph Density: {complexity.get('graph_density', 0):.3f}\n")
        f.write(f"- Strongly Connected Components: {complexity.get('strongly_connected_components', 0)}\n")
        f.write(f"- Average Coupling: {complexity.get('avg_coupling', 0):.2f}\n\n")
        
        f.write("## Most Complex Components\n\n")
        for comp in stats['Most Connected'][:5]:
            f.write(f"- {comp['component']} ({comp['component_type']}): {comp['total_deps']} dependencies\n")
        
        if complexity.get('bottlenecks'):
            f.write("\n## Potential Bottlenecks\n\n")
            for name, score in complexity['bottlenecks']:
                f.write(f"- {name}: centrality score {score:.3f}\n")
    
    print(f"Analysis complete! Check {output_dir} for reports and visualizations.")
    
    return analytics, viz
