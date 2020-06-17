import unittest

import ../src/therapist

if isMainModule:
    suite "Compare distances":
        test "Ascii":
            check(damerau_levenshtein_distance_ascii("cat", "cats")==1)
            check(damerau_levenshtein_distance_ascii("cat", "ca")==1)
            check(damerau_levenshtein_distance_ascii("cat", "bat")==1)
            check(damerau_levenshtein_distance_ascii("crocodile", "alligator")==9)
            check(damerau_levenshtein_distance_ascii("update", "updaet")==1)
            check(damerau_levenshtein_distance_ascii("αlpha", "alpha")==2)
        
        test "Unicode":
            check(damerau_levenshtein_distance("αlpha", "alpha")==1)