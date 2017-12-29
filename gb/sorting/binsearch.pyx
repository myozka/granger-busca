# -*- coding: utf8

from libcpp cimport bool
from libcpp.vector cimport vector


cdef int searchsorted(vector[double] &array, double value, int lower) nogil:
    '''
    Finds the first element in the array where the given is OR should have been
    in the given array. This is simply a binary search, but if the element is
    not found we return the index where it should have been at.

    Parameters
    ----------
    array: vector of doubles
    value: double to look for
    lower: int to start search from [lower, n)
    '''

    cdef int upper = array.size() - 1  # closed interval
    cdef int half = 0
    cdef int idx = -1

    while upper >= lower:
        half = lower + ((upper - lower) // 2)
        if value == array[half]:
            idx = half
            break
        elif value > array[half]:
            lower = half + 1
        else:
            upper = half - 1

    if idx == -1:  # Element not found, return where it should be
        idx = lower

    return idx


def _searchsorted(double[::1] array, double value, int lower=0):
    cdef vector[double] copy
    cdef int i
    for i in range(array.shape[0]):
        copy.push_back(array[i])
    return searchsorted(copy, value, lower)