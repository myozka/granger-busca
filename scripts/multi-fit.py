from gb import GrangerBusca
from gb import simulate

Alpha = [[0.5, 0.5, 0, 0],
         [0,   1,   0, 0],
         [0,   0,   0.5, 0.5],
         [0,   0,   0, 1]]
sim = simulate.GrangeBuscaSimulator([0.01]*4, [2, 10, 20, 30], Alpha)
ticks = sim.simulate(50000)

granger_model = GrangerBusca(alpha_p=1.0/len(ticks), num_iter=300, burn_in=200)
granger_model.fit(ticks)
print(granger_model.mu_)
print(granger_model.back_)
print(granger_model.Alpha_.toarray())