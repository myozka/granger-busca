# -*- coding: utf8
# cython: boundscheck=False
# cython: cdivision=True
# cython: initializedcheck=False
# cython: nonecheck=False
# cython: wraparound=False


from gb.kernels cimport AbstractKernel
from gb.kernels cimport PoissonKernel
from gb.kernels cimport BuscaKernel
from gb.kernels cimport TruncatedHawkesKernel

from gb.randomkit.random cimport rand

from gb.samplers cimport AbstractSampler
from gb.samplers cimport BaseSampler
from gb.samplers cimport CollapsedGibbsSampler
from gb.samplers cimport FenwickSampler

from gb.stamps cimport Timestamps

from gb.sloppy cimport SloppyCounter

from libc.stdint cimport uint64_t
from libc.stdio cimport printf

from libcpp.unordered_map cimport unordered_map
from libcpp.vector cimport vector

import numpy as np


cdef void sample_alpha(size_t proc_a, Timestamps all_stamps,
                       AbstractSampler sampler,  AbstractKernel kernel) nogil:
    cdef size_t i
    cdef size_t influencer
    cdef size_t new_influencer
    cdef size_t n_proc = all_stamps.num_proc()

    cdef double[::1] stamps = all_stamps.get_stamps(proc_a)
    cdef size_t[::1] causes = all_stamps.get_causes(proc_a)

    cdef double prev_back_t = 0      # stores last known background time stamp
    cdef double prev_back_t_aux = 0  # every it: prev_back_t = prev_back_t_aux
    for i in range(<size_t>stamps.shape[0]):
        influencer = causes[i]
        if influencer == n_proc:
            prev_back_t_aux = stamps[i] # found a background ts
        else:
            sampler.dec_one(influencer)

        if rand() < kernel.background_probability(stamps[i] - prev_back_t):
            new_influencer = n_proc
        else:
            new_influencer = sampler.sample_for_idx(i, kernel)

        if new_influencer != n_proc:
            sampler.inc_one(new_influencer)
        causes[i] = new_influencer
        prev_back_t = prev_back_t_aux


cdef void do_work(Timestamps all_stamps, SloppyCounter sloppy,
                  AbstractSampler sampler, AbstractKernel kernel,
                  size_t n_iter, size_t worker_id, size_t[::1] workload) nogil:

    cdef size_t iteration
    cdef size_t proc_a, i
    for iteration in range(n_iter):
        for i in range(<size_t>workload.shape[0]):
            proc_a = workload[i]
            sampler.set_current_process(proc_a)
            kernel.set_current_process(proc_a)
            sample_alpha(proc_a, all_stamps, sampler, kernel)
        sloppy.update_counts(worker_id)


def fit(Timestamps all_stamps, SloppyCounter sloppy, double alpha_prior,
        size_t n_iter, size_t worker_id, size_t[::1] workload,
        int metropolis_walker=True):

    cdef size_t n_proc = all_stamps.num_proc()
    cdef BaseSampler base_sampler = BaseSampler(all_stamps, sloppy, worker_id,
                                                alpha_prior)
    cdef AbstractSampler sampler
    if metropolis_walker == 1:
        sampler = FenwickSampler(base_sampler, n_proc)
    else:
        sampler = CollapsedGibbsSampler(base_sampler, n_proc)

    cdef PoissonKernel poisson = PoissonKernel(all_stamps, n_proc)
    cdef AbstractKernel kernel = BuscaKernel(poisson, n_proc)

    cdef unordered_map[int, unordered_map[int, int]] Alpha
    cdef unordered_map[int, unordered_map[int, double]] Beta
    cdef unordered_map[int, vector[int]] curr_state

    cdef size_t a, b, i, j
    cdef size_t[::1] causes
    cdef int[::1] num_background = np.zeros(n_proc, dtype='i')

    printf("Worker %lu starting\n", worker_id)
    with nogil:
        do_work(all_stamps, sloppy, sampler, kernel, n_iter, worker_id,
                workload)

        for i in range(<size_t>workload.shape[0]):
            a = workload[i]
            causes = all_stamps.get_causes(a)
            curr_state[a].resize(causes.shape[0])
            for j in range(<size_t>causes.shape[0]):
                b = causes[j]
                curr_state[a][j] = b
                if b != n_proc:
                    if Alpha[a].count(b) == 0:
                        Alpha[a][b] = 0
                    Alpha[a][b] += 1
                else:
                    num_background[a] += 1

            kernel.set_current_process(a)
            for b in range(n_proc):
                if Alpha[a].count(b) != 0:
                    Beta[a][b] = kernel.get_beta_rates()[b]
    printf("Worker %lu done\n", worker_id)

    return Alpha, np.asanyarray(poisson.get_mu_rates()), Beta, \
        np.asanyarray(num_background), curr_state
