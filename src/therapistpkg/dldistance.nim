import sequtils
import strformat
import strutils
import tables
import unicode

type Matrix = seq[seq[int]]

proc `$`(matrix: Matrix): string =
    for row in matrix:
        result &= row.join(", ") & "\n"

type
    List[T] = concept list
        list[int] is T 
        len(list) is Ordinal

proc damerau_levenshtein_distance[C](a: List[C], b: List[C]): int =
    ## Ported from https://gist.github.com/badocelot/5327337

    # 'Infinite' row exists to simplify implementation by having a high cost
    # default row we can use to prevent transpositions where the character
    # hasn't been seen
    let inf = len(a) + len(b)

    # Matrix: (len(a) + 2) x (len(b) + 2)
    var matrix: Matrix
    matrix &= repeat(inf, len(b)+2)
    matrix &= @[inf] & toSeq(0..len(b))
    for i in 1..len(a):
        matrix &= @[inf, i] & repeat(0, len(b))
    
    var last_row = initTable[C, int]()

    for row in 1..len(a):
        # echo $matrix
        # Current character in `a`
        let ch_a = a[row-1]

        # Column of last match on this row: `DB` in pseudocode
        var last_match_col = 0

        for col in 1..len(b):
            # Current character in `b`
            let ch_b = b[col-1]

            # Last row with matching character -> row 0 is the infinite row => no match
            let last_matching_row = last_row.getOrDefault(ch_b, 0)

            # Cost of substitution
            let cost = if ch_a == ch_b: 0 else: 1

            # Compute substring distance

            # We are scanning across the cells filling from top to bottom and left to right. To get value of the next cell, we pick the cheapest of:
            matrix[row+1][col+1] = min([
                # Substitution -> one more than diagonally above
                matrix[row][col] + cost, 
                # Addition -> one more than to the left
                matrix[row+1][col] + 1,  
                # Deletion -> one more than the one above
                matrix[row][col+1] + 1,  
                # Swap it -> swap with the previous occurence and take the distance between the two
                matrix[last_matching_row][last_match_col] + (row - last_matching_row - 1) + 1 + (col - last_match_col - 1)  
            ])

            # If there was a match, update last_match_col
            # Doing this here lets me be rid of the `j1` variable from the original pseudocode
            if cost == 0:
                last_match_col = col

        # Update last row for current character
        last_row[ch_a] = row

    # Return last element
    # echo $matrix
    matrix[len(a)+1][len(b)+1]

proc damerau_levenshtein_distance_ascii*(a: string, b: string, ignoreCase=true): int = 
    ## Calculates distance considering each string as a list of bytes
    if ignoreCase:
        damerau_levenshtein_distance(a.toLowerAscii, b.toLowerAscii)
    else:
        damerau_levenshtein_distance(a, b)

proc damerau_levenshtein_distance*(a: string, b: string, ignoreCase=true): int = 
    ## Calculates distance considering each string as a list of runes
    if ignoreCase:
        damerau_levenshtein_distance(map(a.toRunes(), toLower), map(b.toRunes(), toLower))
    else:
        damerau_levenshtein_distance(a.toRunes(), b.toRunes())

proc dldistance*(a: string, b: string, ignoreCase=true): int = 
    ## Alias for damerau_levenshtein_distance
    damerau_levenshtein_distance(a, b, ignoreCase)