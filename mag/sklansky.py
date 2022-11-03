

#
#

"""BK / SK prefix adder"""

import networkx as nx

from sympy import symbols, Symbol
from sympy.logic import boolalg
w = 4
x = symbols(f'x:{w}')
y = symbols(f'y:{w}')
print(x)
print(y)
p, g = zip(*[(xi ^ yi, xi & yi) for xi, yi in zip(x, y)])


p_syms = symbols(f'p:{w}')
g_syms = symbols(f'g:{w}')

c_syms = [g_syms[0]]
for i in range(w-1):
    c_syms.append(boolalg.to_anf(g_syms[i+1] | (p_syms[i+1] & Symbol(f'c{i}')), deep=False))
print(c_syms)
print(c_syms[1])
print(boolalg.simplify_logic(c_syms[1]))
exit(1)


dag = nx.OrderedDiGraph()

res = nx.DiGraph()
# Create nodes in new DAG as edges in original DAG
res.add_nodes_from(list(dag.edges()))
sorted_res_nodes = sorted(res.nodes, key=lambda x: x[1])

# Connect all nodes with end of node1 is equal to start of node2
for n1 in sorted_res_nodes:
    for n2 in sorted_res_nodes:
        if n1[1] == n2[0]:
            res.add_edge(n1, n2)

# # Draw graphs
# nx.draw(
#     dag,
#     with_labels=True,
#     pos=nx.drawing.nx_agraph.graphviz_layout(
#         dag, prog='dot'
#     )
# )
nx.draw(
    res,
    with_labels=True,
    pos=nx.drawing.nx_agraph.graphviz_layout(
        res, prog='dot'
    )
)
