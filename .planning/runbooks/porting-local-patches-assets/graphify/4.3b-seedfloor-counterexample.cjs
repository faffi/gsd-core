const { seedAndExpand, applyBudget } = require('/Users/rerganian/.claude/gsd-core/bin/lib/graphify.cjs');

const nodes = [
    { id: 'n0', label: 'AuthService', description: 'handles authentication', type: 'service' },
    { id: 'n1', label: 'auth', description: '', type: 'module' },       // exact match, score 5
    { id: 'n2', label: 'xzqvwk', description: '', type: 'doc' },
];
const edges = [
    { source: 'n0', target: 'n1', label: 'e0', confidence: 'AMBIGUOUS' },
    { source: 'n1', target: 'n2', label: 'e1', confidence: 'INFERRED' },
];
const graph = { nodes, edges };

const result = seedAndExpand(graph, 'auth');
console.log('seeds:', [...result.seeds]);

for (const budget of [0, 30, 60, 90, 120, 150, 5000]) {
    const r = applyBudget(result, budget, 'auth');
    const n0survives = r.nodes.some(n => n.id === 'n0');
    console.log(`budget=${budget}\ttotal_nodes=${r.total_nodes}\tn0 (AuthService) survives? ${n0survives}\tnode ids: ${r.nodes.map(n=>n.id).join(',')}`);
}
