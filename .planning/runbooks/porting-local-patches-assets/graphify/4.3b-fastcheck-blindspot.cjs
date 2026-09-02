const fc = require('/Users/rerganian/Documents/git/personal/gsd-core/node_modules/fast-check');
fc.configureGlobal({ numRuns: 200, seed: 42 });

const arbGraph = fc
  .array(
    fc.record({
      label: fc.string({ minLength: 1, maxLength: 6 }),
      type: fc.constantFrom('module', 'service', 'doc'),
    }),
    { minLength: 0, maxLength: 8 },
  )
  .map((extra) => {
    const nodes = [
      { id: 'n0', label: 'AuthService', description: 'handles authentication', type: 'service' },
      ...extra.map((n, i) => ({ id: `n${i + 1}`, label: n.label, description: '', type: n.type })),
    ];
    return { nodes };
  });

let hitCount = 0, maxSeeds = 1;
fc.assert(
  fc.property(arbGraph, (graph) => {
    const seedCount = graph.nodes.filter(n => n.label.toLowerCase().includes('auth')).length;
    if (seedCount > 1) { hitCount++; maxSeeds = Math.max(maxSeeds, seedCount); }
    return true; // never fail; just observe
  }),
);
console.log('Runs where extra generated label matched "auth" (>=2 total seeds):', hitCount, '/ 200');
console.log('max seeds seen in any single run:', maxSeeds);
