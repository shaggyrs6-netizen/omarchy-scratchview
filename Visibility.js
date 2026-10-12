function shouldHide(initial, previousCount, count, explicitRestore) {
    return count === 0 && ((initial && !explicitRestore) || (!initial && previousCount > 0));
}
