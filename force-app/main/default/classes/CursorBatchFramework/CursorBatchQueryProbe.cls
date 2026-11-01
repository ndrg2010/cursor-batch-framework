/**
 * @description Builds the existence check CursorBatchCoordinator runs before Database.getCursor().
 *              Salesforce allows 10,000 Apex cursors per rolling 24 hours, and a polling job whose
 *              query matches nothing still spends one. The probe is the cursor query itself with
 *              its top-level ORDER BY removed and its LIMIT forced to 1 (or added), so an empty
 *              run can complete without creating a cursor.
 *
 *              Everything else is kept verbatim, including the select list, WITH clauses, OFFSET,
 *              FOR and ALL ROWS, so the probe matches exactly the rows the cursor would. ORDER BY
 *              is dropped because sorting cannot change whether a row exists and is the main cost
 *              of a LIMIT 1 query that does match.
 * @group CursorBatchFramework
 * @see CursorBatchCoordinator
 */
public without sharing class CursorBatchQueryProbe {

    private static final Integer QUOTE = 39;
    private static final Integer BACKSLASH = 92;
    private static final Integer OPEN_PAREN = 40;
    private static final Integer CLOSE_PAREN = 41;
    private static final Integer UNDERSCORE = 95;
    private static final Integer DOT = 46;

    /**
     * @description Derives the probe from a cursor query. Only clauses at the top level of the
     *              statement are touched; subqueries and string literals are skipped.
     * @param query Cursor query with inline values
     * @return The probe query, or null when the query has no top-level FROM or its LIMIT is not
     *         a number
     */
    public static String buildProbeQuery(String query) {
        if (String.isBlank(query)) {
            return null;
        }
        List<Word> words = topLevelWords(query);
        Integer fromIndex;
        for (Integer i = 0; i < words.size(); i++) {
            if (words[i].text == 'FROM') {
                fromIndex = i;
                break;
            }
        }
        if (fromIndex == null) {
            return null;
        }

        Integer orderByStart;
        Integer orderByEnd;
        Integer limitStart;
        Integer limitEnd;
        Integer limitValue;
        Integer insertLimitAt;
        for (Integer i = fromIndex + 1; i < words.size(); i++) {
            Word word = words[i];
            String next = i + 1 < words.size() ? words[i + 1].text : null;
            if (orderByStart == null && word.text == 'ORDER' && next == 'BY') {
                orderByStart = word.position;
                continue;
            }
            if (!startsClauseAfterOrderBy(word.text, next)) {
                continue;
            }
            if (orderByStart != null && orderByEnd == null) {
                orderByEnd = word.position;
            }
            if (word.text == 'LIMIT' && limitStart == null) {
                if (next == null || !next.isNumeric()) {
                    return null;
                }
                limitStart = word.position;
                limitEnd = words[i + 1].position + next.length();
                limitValue = Integer.valueOf(next);
            } else if (word.text != 'LIMIT' && insertLimitAt == null && limitStart == null) {
                insertLimitAt = word.position;
            }
        }
        if (orderByStart != null && orderByEnd == null) {
            orderByEnd = query.length();
        }

        String probe = query;
        if (limitStart != null) {
            probe = probe.left(limitStart) + 'LIMIT ' + Math.min(limitValue, 1) + probe.substring(limitEnd);
        } else if (insertLimitAt != null) {
            probe = probe.left(insertLimitAt) + 'LIMIT 1 ' + probe.substring(insertLimitAt);
        } else {
            probe = probe + ' LIMIT 1';
        }
        if (orderByStart != null) {
            String before = probe.left(orderByStart);
            String after = probe.substring(orderByEnd);
            if (before.right(1).isWhitespace()) {
                after = after.replaceFirst('^\\s+', '');
            }
            probe = before + after;
        }
        return probe.trim();
    }

    private static Boolean startsClauseAfterOrderBy(String word, String next) {
        switch on word {
            when 'LIMIT', 'OFFSET' {
                return true;
            }
            when 'FOR' {
                return next == 'VIEW' || next == 'UPDATE' || next == 'REFERENCE';
            }
            when 'UPDATE' {
                return next == 'TRACKING' || next == 'VIEWSTAT';
            }
            when 'ALL' {
                return next == 'ROWS';
            }
            when else {
                return false;
            }
        }
    }

    private static List<Word> topLevelWords(String query) {
        List<Word> words = new List<Word>();
        Integer length = query.length();
        Integer depth = 0;
        Boolean inString = false;
        Integer i = 0;
        while (i < length) {
            Integer c = query.charAt(i);
            if (inString) {
                if (c == BACKSLASH) {
                    i++;
                } else if (c == QUOTE) {
                    inString = false;
                }
                i++;
                continue;
            }
            if (isWordChar(c)) {
                Integer start = i;
                while (i < length && isWordChar(query.charAt(i))) {
                    i++;
                }
                if (depth == 0) {
                    words.add(new Word(query.substring(start, i).toUpperCase(), start));
                }
                continue;
            }
            if (c == QUOTE) {
                inString = true;
            } else if (c == OPEN_PAREN) {
                depth++;
            } else if (c == CLOSE_PAREN) {
                depth--;
            }
            i++;
        }
        return words;
    }

    private static Boolean isWordChar(Integer c) {
        return (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || (c >= 48 && c <= 57) ||
            c == UNDERSCORE || c == DOT;
    }

    private class Word {
        final String text;
        final Integer position;

        Word(String text, Integer position) {
            this.text = text;
            this.position = position;
        }
    }
}
