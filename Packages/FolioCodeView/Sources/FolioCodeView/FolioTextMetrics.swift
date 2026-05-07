enum FolioTextMetrics {
    static func lineCount(in text: String) -> Int {
        var count = 1
        for unit in text.utf8 where unit == 0x0A {
            count += 1
        }
        return count
    }
}
