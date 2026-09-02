const fs = require('fs');
const graph = JSON.parse(fs.readFileSync('/Users/rerganian/Documents/git/bootstrap-terraform/.planning/graphs/graph.json', 'utf8'));

const pristine = require('/tmp/gsd-norm/gsd-core/bin/lib/graphify.cjs');
const patched = require('/Users/rerganian/.claude/gsd-core/bin/lib/graphify.cjs');

// Claim 3 "before" number: real pre-patch floor cost on the CURRENT corpus,
// budget 2000 (the planner's stated budget), same tree version otherwise.
{
    const rP = pristine.seedAndExpand(graph, 'auth');
    const bP = pristine.applyBudget(rP, 2000, 'auth');
    console.log('PRISTINE  budget=2000  seeds=%d  total_nodes=%d  total_edges=%d  budget_met=%s  estimate=%d',
        rP.seeds.size, bP.total_nodes, bP.total_edges, bP.budget_met, bP.budget_estimate);
}
// Same, patched (497-line file has different exports? check same signature)
{
    const rQ = patched.seedAndExpand(graph, 'auth');
    const bQ = patched.applyBudget(rQ, 2000, 'auth');
    console.log('PATCHED   budget=2000  seeds=%d  total_nodes=%d  total_edges=%d  budget_met=%s  estimate=%d',
        rQ.seeds.size, bQ.total_nodes, bQ.total_edges, bQ.budget_met, bQ.budget_estimate);
}

// Claim 1 "no-op above the cliff": generous budget, pristine vs patched, diff.
{
    const rP = pristine.seedAndExpand(graph, 'oidc');
    const bP = pristine.applyBudget(rP, 5_000_000, 'oidc');
    const rQ = patched.seedAndExpand(graph, 'oidc');
    const bQ = patched.applyBudget(rQ, 5_000_000, 'oidc');
    const same = JSON.stringify(bP.nodes) === JSON.stringify(bQ.nodes) && JSON.stringify(bP.edges) === JSON.stringify(bQ.edges);
    console.log('\nAt a budget above the full unbudgeted payload (oidc): identical nodes+edges? %s', same);
    console.log('pristine: nodes=%d edges=%d budget_met=%s', bP.total_nodes, bP.total_edges, bP.budget_met);
    console.log('patched:  nodes=%d edges=%d budget_met=%s', bQ.total_nodes, bQ.total_edges, bQ.budget_met);
}
